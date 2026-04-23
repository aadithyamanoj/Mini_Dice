// =============================================================================
// tb_mini_dice.sv
//
// Top-level testbench for mini_dice (dice_core + cgra_io_axi4_top + cgra_io_csr).
//
// Flow:
//   1. Bring up reset + bsg_link.
//   2. DPI loads test-vector collateral (CTA desc mem, meta mem, bitstream mem,
//      runtime JSON with CSR values + expected writes).
//   3. External "RX" agent (this TB's FPGA AXI master) writes csrX0..7 and
//      start_pc into cgra_io_csr, then pulses the start bit — that is what
//      hands control to dice_core.
//   4. dice_core's mfetch / bsfetch / dfetch requests traverse the crossbar
//      and bsg_link DDR.  A second top_level_io instance sits on the physical
//      pins as the "FPGA endpoint"; its memory model answers reads from the
//      DPI meta/bitstream stores and forwards writes to the DPI write
//      recorder.
//   5. After a bounded settle window the DPI verifier reports PASS/FAIL.
//
// Note: dfetch path is wired end-to-end but the DUT-side dfetch may still be
// in-flight work — the TB records whatever reaches the FPGA endpoint and
// relies on dice_core_tb_check_done() to report mismatches.
// =============================================================================

`timescale 1ns/1ps

import "DPI-C" context function void dice_core_tb_init(
  input string cta_desc_mem_file,
  input string meta_mem_file,
  input string bitstream_mem_file,
  input string runtime_json_file
);
import "DPI-C" context function int unsigned dice_core_tb_has_init_error();
import "DPI-C" context function string dice_core_tb_get_init_error();
import "DPI-C" context function int unsigned dice_core_tb_get_csr(input int unsigned csr_idx);
import "DPI-C" context function int unsigned dice_core_tb_meta_read16(input int unsigned byte_addr);
import "DPI-C" context function int unsigned dice_core_tb_meta_read32(input int unsigned byte_addr);
import "DPI-C" context function int unsigned dice_core_tb_bitstream_read16(
  input int unsigned byte_addr
);
import "DPI-C" context function int unsigned dice_core_tb_bitstream_read32(
  input int unsigned byte_addr
);
import "DPI-C" context function int unsigned dice_core_tb_axi_read16(
  input int unsigned addr
);
import "DPI-C" context function void dice_core_tb_record_axi_write(
  input int unsigned addr,
  input int unsigned data,
  input int unsigned strb
);
import "DPI-C" context function int unsigned dice_core_tb_check_done();

`include "dice_define.vh"

module tb_mini_dice;
  import dice_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;
  import axi_pkg::*;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam int AW           = 16;
  localparam int DW           = 32;
  localparam int FW           = 32;
  localparam int CW           = 8;
  localparam int CLK_HALF_NS  = 5;   // 100 MHz core clock
  localparam int TIMEOUT_CYC  = 2000000;

  // Address map constants (mirror axi4_xbar_pkg — CSR bank moved high so
  // fpga_mem can cover all of the CGRA's fetch/data addresses).
  localparam logic [AW-1:0] CSR_BASE     = 16'hFF00;
  localparam logic [AW-1:0] FPGAMEM_BASE = 16'h0000;

  // cgra_io_csr word offsets (byte-addressed, stride 2) relative to CSR_BASE
  localparam logic [AW-1:0] REG_CTRL     = CSR_BASE + 16'h0000;
  localparam logic [AW-1:0] REG_STARTPC  = CSR_BASE + 16'h0002;
  localparam logic [AW-1:0] REG_STATUS   = CSR_BASE + 16'h0004;
  localparam logic [AW-1:0] REG_CSRX0    = CSR_BASE + 16'h0010; // ...0x1E

  // CTRL bits
  localparam logic [15:0] CTRL_START       = 16'h0001;
  localparam logic [15:0] CTRL_CGRA_RESET  = 16'h0002;
  localparam logic [15:0] CTRL_BSLOAD_EN   = 16'h0004;

  // Default test vector
  localparam string DEFAULT_TEST_VECTOR     = "full_mul_array_test_vector";
  localparam string DEFAULT_TEST_VECTOR_DIR = "tb/test_vectors";

  // --------------------------------------------------------------------------
  // Clocks / reset
  // --------------------------------------------------------------------------
  bit   clk_i;
  logic rst_i = 1'b1;
  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

  int unsigned cyc_count;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cyc_count <= 0;
    end else begin
      cyc_count <= cyc_count + 1;
      if (cyc_count >= TIMEOUT_CYC) begin
        $display("[TB] TIMEOUT at %0d cycles", cyc_count);
        if (dice_core_tb_check_done() != 0) begin
          $display("[TB] (timeout) PASS-at-timeout: DPI write diff clean");
        end
        $fatal(1, "timeout");
      end
    end
  end

  // --------------------------------------------------------------------------
  // FPGA AXI master pins (TB drives these — chip sees them as slave)
  // --------------------------------------------------------------------------
  logic [AW-1:0]      fpga_aw_addr  = '0;
  logic [2:0]         fpga_aw_prot  = '0;
  logic               fpga_aw_valid = 1'b0;
  logic               fpga_aw_ready;

  logic [DW-1:0]      fpga_w_data   = '0;
  logic [DW/8-1:0]    fpga_w_strb   = '0;
  logic               fpga_w_valid  = 1'b0;
  logic               fpga_w_ready;

  logic [1:0]         fpga_b_resp;
  logic               fpga_b_valid;
  logic               fpga_b_ready  = 1'b1;

  logic [AW-1:0]      fpga_ar_addr  = '0;
  logic [2:0]         fpga_ar_prot  = '0;
  logic               fpga_ar_valid = 1'b0;
  logic               fpga_ar_ready;

  logic [DW-1:0]      fpga_r_data;
  logic [1:0]         fpga_r_resp;
  logic               fpga_r_valid;
  logic               fpga_r_ready  = 1'b1;

  // --------------------------------------------------------------------------
  // bsg_link reset / control
  // --------------------------------------------------------------------------
  logic dut_upstream_io_link_reset   = 1'b1;
  logic dut_async_token_reset        = 1'b0;
  logic dut_downstream_io_link_reset = 1'b1;

  logic ep_upstream_io_link_reset    = 1'b1;
  logic ep_async_token_reset         = 1'b0;
  logic ep_downstream_io_link_reset  = 1'b1;

  // --------------------------------------------------------------------------
  // DDR pins — DUT ↔ FPGA endpoint
  // --------------------------------------------------------------------------
  logic        dut_up_clk_r;
  logic [CW-1:0] dut_up_data_r;
  logic        dut_up_valid_r;
  logic        dut_dn_token_r;

  logic        ep_up_clk_r;
  logic [CW-1:0] ep_up_data_r;
  logic        ep_up_valid_r;
  logic        ep_dn_token_r;

  // --------------------------------------------------------------------------
  // DUT: mini_dice
  // --------------------------------------------------------------------------
  logic cgra_prog_dout, cgra_prog_we;
  logic csr_cgra_reset_w, csr_bsload_en_w;

  mini_dice_top #(
    .ADDR_WIDTH          (AW),
    .DATA_WIDTH          (DW),
    .FLIT_WIDTH          (FW),
    .CHANNEL_WIDTH       (CW),
    .BYPASS_TWOFER_FIFO  (1),
    .BYPASS_GEARBOX      (1)
  ) u_dut (
    .clk_i               (clk_i),
    .rst_i               (rst_i),

    // bsg_link upstream (DUT → FPGA endpoint)
    .io_master_clk_i            (clk_i),
    .upstream_io_link_reset_i   (dut_upstream_io_link_reset),
    .async_token_reset_i        (dut_async_token_reset),
    .token_clk_i                (ep_dn_token_r),
    .upstream_io_clk_r_o        (dut_up_clk_r),
    .upstream_io_data_r_o       (dut_up_data_r),
    .upstream_io_valid_r_o      (dut_up_valid_r),

    // bsg_link downstream (FPGA endpoint → DUT)
    .downstream_io_link_reset_i (dut_downstream_io_link_reset),
    .downstream_io_clk_i        (ep_up_clk_r),
    .downstream_io_data_i       (ep_up_data_r),
    .downstream_io_valid_i      (ep_up_valid_r),
    .downstream_core_token_r_o  (dut_dn_token_r),

    .cgra_prog_dout_o   (cgra_prog_dout),
    .cgra_prog_we_o     (cgra_prog_we),
    .csr_cgra_reset_o   (csr_cgra_reset_w),
    .csr_bsload_en_o    (csr_bsload_en_w)
  );

  // --------------------------------------------------------------------------
  // FPGA endpoint: second top_level_io, back-to-back with DUT on DDR pins
  // --------------------------------------------------------------------------
  logic        ep_tx_awvalid = 1'b0;
  logic        ep_tx_awready;
  logic [AW-1:0] ep_tx_awaddr = '0;
  logic [7:0]  ep_tx_awlen   = '0;
  logic [2:0]  ep_tx_awsize  = 3'b010;
  logic [1:0]  ep_tx_awburst = BURST_INCR;

  logic        ep_tx_wvalid  = 1'b0;
  logic        ep_tx_wready;
  logic [DW-1:0] ep_tx_wdata = '0;
  logic        ep_tx_wlast   = 1'b1;

  logic        ep_tx_arvalid = 1'b0;
  logic        ep_tx_arready;
  logic [AW-1:0] ep_tx_araddr = '0;
  logic [7:0]  ep_tx_arlen   = '0;
  logic [2:0]  ep_tx_arsize  = 3'b010;
  logic [1:0]  ep_tx_arburst = BURST_INCR;

  logic        ep_tx_rvalid  = 1'b0;
  logic [DW-1:0] ep_tx_rdata = '0;
  logic        ep_tx_rlast   = 1'b0;
  logic [1:0]  ep_tx_rresp   = '0;
  logic        ep_tx_rready;

  logic        ep_tx_bvalid  = 1'b0;
  logic [1:0]  ep_tx_bresp   = '0;
  logic        ep_tx_bready;

  logic        ep_rx_awvalid;
  logic [AW-1:0] ep_rx_awaddr;
  logic [7:0]  ep_rx_awlen;
  logic        ep_rx_wvalid;
  logic [DW-1:0] ep_rx_wdata;
  logic        ep_rx_wlast;
  logic        ep_rx_arvalid;
  logic [AW-1:0] ep_rx_araddr;
  logic [7:0]  ep_rx_arlen;
  logic        ep_rx_rvalid;
  logic        ep_rx_rready = 1'b0;
  logic [DW-1:0] ep_rx_rdata;
  logic [1:0]  ep_rx_rresp;
  logic        ep_rx_rlast;
  logic        ep_rx_bvalid;
  logic        ep_rx_bready = 1'b0;
  logic [1:0]  ep_rx_bresp;

  top_level_io #(
    .flit_width_p         (FW),
    .addr_width_p         (AW),
    .channel_width_p      (CW),
    .num_channels_p       (1),
    .bypass_gearbox_p     (1),
    .bypass_twofer_fifo_p (1),
    .rx_link_fifo_els_p   (64),
    .rx_aw_desc_fifo_els_p(2),
    .rx_ar_desc_fifo_els_p(2),
    .rx_w_len_fifo_els_p  (4),
    .rx_w_data_fifo_els_p (8),
    .rx_r_len_fifo_els_p  (4),
    .rx_r_data_fifo_els_p (64),
    .rx_b_resp_fifo_els_p (4),
    .tx_link_fifo_els_p   (64),
    .tx_aw_desc_fifo_els_p(2),
    .tx_ar_desc_fifo_els_p(2),
    .tx_w_len_fifo_els_p  (4),
    .tx_w_data_fifo_els_p (8),
    .tx_r_len_fifo_els_p  (4),
    .tx_r_data_fifo_els_p (64),
    .tx_b_resp_fifo_els_p (4),
    .tx_pkt_order_fifo_els_p(8)
  ) u_fpga_ep (
    .core_clk_i                 (clk_i),
    .reset_i                    (rst_i),

    // bsg_link upstream (FPGA ep → DUT downstream)
    .io_master_clk_i            (clk_i),
    .upstream_io_link_reset_i   (ep_upstream_io_link_reset),
    .async_token_reset_i        (ep_async_token_reset),
    .token_clk_i                (dut_dn_token_r),
    .upstream_io_clk_r_o        (ep_up_clk_r),
    .upstream_io_data_r_o       (ep_up_data_r),
    .upstream_io_valid_r_o      (ep_up_valid_r),

    // bsg_link downstream (DUT upstream → FPGA ep)
    .downstream_io_link_reset_i (ep_downstream_io_link_reset),
    .downstream_io_clk_i        (dut_up_clk_r),
    .downstream_io_data_i       (dut_up_data_r),
    .downstream_io_valid_i      (dut_up_valid_r),
    .downstream_core_token_r_o  (ep_dn_token_r),

    // TX: host requests plus R/B memory responses back to chip
    .tx_awvalid_i (ep_tx_awvalid), .tx_awready_o (ep_tx_awready),
    .tx_awaddr_i  (ep_tx_awaddr),  .tx_awlen_i   (ep_tx_awlen),
    .tx_awsize_i  (ep_tx_awsize),  .tx_awburst_i (ep_tx_awburst),
    .tx_wvalid_i  (ep_tx_wvalid),  .tx_wready_o  (ep_tx_wready),
    .tx_wdata_i   (ep_tx_wdata),   .tx_wlast_i   (ep_tx_wlast),
    .tx_arvalid_i (ep_tx_arvalid), .tx_arready_o (ep_tx_arready),
    .tx_araddr_i  (ep_tx_araddr),  .tx_arlen_i   (ep_tx_arlen),
    .tx_arsize_i  (ep_tx_arsize),  .tx_arburst_i (ep_tx_arburst),
    .tx_rvalid_i  (ep_tx_rvalid), .tx_rready_o (ep_tx_rready),
    .tx_rdata_i   (ep_tx_rdata), .tx_rresp_i (ep_tx_rresp), .tx_rlast_i (ep_tx_rlast),
    .tx_bvalid_i  (ep_tx_bvalid), .tx_bready_o (ep_tx_bready), .tx_bresp_i (ep_tx_bresp),

    // RX: AW/W/AR decoded from chip flits
    .rx_awvalid_o (ep_rx_awvalid), .rx_awready_i (1'b1), .rx_awaddr_o (ep_rx_awaddr),
    .rx_awlen_o   (ep_rx_awlen), .rx_awsize_o (), .rx_awburst_o (),
    .rx_wvalid_o  (ep_rx_wvalid), .rx_wready_i (1'b1), .rx_wdata_o (ep_rx_wdata),
    .rx_wlast_o   (ep_rx_wlast),
    .rx_arvalid_o (ep_rx_arvalid), .rx_arready_i (1'b1), .rx_araddr_o (ep_rx_araddr),
    .rx_arlen_o   (ep_rx_arlen), .rx_arsize_o (), .rx_arburst_o (),
    .rx_rvalid_o  (ep_rx_rvalid), .rx_rready_i (ep_rx_rready),
    .rx_rdata_o   (ep_rx_rdata),  .rx_rresp_o  (ep_rx_rresp), .rx_rlast_o (ep_rx_rlast),
    .rx_bvalid_o  (ep_rx_bvalid), .rx_bready_i (ep_rx_bready), .rx_bresp_o (ep_rx_bresp)
  );

  // --------------------------------------------------------------------------
  // FPGA memory model — burst-aware, classifies each AR by (address, length)
  // and serves it from the appropriate DPI port.  Writes are forwarded to
  // dice_core_tb_record_axi_write.
  //
  //   Classifier:
  //     addr >= 0x1000                                → meta read     (mfetch)
  //     arlen >  8  AND addr < 0x1000                 → bitstream read (bsfetch)
  //     else                                          → data read     (dfetch)
  //
  //   Metadata and bitstream fetches use true 32-bit beats. dmem reads still
  //   return a 16-bit payload in the low half of the 32-bit beat.
  // --------------------------------------------------------------------------
  localparam int MetaBeatBytes = DW / 8; // 4

  typedef enum logic [0:0] { RD_IDLE, RD_ACTIVE } rd_state_e;
  rd_state_e      rd_state_q;
  logic [AW-1:0]  rd_base_addr_q;
  logic [7:0]     rd_arlen_q;
  logic [7:0]     rd_beat_idx_q;
  logic [1:0]     rd_kind_q;   // 0=data, 1=meta, 2=bitstream

  function automatic int unsigned fetch_beat(
      input logic [1:0] kind,
      input logic [AW-1:0] base,
      input int unsigned beat_idx
  );
    int unsigned byte_addr;
    byte_addr = int'(base) + beat_idx * MetaBeatBytes;
    case (kind)
      2'd1:    return dice_core_tb_meta_read32(byte_addr);
      2'd2:    return dice_core_tb_bitstream_read32(byte_addr);
      default: return dice_core_tb_axi_read16(byte_addr);
    endcase
  endfunction

  // Single-outstanding AW/W pairing (dfetch writes are single-beat)
  logic          ep_aw_pending;
  logic [AW-1:0] ep_aw_addr_lat;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rd_state_q     <= RD_IDLE;
      rd_base_addr_q <= '0;
      rd_arlen_q     <= '0;
      rd_beat_idx_q  <= '0;
      rd_kind_q      <= '0;
      ep_tx_rvalid   <= 1'b0;
      ep_tx_rlast    <= 1'b0;
      ep_tx_rdata    <= '0;
      ep_tx_rresp    <= '0;
      ep_tx_bvalid   <= 1'b0;
      ep_aw_pending  <= 1'b0;
      ep_aw_addr_lat <= '0;
    end else begin
      // Read FSM
      unique case (rd_state_q)
        RD_IDLE: begin
          if (ep_rx_arvalid) begin
            logic [1:0] kind;
            if (ep_rx_araddr >= 16'h1000)       kind = 2'd1; // meta
            else if (ep_rx_arlen > 8'd8)        kind = 2'd2; // bitstream
            else                                 kind = 2'd0; // data
            rd_base_addr_q <= ep_rx_araddr;
            rd_arlen_q     <= ep_rx_arlen;
            rd_beat_idx_q  <= '0;
            rd_kind_q      <= kind;
            ep_tx_rdata    <= DW'(fetch_beat(kind, ep_rx_araddr, 0));
            ep_tx_rlast    <= (ep_rx_arlen == 8'd0);
            ep_tx_rresp    <= 2'b00;
            ep_tx_rvalid   <= 1'b1;
            rd_state_q     <= RD_ACTIVE;
          end
        end
        RD_ACTIVE: begin
          if (ep_tx_rvalid && ep_tx_rready) begin
            if (ep_tx_rlast) begin
              ep_tx_rvalid <= 1'b0;
              ep_tx_rlast  <= 1'b0;
              rd_state_q   <= RD_IDLE;
            end else begin
              automatic int unsigned next_idx = int'(rd_beat_idx_q) + 1;
              rd_beat_idx_q <= rd_beat_idx_q + 8'd1;
              ep_tx_rdata   <= DW'(fetch_beat(rd_kind_q, rd_base_addr_q, next_idx));
              ep_tx_rlast   <= (rd_beat_idx_q + 8'd1 == rd_arlen_q);
            end
          end
        end
      endcase

      // Write path — single-beat pairing, record to DPI
      if (ep_tx_bvalid && ep_tx_bready) ep_tx_bvalid <= 1'b0;

      if (ep_rx_awvalid && !ep_aw_pending) begin
        ep_aw_addr_lat <= ep_rx_awaddr;
        ep_aw_pending  <= 1'b1;
      end

      if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid) begin
        dice_core_tb_record_axi_write(
          int'(ep_aw_addr_lat),
          int'(ep_rx_wdata[15:0]),
          int'(32'h3)
        );
        ep_aw_pending  <= 1'b0;
        ep_tx_bresp    <= 2'b00;
        ep_tx_bvalid   <= 1'b1;
      end
    end
  end

  // Debug: log link-level activity at the FPGA endpoint so we can see what
  // the CGRA is actually issuing through bsg_link.
  always_ff @(posedge clk_i) if (!rst_i) begin
    if (ep_rx_arvalid && rd_state_q == RD_IDLE)
      $display("[EP] t=%0t AR addr=0x%04x len=%0d kind=%0d",
               $time, ep_rx_araddr, ep_rx_arlen,
               (ep_rx_araddr >= 16'h1000) ? 2'd1 :
               (ep_rx_arlen > 8'd8) ? 2'd2 : 2'd0);
    if (ep_rx_awvalid && !ep_aw_pending)
      $display("[EP] t=%0t AW addr=0x%04x len=%0d", $time, ep_rx_awaddr, ep_rx_awlen);
    if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid)
      $display("[EP] t=%0t W  addr=0x%04x data=0x%04x",
               $time, ep_aw_addr_lat, ep_rx_wdata[15:0]);
  end

  // Debug: log activity at several points along the fetch path.  Hierarchical
  // probes into the DUT so we can tell where fetches are stalling.
  always_ff @(posedge clk_i) if (!rst_i) begin
    if (u_dut.mfetch_req.ar_valid && u_dut.mfetch_resp.ar_ready)
      $display("[HIER][DC] t=%0t mfetch AR addr=0x%04x len=%0d",
               $time, u_dut.mfetch_req.ar.addr, u_dut.mfetch_req.ar.len);
    if (u_dut.bsfetch_req.ar_valid && u_dut.bsfetch_resp.ar_ready)
      $display("[HIER][DC] t=%0t bsfetch AR addr=0x%04x len=%0d",
               $time, u_dut.bsfetch_req.ar.addr, u_dut.bsfetch_req.ar.len);
    if (u_dut.dfetch_arvalid && u_dut.dfetch_arready)
      $display("[HIER][DC] t=%0t dfetch AR addr=0x%04x",
               $time, u_dut.dfetch_araddr);
    if (u_dut.dfetch_awvalid && u_dut.dfetch_awready)
      $display("[HIER][DC] t=%0t dfetch AW addr=0x%04x",
               $time, u_dut.dfetch_awaddr);
    if (u_dut.u_io_top.xbar_mem_req.ar_valid && u_dut.u_io_top.xbar_mem_resp.ar_ready)
      $display("[HIER][XB] t=%0t xbar_mem AR addr=0x%04x len=%0d",
               $time, u_dut.u_io_top.xbar_mem_req.ar.addr,
               u_dut.u_io_top.xbar_mem_req.ar.len);
    if (u_dut.u_io_top.xbar_mem_req.aw_valid && u_dut.u_io_top.xbar_mem_resp.aw_ready)
      $display("[HIER][XB] t=%0t xbar_mem AW addr=0x%04x",
               $time, u_dut.u_io_top.xbar_mem_req.aw.addr);
    if (u_dut.u_io_top.xbar_mem_req.ar_valid && !u_dut.u_io_top.xbar_mem_resp.ar_ready)
      ; // stall visible via waveforms — too verbose to log every cycle
  end

  // Dump CSR values at the DUT's cgra_io_csr outputs once the start pulse
  // has fired, so we can see whether the RX programming actually landed.
  int csr_dump_once;
  always_ff @(posedge clk_i) if (!rst_i) begin
    if (u_dut.u_csr.start_o && csr_dump_once == 0) begin
      csr_dump_once <= 1;
      $display("[CSR-POST-START] csr_out={%04x %04x %04x %04x %04x %04x %04x %04x} start_pc=%04x",
               u_dut.u_csr.csrX0_o, u_dut.u_csr.csrX1_o,
               u_dut.u_csr.csrX2_o, u_dut.u_csr.csrX3_o,
               u_dut.u_csr.csrX4_o, u_dut.u_csr.csrX5_o,
               u_dut.u_csr.csrX6_o, u_dut.u_csr.csrX7_o,
               u_dut.u_csr.start_pc_o);
      $display("[CSR-POST-START] dc_in ={%04x %04x %04x %04x %04x %04x %04x %04x}",
               u_dut.u_dice_core.csrX0_i, u_dut.u_dice_core.csrX1_i,
               u_dut.u_dice_core.csrX2_i, u_dut.u_dice_core.csrX3_i,
               u_dut.u_dice_core.csrX4_i, u_dut.u_dice_core.csrX5_i,
               u_dut.u_dice_core.csrX6_i, u_dut.u_dice_core.csrX7_i);
    end
  end

  // Periodic heartbeat to expose stall state at both ends.
  int hb_count;
  always_ff @(posedge clk_i) if (!rst_i) begin
    hb_count <= hb_count + 1;
    if ((hb_count % 2000) == 0) begin
      $display("[HB] t=%0t beat=%0d  ep_tx_rv=%b rrdy=%b | chip.rx_rv=%b rrdy=%b | xbar.r_v=%b r_rdy=%b | mf.r_v=%b r_rdy=%b",
               $time, rd_beat_idx_q,
               ep_tx_rvalid, ep_tx_rready,
               u_dut.u_io_top.rx_rvalid, u_dut.u_io_top.xbar_mem_req.r_ready,
               u_dut.u_io_top.xbar_mem_resp.r_valid, u_dut.u_io_top.xbar_mem_req.r_ready,
               u_dut.mfetch_resp.r_valid, u_dut.mfetch_req.r_ready);
    end
  end

  // Log every R beat handshake on the EP→chip path.
  int ep_r_beats;
  always_ff @(posedge clk_i) if (!rst_i) begin
    if (ep_tx_rvalid && ep_tx_rready) begin
      ep_r_beats <= ep_r_beats + 1;
      $display("[EP->chip] t=%0t R beat#%0d data=0x%08x last=%b",
               $time, ep_r_beats, ep_tx_rdata, ep_tx_rlast);
    end
    if (u_dut.mfetch_resp.r_valid && u_dut.mfetch_req.r_ready)
      $display("[chip][DC] t=%0t mfetch R beat data=0x%08x last=%b",
               $time, u_dut.mfetch_resp.r.data, u_dut.mfetch_resp.r.last);
  end

  // --------------------------------------------------------------------------
  // Simple AXI-Lite-style master tasks through the FPGA endpoint link TX.
  // The transport does not carry WSTRB, so writes are full-strobe on chip.
  // --------------------------------------------------------------------------
  task automatic axi_write(input logic [AW-1:0] addr,
                           input logic [DW-1:0] data,
                           input logic [DW/8-1:0] strb = 4'hF);
    bit aw_done;
    bit w_done;
    begin
      void'(strb);

      @(posedge clk_i); #1;
      ep_tx_awaddr  = addr;
      ep_tx_awlen   = '0;
      ep_tx_awsize  = 3'b010;
      ep_tx_awburst = BURST_INCR;
      ep_tx_awvalid = 1'b1;

      ep_tx_wdata   = data;
      ep_tx_wlast   = 1'b1;
      ep_tx_wvalid  = 1'b1;

      aw_done = 1'b0;
      w_done  = 1'b0;
      do begin
        @(posedge clk_i); #1;
        if (!aw_done && ep_tx_awready) begin
          ep_tx_awvalid = 1'b0;
          aw_done = 1'b1;
        end
        if (!w_done && ep_tx_wready) begin
          ep_tx_wvalid = 1'b0;
          w_done = 1'b1;
        end
      end while (!(aw_done && w_done));

      // Wait for B response decoded from the DUT's link TX.
      ep_rx_bready = 1'b1;
      do @(posedge clk_i); while (!ep_rx_bvalid);
      @(posedge clk_i); #1;
      ep_rx_bready = 1'b0;
    end
  endtask

  task automatic csr_write(input logic [AW-1:0] reg_offset,
                           input logic [15:0]   data16);
    // cgra_io_csr uses 16-bit registers; place the 16-bit datum in the low
    // half of the 32-bit AXI word and assert the low strobes.
    axi_write(reg_offset, DW'(data16), 4'b0011);
  endtask

  task automatic bsg_link_bringup();
    begin
      rst_i                        = 1'b1;
      dut_upstream_io_link_reset   = 1'b1;
      dut_downstream_io_link_reset = 1'b1;
      ep_upstream_io_link_reset    = 1'b1;
      ep_downstream_io_link_reset  = 1'b1;
      dut_async_token_reset        = 1'b0;
      ep_async_token_reset         = 1'b0;
      repeat (4) @(posedge clk_i);

      @(posedge clk_i); #1;
      dut_async_token_reset = 1'b1;
      ep_async_token_reset  = 1'b1;
      @(posedge clk_i); #1;
      dut_async_token_reset = 1'b0;
      ep_async_token_reset  = 1'b0;

      repeat (8) @(posedge clk_i);

      @(posedge clk_i); #1;
      dut_upstream_io_link_reset = 1'b0;
      ep_upstream_io_link_reset  = 1'b0;
      repeat (8) @(posedge clk_i);

      @(posedge clk_i); #1;
      dut_downstream_io_link_reset = 1'b0;
      ep_downstream_io_link_reset  = 1'b0;
      repeat (4) @(posedge clk_i);

      rst_i = 1'b0;
      repeat (4) @(posedge clk_i);
    end
  endtask

  // --------------------------------------------------------------------------
  // Collateral + path resolution
  // --------------------------------------------------------------------------
  string test_vector_name;
  string test_vector_dir;
  string test_vector_stem;
  string cta_desc_mem_file;
  string meta_mem_file;
  string bitstream_mem_file;
  string runtime_json_file;

  function automatic bit has_path_component(input string path);
    if (path.len() == 0) return 1'b0;
    if (path.getc(0) == "/") return 1'b1;
    for (int i = 0; i < path.len(); i++) if (path.getc(i) == "/") return 1'b1;
    return 1'b0;
  endfunction

  task automatic init_paths();
    begin
      if (!$value$plusargs("TEST_VECTOR=%s", test_vector_name))
        test_vector_name = DEFAULT_TEST_VECTOR;
      if (has_path_component(test_vector_name)) begin
        test_vector_stem = test_vector_name;
      end else begin
        if (!$value$plusargs("TEST_VECTOR_DIR=%s", test_vector_dir))
          test_vector_dir = DEFAULT_TEST_VECTOR_DIR;
        test_vector_stem = {test_vector_dir, "/", test_vector_name};
      end
      cta_desc_mem_file  = {test_vector_stem, "_cta_desc.mem"};
      meta_mem_file      = {test_vector_stem, "_meta.mem"};
      bitstream_mem_file = {test_vector_stem, "_bitstream.mem"};
      runtime_json_file  = {test_vector_stem, "_runtime.json"};
    end
  endtask

  logic [15:0] csr_values [0:7];
  logic [15:0] start_pc_val;

  task automatic load_collateral();
    begin
      dice_core_tb_init(cta_desc_mem_file, meta_mem_file, bitstream_mem_file, runtime_json_file);
      if (dice_core_tb_has_init_error())
        $fatal(1, "[TB] DPI init failed: %s", dice_core_tb_get_init_error());

      for (int i = 0; i < 8; i++)
        csr_values[i] = 16'(dice_core_tb_get_csr(i));

      // csrX0 convention in the existing dice_core vectors carries the bitstream
      // base address.  Use it as the reads-classifier boundary.  Meta lives at
      // a lower address (start_pc range); bitstream at csrX0+.
      // Conventional kernel_simple vectors use start_pc = 0x1000.
      start_pc_val = 16'h1000;
      void'($value$plusargs("START_PC=%h", start_pc_val));

      $display("[TB] Test vector stem      : %s", test_vector_stem);
      $display("[TB] csrX0..7              : %04x %04x %04x %04x %04x %04x %04x %04x",
               csr_values[0], csr_values[1], csr_values[2], csr_values[3],
               csr_values[4], csr_values[5], csr_values[6], csr_values[7]);
      $display("[TB] start_pc              : 0x%04x", start_pc_val);
    end
  endtask

  // --------------------------------------------------------------------------
  // Program CSRs + launch
  // --------------------------------------------------------------------------
  task automatic program_csrs_and_launch();
    begin
      $display("[TB] Programming csrX0..7 via bsg_link host path");
      for (int i = 0; i < 8; i++) begin
        csr_write(REG_CSRX0 + AW'(i * 2), csr_values[i]);
      end

      $display("[TB] Setting start_pc = 0x%04x", start_pc_val);
      csr_write(REG_STARTPC, start_pc_val);

      $display("[TB] Pulsing CTRL.start");
      csr_write(REG_CTRL, CTRL_START);
    end
  endtask

  // --------------------------------------------------------------------------
  // Completion wait
  //   We wait on STATUS.complete (bit 0).  If the RTL hasn't routed hw_complete
  //   yet, fall back to a bounded settle window + DPI write count check.
  // --------------------------------------------------------------------------
  task automatic wait_for_complete();
    int unsigned settle_cycles;
    settle_cycles = 500000;
    void'($value$plusargs("SETTLE=%d", settle_cycles));

    $display("[TB] Running for up to %0d cycles, then checking DPI", settle_cycles);
    repeat (settle_cycles) @(posedge clk_i);
  endtask

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------
  initial begin
    int unsigned ok;

    $fsdbDumpfile("tb_mini_dice.fsdb");
    $fsdbDumpvars(0, tb_mini_dice, "+struct", "+mda");

    init_paths();
    bsg_link_bringup();
    load_collateral();

    // Optional: release cgra_reset / enable bsload before launch if used
    // csr_write(REG_CTRL, CTRL_BSLOAD_EN);

    program_csrs_and_launch();
    wait_for_complete();

    ok = dice_core_tb_check_done();
    if (ok != 0) begin
      $display("[TB] PASS: mini_dice top-level DPI checks clean");
      $finish;
    end
    $display("[TB] FAIL: DPI reported AXI write mismatch (see diff above)");
    $fatal(1, "FAIL");
  end

endmodule
