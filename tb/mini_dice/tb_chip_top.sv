// =============================================================================
// tb_chip_top.sv
//
// Chip-level testbench for chip_top — drives all signals through PAD pins
// via the TSMC pad ring.  Functionally identical to tb_mini_dice but uses
// chip_top as the DUT so the full pad connectivity is exercised.
//
// Flow:
//   1. Bring up reset + bsg_link by driving PAD input pins.
//   2. DPI loads test-vector collateral.
//   3. FPGA endpoint programs CSRs through bsg_link → dice_core launches.
//   4. dice_core mfetch/bsfetch/dfetch traverse crossbar + bsg_link DDR.
//   5. DPI verifier reports PASS/FAIL.
// =============================================================================

`timescale 1ns / 1ps

import "DPI-C" context function void dice_core_tb_init(
  input string cta_desc_mem_file,
  input string meta_mem_file,
  input string bitstream_mem_file,
  input string runtime_json_file
);
import "DPI-C" context function int unsigned dice_core_tb_has_init_error();
import "DPI-C" context function string dice_core_tb_get_init_error();
import "DPI-C" context function int unsigned dice_core_tb_get_cta_desc_word(
  input int unsigned word_idx
);
import "DPI-C" context function int unsigned dice_core_tb_get_csr(input int unsigned csr_idx);
import "DPI-C" context function int unsigned dice_core_tb_meta_read16(input int unsigned byte_addr);
import "DPI-C" context function int unsigned dice_core_tb_meta_read32(input int unsigned byte_addr);
import "DPI-C" context function int unsigned dice_core_tb_bitstream_read16(
  input int unsigned byte_addr
);
import "DPI-C" context function int unsigned dice_core_tb_bitstream_read32(
  input int unsigned byte_addr
);
import "DPI-C" context function int unsigned dice_core_tb_axi_read16(input int unsigned addr);
import "DPI-C" context function void dice_core_tb_record_axi_write(
  input int unsigned addr,
  input int unsigned data,
  input int unsigned strb
);
import "DPI-C" context function int unsigned dice_core_tb_check_done();

`include "dice_define.vh"

module tb_chip_top;
  import dice_pkg::*;
  import DE_pkg::*;

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam int AW = 16;
  localparam int DW = 32;
  localparam int FW = 32;
  localparam int CW = 16;
  localparam int CLK_HALF_NS = 10;  // 100 MHz
  localparam int TIMEOUT_CYC = 70000;
  localparam int CTA_DESC_BITS = $bits(dice_cta_desc_t);
  localparam int CTA_DESC_WORDS = (CTA_DESC_BITS + 31) / 32;
  localparam logic [1:0] BURST_INCR = 2'b01;

  localparam logic [AW-1:0] CSR_BASE = 16'hFF00;
  localparam logic [AW-1:0] REG_CTRL = CSR_BASE + 16'h0000;
  localparam logic [AW-1:0] REG_STARTPC = CSR_BASE + 16'h0002;
  localparam logic [AW-1:0] REG_STATUS = CSR_BASE + 16'h0004;
  localparam logic [AW-1:0] REG_THREAD_COUNT = CSR_BASE + 16'h000c;
  localparam logic [AW-1:0] REG_CSRX0 = CSR_BASE + 16'h0010;

  localparam logic [15:0] CTRL_START = 16'h0001;
  localparam logic [15:0] CTRL_CGRA_RESET = 16'h0002;
  localparam logic [15:0] CTRL_BSLOAD_EN = 16'h0004;

  localparam string DEFAULT_TEST_VECTOR = "simple_branching_test_vector";
  localparam string DEFAULT_TEST_VECTOR_DIR = "tb/test_vectors";

  // --------------------------------------------------------------------------
  // Clock / reset drivers (TB-side logic, mapped to PAD below)
  // --------------------------------------------------------------------------
  bit   clk_i;
  logic rst_i = 1'b1;  // FPGA endpoint/core reset
  logic hard_reset = 1'b1;  // chip hard reset on PAD[45]
  logic ep_upstream_io_link_reset = 1'b1;
  logic ep_async_token_reset = 1'b0;
  logic ep_downstream_io_link_reset = 1'b1;

  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

  // --------------------------------------------------------------------------
  // PAD bus — chip_top inout
  // --------------------------------------------------------------------------
  wire  [  47:0] PAD;
  logic [  47:0] pad_drv;

  // EP upstream outputs -> chip downstream inputs.
  wire           ep_up_clk_r;
  wire           ep_up_valid_r;
  wire  [CW-1:0] ep_up_data_r;
  wire           ep_dn_token_r;

  function automatic logic kz(input logic v);
    kz = v;
  endfunction

  assign PAD = pad_drv;

  always_comb begin
    pad_drv = 'z;

    // zeroscatter-compatible chip_top pad map.
    pad_drv[44] = kz(clk_i);  // core_clk
    pad_drv[45] = kz(hard_reset);

    // EP upstream outputs -> chip downstream inputs.
    pad_drv[8] = kz(ep_up_clk_r);
    pad_drv[9] = kz(ep_up_valid_r);
    for (int i = 0; i < CW; i++) begin
      pad_drv[dn_data_pad(i)] = kz(ep_up_data_r[i]);
    end

    // Chip TX-side credit return into EP upstream.
    pad_drv[12] = kz(ep_dn_token_r);
  end

  function automatic int dn_data_pad(input int bit_idx);
    case (bit_idx)
      0: dn_data_pad = 0;
      1: dn_data_pad = 1;
      2: dn_data_pad = 2;
      3: dn_data_pad = 3;
      4: dn_data_pad = 4;
      5: dn_data_pad = 5;
      6: dn_data_pad = 6;
      7: dn_data_pad = 7;
      8: dn_data_pad = 37;
      9: dn_data_pad = 36;
      10: dn_data_pad = 39;
      11: dn_data_pad = 38;
      12: dn_data_pad = 41;
      13: dn_data_pad = 40;
      14: dn_data_pad = 43;
      15: dn_data_pad = 42;
      default: dn_data_pad = 0;
    endcase
  endfunction

  function automatic int up_data_pad(input int bit_idx);
    case (bit_idx)
      0: up_data_pad = 22;
      1: up_data_pad = 23;
      2: up_data_pad = 20;
      3: up_data_pad = 21;
      4: up_data_pad = 18;
      5: up_data_pad = 19;
      6: up_data_pad = 16;
      7: up_data_pad = 17;
      8: up_data_pad = 28;
      9: up_data_pad = 29;
      10: up_data_pad = 30;
      11: up_data_pad = 31;
      12: up_data_pad = 32;
      13: up_data_pad = 33;
      14: up_data_pad = 34;
      15: up_data_pad = 35;
      default: up_data_pad = 28;
    endcase
  endfunction

  // Chip upstream outputs -> EP downstream inputs.
  wire          dut_up_clk_r = PAD[15];
  wire          dut_up_valid_r = PAD[14];
  wire [CW-1:0] dut_up_data_r;
  genvar gi;
  generate
    for (gi = 0; gi < CW; gi++) begin : gen_up_data
      assign dut_up_data_r[gi] = PAD[up_data_pad(gi)];
    end
  endgenerate
  wire dut_dn_token_r = PAD[10];

  // --------------------------------------------------------------------------
  // DUT: chip_top
  // --------------------------------------------------------------------------
  chip_top u_dut (
      .PAD   (PAD),
      .VDDPST(1'b1),
      .VSSPST(1'b0),
      .VDD   (1'b1),
      .VSS   (1'b0)
  );

  // --------------------------------------------------------------------------
  // FPGA endpoint: top_level_io packetizer + external bsg_link wrapper
  // back-to-back with DUT over DDR pads.
  // --------------------------------------------------------------------------
  logic          ep_tx_awvalid = 1'b0;
  logic          ep_tx_awready;
  logic [AW-1:0] ep_tx_awaddr = '0;
  logic [   7:0] ep_tx_awlen = '0;
  logic [   2:0] ep_tx_awsize = 3'b010;
  logic [   1:0] ep_tx_awburst = BURST_INCR;

  logic          ep_tx_wvalid = 1'b0;
  logic          ep_tx_wready;
  logic [DW-1:0] ep_tx_wdata = '0;
  logic          ep_tx_wlast = 1'b1;

  logic          ep_tx_arvalid = 1'b0;
  logic          ep_tx_arready;
  logic [AW-1:0] ep_tx_araddr = '0;
  logic [   7:0] ep_tx_arlen = '0;
  logic [   2:0] ep_tx_arsize = 3'b010;
  logic [   1:0] ep_tx_arburst = BURST_INCR;

  logic          ep_tx_rvalid = 1'b0;
  logic [DW-1:0] ep_tx_rdata = '0;
  logic          ep_tx_rlast = 1'b0;
  logic [   1:0] ep_tx_rresp = '0;
  logic          ep_tx_rready;

  logic          ep_tx_bvalid = 1'b0;
  logic [   1:0] ep_tx_bresp = '0;
  logic          ep_tx_bready;

  logic          ep_rx_awvalid;
  logic [AW-1:0] ep_rx_awaddr;
  logic [   7:0] ep_rx_awlen;
  logic          ep_rx_wvalid;
  logic [DW-1:0] ep_rx_wdata;
  logic          ep_rx_wlast;
  logic          ep_rx_arvalid;
  logic          ep_rx_arready;
  logic [AW-1:0] ep_rx_araddr;
  logic [   7:0] ep_rx_arlen;
  logic [  13:0] ep_rx_aruser;
  logic          ep_rx_aruser_is_meta;
  logic          ep_rx_rvalid;
  logic          ep_rx_rready = 1'b0;
  logic [DW-1:0] ep_rx_rdata;
  logic [   1:0] ep_rx_rresp;
  logic          ep_rx_rlast;
  logic          ep_rx_bvalid;
  logic          ep_rx_bready = 1'b0;
  logic [   1:0] ep_rx_bresp;

  logic [FW-1:0] ep_link_rx_data;
  logic          ep_link_rx_valid;
  logic          ep_link_rx_yumi;
  logic [FW-1:0] ep_link_tx_data;
  logic          ep_link_tx_valid;
  logic          ep_link_tx_ready;

  bsg_link_wrapper #(
      .FLIT_WIDTH   (FW),
      .CHANNEL_WIDTH(CW)
  ) u_fpga_link (
      .core_clk_i                (clk_i),
      .reset_i                   (rst_i),
      .io_master_clk_i           (clk_i),
      .upstream_io_link_reset_i  (ep_upstream_io_link_reset),
      .async_token_reset_i       (ep_async_token_reset),
      .token_clk_i               (dut_dn_token_r),
      .downstream_io_link_reset_i(ep_downstream_io_link_reset),
      .downstream_io_clk_i       (dut_up_clk_r),
      .downstream_io_data_i      (dut_up_data_r),
      .downstream_io_valid_i     (dut_up_valid_r),
      .upstream_io_clk_r_o       (ep_up_clk_r),
      .upstream_io_data_r_o      (ep_up_data_r),
      .upstream_io_valid_r_o     (ep_up_valid_r),
      .downstream_core_token_r_o (ep_dn_token_r),
      .rx_data_o                 (ep_link_rx_data),
      .rx_valid_o                (ep_link_rx_valid),
      .rx_yumi_i                 (ep_link_rx_yumi),
      .tx_data_i                 (ep_link_tx_data),
      .tx_valid_i                (ep_link_tx_valid),
      .tx_ready_o                (ep_link_tx_ready)
  );

  top_level_io #(
      .flit_width_p           (FW),
      .addr_width_p           (AW),
      .channel_width_p        (CW),
      .num_channels_p         (1),
      .bypass_gearbox_p       (1),
      .bypass_twofer_fifo_p   (1),
      .rx_link_fifo_els_p     (64),
      .rx_aw_desc_fifo_els_p  (2),
      .rx_ar_desc_fifo_els_p  (2),
      .rx_w_len_fifo_els_p    (4),
      .rx_w_data_fifo_els_p   (8),
      .rx_r_len_fifo_els_p    (4),
      .rx_r_data_fifo_els_p   (64),
      .tx_link_fifo_els_p     (64),
      .tx_aw_desc_fifo_els_p  (2),
      .tx_ar_desc_fifo_els_p  (2),
      .tx_w_len_fifo_els_p    (4),
      .tx_w_data_fifo_els_p   (8),
      .tx_r_len_fifo_els_p    (4),
      .tx_r_data_fifo_els_p   (64),
      .tx_pkt_order_fifo_els_p(8)
  ) u_fpga_ep (
      .core_clk_i(clk_i),
      .reset_i   (rst_i),

      .link_rx_data_i (ep_link_rx_data),
      .link_rx_valid_i(ep_link_rx_valid),
      .link_rx_yumi_o (ep_link_rx_yumi),
      .link_tx_data_o (ep_link_tx_data),
      .link_tx_valid_o(ep_link_tx_valid),
      .link_tx_ready_i(ep_link_tx_ready),

      .tx_awvalid_i(ep_tx_awvalid),
      .tx_awready_o(ep_tx_awready),
      .tx_awaddr_i (ep_tx_awaddr),
      .tx_awlen_i  (ep_tx_awlen),
      .tx_awsize_i (ep_tx_awsize),
      .tx_awburst_i(ep_tx_awburst),
      .tx_wvalid_i (ep_tx_wvalid),
      .tx_wready_o (ep_tx_wready),
      .tx_wdata_i  (ep_tx_wdata),
      .tx_wlast_i  (ep_tx_wlast),
      .tx_arvalid_i(ep_tx_arvalid),
      .tx_arready_o(ep_tx_arready),
      .tx_araddr_i (ep_tx_araddr),
      .tx_arlen_i  (ep_tx_arlen),
      .tx_arsize_i (ep_tx_arsize),
      .tx_arburst_i(ep_tx_arburst),
      .tx_aruser_i (14'b0),
      .tx_rvalid_i (ep_tx_rvalid),
      .tx_rready_o (ep_tx_rready),
      .tx_rdata_i  (ep_tx_rdata),
      .tx_rresp_i  (ep_tx_rresp),
      .tx_rlast_i  (ep_tx_rlast),
      .tx_bvalid_i (ep_tx_bvalid),
      .tx_bready_o (ep_tx_bready),
      .tx_bresp_i  (ep_tx_bresp),

      .rx_awvalid_o(ep_rx_awvalid),
      .rx_awready_i(1'b1),
      .rx_awaddr_o (ep_rx_awaddr),
      .rx_awlen_o  (ep_rx_awlen),
      .rx_awsize_o (),
      .rx_awburst_o(),
      .rx_wvalid_o (ep_rx_wvalid),
      .rx_wready_i (1'b1),
      .rx_wdata_o  (ep_rx_wdata),
      .rx_wlast_o  (ep_rx_wlast),
      .rx_arvalid_o(ep_rx_arvalid),
      .rx_arready_i(ep_rx_arready),
      .rx_araddr_o (ep_rx_araddr),
      .rx_arlen_o  (ep_rx_arlen),
      .rx_arsize_o (),
      .rx_arburst_o(),
      .rx_aruser_o (ep_rx_aruser),
      .rx_rvalid_o (ep_rx_rvalid),
      .rx_rready_i (ep_rx_rready),
      .rx_rdata_o  (ep_rx_rdata),
      .rx_rresp_o  (ep_rx_rresp),
      .rx_rlast_o  (ep_rx_rlast),
      .rx_bvalid_o (ep_rx_bvalid),
      .rx_bready_i (ep_rx_bready),
      .rx_bresp_o  (ep_rx_bresp)
  );

  assign ep_rx_aruser_is_meta = ep_rx_aruser[13];

  // --------------------------------------------------------------------------
  // FPGA memory model (identical to tb_mini_dice)
  // --------------------------------------------------------------------------
  localparam int MetaBeatBytes = DW / 8;

  typedef enum logic [0:0] {
    RD_IDLE,
    RD_ACTIVE
  } rd_state_e;
  rd_state_e               rd_state_q;
  logic           [AW-1:0] rd_base_addr_q;
  logic           [   7:0] rd_arlen_q;
  logic           [   7:0] rd_beat_idx_q;
  logic           [   1:0] rd_kind_q;
  logic                    rd_aruser_is_meta_q;
  logic           [  12:0] rd_aruser_q;
  logic           [  15:0] csr_values          [0:7];
  logic           [  15:0] start_pc_val;
  dice_cta_desc_t          launch_desc;

  function automatic int unsigned fetch_beat(input logic [1:0] kind, input logic [AW-1:0] base,
                                             input int unsigned beat_idx);
    int unsigned byte_addr;
    byte_addr = int'(base) + beat_idx * MetaBeatBytes;
    case (kind)
      2'd1:    return dice_core_tb_meta_read32(byte_addr);
      2'd2:    return dice_core_tb_bitstream_read32(byte_addr);
      default: return dice_core_tb_axi_read16(byte_addr);
    endcase
  endfunction

  function automatic logic [DW-1:0] pack_read_beat(
      input logic [1:0] kind, input logic [AW-1:0] base, input int unsigned beat_idx,
      input logic is_meta, input logic [12:0] meta);
    logic [DW-1:0] word;
    begin
      word = DW'(fetch_beat(kind, base, beat_idx));
      if (is_meta) word[28:16] = meta;
      return word;
    end
  endfunction

  logic          ep_aw_pending;
  logic [AW-1:0] ep_aw_addr_lat;

  assign ep_rx_arready = (rd_state_q == RD_IDLE);

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rd_state_q          <= RD_IDLE;
      rd_base_addr_q      <= '0;
      rd_arlen_q          <= '0;
      rd_beat_idx_q       <= '0;
      rd_kind_q           <= '0;
      rd_aruser_is_meta_q <= 1'b0;
      rd_aruser_q         <= '0;
      ep_tx_rvalid        <= 1'b0;
      ep_tx_rlast         <= 1'b0;
      ep_tx_rdata         <= '0;
      ep_tx_rresp         <= '0;
      ep_tx_bvalid        <= 1'b0;
      ep_aw_pending       <= 1'b0;
      ep_aw_addr_lat      <= '0;
    end else begin
      unique case (rd_state_q)
        RD_IDLE: begin
          if (ep_rx_arvalid && ep_rx_arready) begin
            logic [1:0] kind;
            if (ep_rx_araddr >= start_pc_val) kind = 2'd1;
            else if (ep_rx_arlen > 8'd8) kind = 2'd2;
            else kind = 2'd0;
            rd_base_addr_q <= ep_rx_araddr;
            rd_arlen_q <= ep_rx_arlen;
            rd_beat_idx_q <= '0;
            rd_kind_q <= kind;
            rd_aruser_is_meta_q <= ep_rx_aruser_is_meta;
            rd_aruser_q <= ep_rx_aruser[12:0];
            ep_tx_rdata <= pack_read_beat(
                kind, ep_rx_araddr, 0, ep_rx_aruser_is_meta, ep_rx_aruser[12:0]
            );
            ep_tx_rlast <= (ep_rx_arlen == 8'd0);
            ep_tx_rresp <= 2'b00;
            ep_tx_rvalid <= 1'b1;
            rd_state_q <= RD_ACTIVE;
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
              ep_tx_rdata <= pack_read_beat(
                  rd_kind_q, rd_base_addr_q, next_idx, rd_aruser_is_meta_q, rd_aruser_q
              );
              ep_tx_rlast <= (rd_beat_idx_q + 8'd1 == rd_arlen_q);
            end
          end
        end
      endcase

      if (ep_tx_bvalid && ep_tx_bready) ep_tx_bvalid <= 1'b0;
      if (ep_rx_awvalid && !ep_aw_pending) begin
        ep_aw_addr_lat <= ep_rx_awaddr;
        ep_aw_pending  <= 1'b1;
      end
      if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid) begin
        dice_core_tb_record_axi_write(int'(ep_aw_addr_lat), int'(ep_rx_wdata[15:0]), int'(32'h3));
        ep_aw_pending <= 1'b0;
        ep_tx_bresp   <= 2'b00;
        ep_tx_bvalid  <= 1'b1;
      end
    end
  end

`ifdef TB_RTL_HIER_DEBUG
  // --------------------------------------------------------------------------
  // RTL-only completion / timeout monitor and deep debug probes.
  //
  // These use hierarchical references into RTL internals. Gate-level netlists
  // do not preserve those names, so keep this block opt-in only.
  // --------------------------------------------------------------------------
  task automatic print_param_debug();
    $display("hello?");
    $display("TID W: %0d", DICE_TID_WIDTH);
    $display("REG W: %0d", DICE_REG_ADDR_WIDTH);
  endtask

  int unsigned cyc_count;
  int unsigned complete_seen_cycle;
  localparam int unsigned POST_COMPLETE_DRAIN_CYC = 1024;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cyc_count           <= 0;
      complete_seen_cycle <= 0;
    end else begin
      cyc_count <= cyc_count + 1;
      if (u_dut.u_mini_dice_top.u_csr.complete_sticky_r && complete_seen_cycle == 0)
        complete_seen_cycle <= cyc_count;
      if ((complete_seen_cycle != 0)
          && ((cyc_count - complete_seen_cycle) >= POST_COMPLETE_DRAIN_CYC)) begin
        if (dice_core_tb_check_done() != 0) begin
          $display("[TB] PASS: CSR complete observed and DPI write diff clean after drain");
          print_param_debug();
          $finish;
        end
        $fatal(1, "CSR complete observed but DPI write diff failed after drain");
      end
      if (cyc_count >= TIMEOUT_CYC) begin
        $display("[TB] TIMEOUT at %0d cycles", cyc_count);
        if (dice_core_tb_check_done() != 0)
          $display("[TB] (timeout) PASS-at-timeout: DPI write diff clean");
        $fatal(1, "timeout");
      end
    end
  end

  // --------------------------------------------------------------------------
  // Debug probes (same signals, deep path now includes u_mini_dice_top)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i)
    if (!rst_i) begin
      if (ep_rx_arvalid && ep_rx_arready)
        $display(
            "[EP] t=%0t AR addr=0x%04x len=%0d kind=%0d is_meta=%0b meta=0x%03x",
            $time,
            ep_rx_araddr,
            ep_rx_arlen,
            (ep_rx_araddr >= start_pc_val) ? 2'd1 : (ep_rx_arlen > 8'd8) ? 2'd2 : 2'd0,
            ep_rx_aruser_is_meta,
            ep_rx_aruser[12:0]
        );
      if (ep_rx_awvalid && !ep_aw_pending)
        $display("[EP] t=%0t AW addr=0x%04x", $time, ep_rx_awaddr);
      if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid)
        $display("[EP] t=%0t W  addr=0x%04x data=0x%04x", $time, ep_aw_addr_lat, ep_rx_wdata[15:0]);
    end

  always_ff @(posedge clk_i)
    if (!rst_i) begin
      if (u_dut.u_mini_dice_top.mfetch_req.ar_valid && u_dut.u_mini_dice_top.mfetch_resp.ar_ready)
        $display(
            "[HIER][DC] t=%0t mfetch AR addr=0x%04x len=%0d",
            $time,
            u_dut.u_mini_dice_top.mfetch_req.ar.addr,
            u_dut.u_mini_dice_top.mfetch_req.ar.len
        );
      if (u_dut.u_mini_dice_top.bsfetch_req.ar_valid && u_dut.u_mini_dice_top.bsfetch_resp.ar_ready)
        $display(
            "[HIER][DC] t=%0t bsfetch AR addr=0x%04x len=%0d",
            $time,
            u_dut.u_mini_dice_top.bsfetch_req.ar.addr,
            u_dut.u_mini_dice_top.bsfetch_req.ar.len
        );
      if (|u_dut.u_mini_dice_top.dfetch_arvalid && |u_dut.u_mini_dice_top.dfetch_arready)
        $display(
            "[HIER][DC] t=%0t dfetch AR valid=%b ready=%b addr=%p",
            $time,
            u_dut.u_mini_dice_top.dfetch_arvalid,
            u_dut.u_mini_dice_top.dfetch_arready,
            u_dut.u_mini_dice_top.dfetch_araddr
        );
      if (|u_dut.u_mini_dice_top.dfetch_awvalid && |u_dut.u_mini_dice_top.dfetch_awready)
        $display(
            "[HIER][DC] t=%0t dfetch AW valid=%b ready=%b addr=%p",
            $time,
            u_dut.u_mini_dice_top.dfetch_awvalid,
            u_dut.u_mini_dice_top.dfetch_awready,
            u_dut.u_mini_dice_top.dfetch_awaddr
        );
      if (u_dut.u_mini_dice_top.u_io_top.xbar_mem_req.ar_valid &&
        u_dut.u_mini_dice_top.u_io_top.xbar_mem_resp.ar_ready)
        $display(
            "[HIER][XB] t=%0t xbar_mem AR addr=0x%04x len=%0d",
            $time,
            u_dut.u_mini_dice_top.u_io_top.xbar_mem_req.ar.addr,
            u_dut.u_mini_dice_top.u_io_top.xbar_mem_req.ar.len
        );
    end

  int hb_count;
  always_ff @(posedge clk_i)
    if (!rst_i) begin
      hb_count <= hb_count + 1;
      if ((hb_count % 2000) == 0)
        $display(
            "[HB] t=%0t beat=%0d  ep_tx_rv=%b rrdy=%b | chip.rx_rv=%b rrdy=%b",
            $time,
            rd_beat_idx_q,
            ep_tx_rvalid,
            ep_tx_rready,
            u_dut.u_mini_dice_top.u_io_top.rx_rvalid,
            u_dut.u_mini_dice_top.u_io_top.xbar_mem_req.r_ready
        );
    end

  int csr_dump_once;
  always_ff @(posedge clk_i)
    if (!rst_i) begin
      if (u_dut.u_mini_dice_top.u_csr.start_o && csr_dump_once == 0) begin
        csr_dump_once <= 1;
        $display(
            "[CSR] t=%0t start_o=1 start_pc=0x%04x csrX0..7={%04x %04x %04x %04x %04x %04x %04x %04x}",
            $time, u_dut.u_mini_dice_top.u_csr.start_pc_o, u_dut.u_mini_dice_top.u_csr.csrX_r[0],
            u_dut.u_mini_dice_top.u_csr.csrX_r[1], u_dut.u_mini_dice_top.u_csr.csrX_r[2],
            u_dut.u_mini_dice_top.u_csr.csrX_r[3], u_dut.u_mini_dice_top.u_csr.csrX_r[4],
            u_dut.u_mini_dice_top.u_csr.csrX_r[5], u_dut.u_mini_dice_top.u_csr.csrX_r[6],
            u_dut.u_mini_dice_top.u_csr.csrX_r[7]);
      end
      if (u_dut.u_mini_dice_top.u_cta_if.dispatch_valid && u_dut.u_mini_dice_top.u_cta_if.dispatch_ready)
        $display(
            "[CTA] t=%0t dispatch handshake start_pc=0x%04x",
            $time,
            u_dut.u_mini_dice_top.u_cta_if.dispatch_data.kernel_desc.start_pc
        );
    end
`endif

  // --------------------------------------------------------------------------
  // AXI write + CSR write tasks (same as tb_mini_dice)
  // --------------------------------------------------------------------------
  task automatic axi_write(input logic [AW-1:0] addr, input logic [DW-1:0] data,
                           input logic [DW/8-1:0] strb = 4'hF);
    begin
      @(posedge clk_i);
      #1;
      ep_tx_awaddr  = addr;
      ep_tx_awlen   = '0;
      ep_tx_awsize  = 3'b010;
      ep_tx_awburst = BURST_INCR;
      ep_tx_awvalid = 1'b1;
      do @(posedge clk_i); while (!ep_tx_awready);
      #1;
      ep_tx_awvalid = 1'b0;
      $display("[AXI_WR] t=%0t AW accepted addr=0x%04x", $time, addr);

      ep_tx_wdata  = data;
      ep_tx_wlast  = 1'b1;
      ep_tx_wvalid = 1'b1;
      do @(posedge clk_i); while (!ep_tx_wready);
      #1;
      ep_tx_wvalid = 1'b0;
      $display("[AXI_WR] t=%0t W  accepted data=0x%08x", $time, data);

      ep_rx_bready = 1'b1;
      begin : b_hs
        int unsigned bwait = 0;
        do begin
          @(posedge clk_i);
          bwait++;
          if (bwait == 200) $display("[AXI_WR] t=%0t B STUCK addr=0x%04x", $time, addr);
        end while (!ep_rx_bvalid);
        $display("[AXI_WR] t=%0t B  accepted addr=0x%04x (cyc=%0d)", $time, addr, bwait);
      end
      @(posedge clk_i);
      #1;
      ep_rx_bready = 1'b0;
    end
  endtask

  task automatic csr_write(input logic [AW-1:0] reg_offset, input logic [15:0] data16);
    axi_write(reg_offset, DW'(data16), 4'b0011);
  endtask

  // --------------------------------------------------------------------------
  // bsg_link bringup (drives PAD signals via the logic variables above)
  // --------------------------------------------------------------------------
  task automatic bsg_link_bringup();
    begin
      hard_reset                  = 1'b1;
      rst_i                       = 1'b1;
      ep_upstream_io_link_reset   = 1'b1;
      ep_downstream_io_link_reset = 1'b1;
      ep_async_token_reset        = 1'b0;
      repeat (4) @(posedge clk_i);

      @(posedge clk_i);
      #1;
      ep_async_token_reset = 1'b1;
      @(posedge clk_i);
      #1;
      ep_async_token_reset = 1'b0;
      repeat (8) @(posedge clk_i);

      @(posedge clk_i);
      #1;
      ep_upstream_io_link_reset = 1'b0;
      repeat (8) @(posedge clk_i);

      // Release chip hard reset first; chip_top internally sequences its
      // bsg_link resets before Mini_Dice consumes the core-side flit stream.
      @(posedge clk_i);
      #1;
      hard_reset = 1'b0;
      repeat (64) @(posedge clk_i);

      // The chip is now driving up_clk, so the FPGA-side downstream receiver
      // can safely start sampling the chip -> FPGA link.
      @(posedge clk_i);
      #1;
      ep_downstream_io_link_reset = 1'b0;
      repeat (8) @(posedge clk_i);

      // Release FPGA core-side logic last, matching the zeroscatter link TB.
      @(posedge clk_i);
      #1;
      rst_i = 1'b0;
      repeat (4) @(posedge clk_i);
    end
  endtask

  // --------------------------------------------------------------------------
  // Collateral loading + launch (identical to tb_mini_dice)
  // --------------------------------------------------------------------------
  string test_vector_name, test_vector_dir, test_vector_stem;
  string cta_desc_mem_file, meta_mem_file, bitstream_mem_file, runtime_json_file;

  function automatic bit has_path_component(input string path);
    if (path.len() == 0) return 1'b0;
    if (path.getc(0) == "/") return 1'b1;
    for (int i = 0; i < path.len(); i++) if (path.getc(i) == "/") return 1'b1;
    return 1'b0;
  endfunction

  task automatic init_paths();
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
  endtask

  task automatic load_collateral();
    logic [CTA_DESC_WORDS*32-1:0] packed_desc;
    packed_desc = '0;
    dice_core_tb_init(cta_desc_mem_file, meta_mem_file, bitstream_mem_file, runtime_json_file);
    if (dice_core_tb_has_init_error())
      $fatal(1, "[TB] DPI init failed: %s", dice_core_tb_get_init_error());
    for (int w = 0; w < CTA_DESC_WORDS; w++)
      packed_desc[w*32+:32] = dice_core_tb_get_cta_desc_word(w);
    launch_desc = dice_cta_desc_t'(packed_desc[CTA_DESC_BITS-1:0]);
    for (int i = 0; i < 8; i++) csr_values[i] = 16'(dice_core_tb_get_csr(i));
    start_pc_val = 16'(launch_desc.kernel_desc.start_pc);
    void'($value$plusargs("START_PC=%h", start_pc_val));
    $display("[TB] Test vector stem      : %s", test_vector_stem);
    $display("[TB] csrX0..7              : %04x %04x %04x %04x %04x %04x %04x %04x", csr_values[0],
             csr_values[1], csr_values[2], csr_values[3], csr_values[4], csr_values[5],
             csr_values[6], csr_values[7]);
    $display("[TB] start_pc              : 0x%04x", start_pc_val);
  endtask

  task automatic program_csrs_and_launch();
    $display("[TB] Programming csrX0..7 via bsg_link host path");
    for (int i = 0; i < 8; i++) csr_write(REG_CSRX0 + AW'(i * 2), csr_values[i]);
    $display("[TB] Setting start_pc = 0x%04x", start_pc_val);
    csr_write(REG_STARTPC, start_pc_val);
    $display("[TB] Setting thread_count = %0d", launch_desc.kernel_desc.thread_count);
    csr_write(REG_THREAD_COUNT, 16'(launch_desc.kernel_desc.thread_count));
    $display("[TB] Pulsing CTRL.start");
    csr_write(REG_CTRL, CTRL_START);
  endtask

  task automatic wait_for_complete();
    int unsigned settle_cycles = 500000;
    void'($value$plusargs("SETTLE=%d", settle_cycles));
    $display("[TB] Running for up to %0d cycles, then checking DPI", settle_cycles);
    repeat (settle_cycles) @(posedge clk_i);
  endtask

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------
  initial begin
    int unsigned ok;

    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_chip_top, "+struct", "+mda");

    init_paths();
    bsg_link_bringup();
    load_collateral();
    program_csrs_and_launch();
    wait_for_complete();

    ok = dice_core_tb_check_done();

    if (ok != 0) begin
      $display("[TB] PASS: chip_top DPI checks clean");
      $display("hello?");
      $display("TID W: %0d", DICE_TID_WIDTH);
      $display("REG W: %0d", DICE_REG_ADDR_WIDTH);
      $finish;
    end
    $display("[TB] FAIL: DPI reported AXI write mismatch");
    $fatal(1, "FAIL");
  end

endmodule
