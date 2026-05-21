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

// `define TB_RTL_HIER_DEBUG

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

// Multi-CTA extensions: per_cta_csr_overrides accessors. Both fall back to
// the launch-time csr_values when the override table is missing or empty,
// so single-CTA kernels see byte-identical behavior to the legacy path.
import "DPI-C" context function int unsigned dice_core_tb_num_ctas();
import "DPI-C" context function int unsigned dice_core_tb_get_per_cta_csr(
  input int unsigned cta_idx,
  input int unsigned csr_idx
);

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
  localparam int TIMEOUT_CYC = 700000;
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

  localparam string DEFAULT_TEST_VECTOR = "gemm";
  localparam string DEFAULT_TEST_VECTOR_DIR = "tb/test_vectors/gemm";

  // --------------------------------------------------------------------------
  // Clock / reset drivers (TB-side logic, mapped to PAD below)
  // --------------------------------------------------------------------------
  bit   clk_i;
  bit   dn_io_clk;  // FPGA TX I/O master clock; oddr PHY forwards PAD[8].
  logic rst_i = 1'b1;  // FPGA endpoint/core reset
  logic hard_reset = 1'b1;  // chip hard reset on PAD[45]
  logic ep_upstream_io_link_reset = 1'b1;
  logic ep_async_token_reset = 1'b0;
  logic ep_downstream_io_link_reset = 1'b1;
  logic ep_downstream_io_link_reset_sync;
  logic tb_pad_drive_en = 1'b0;

  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;
  initial forever #(CLK_HALF_NS * 1ns) dn_io_clk = ~dn_io_clk;

  // --------------------------------------------------------------------------
  // PAD bus — chip_top inout
  // --------------------------------------------------------------------------
  tri   [  47:0] PAD;
  logic [  47:0] pad_drv;
  logic [  47:0] pad_oe;

  // EP upstream outputs -> chip downstream inputs.
  wire           ep_up_clk_r;
  wire           ep_up_valid_r;
  wire  [CW-1:0] ep_up_data_r;
  wire           ep_dn_token_r;

  function automatic logic kz(input logic v);
    kz = (v === 1'b1) ? 1'b1 : 1'b0;
  endfunction

  genvar pad_idx;
  generate
    for (pad_idx = 0; pad_idx < 48; pad_idx++) begin : gen_pad_drive
      assign PAD[pad_idx] = pad_oe[pad_idx] ? pad_drv[pad_idx] : 1'bz;
    end
  endgenerate

  always_comb begin
    pad_drv = '0;
    pad_oe = '0;

    // zeroscatter-compatible chip_top pad map.
    pad_drv[44] = kz(clk_i);  // core_clk
    pad_drv[45] = kz(hard_reset);
    pad_oe[44] = tb_pad_drive_en;
    pad_oe[45] = tb_pad_drive_en;

    // EP upstream outputs -> chip downstream inputs.
    pad_drv[8] = kz(ep_up_clk_r);
    pad_drv[9] = kz(ep_up_valid_r);
    pad_oe[8] = tb_pad_drive_en;
    pad_oe[9] = tb_pad_drive_en;
    for (int i = 0; i < CW; i++) begin
      pad_drv[dn_data_pad(i)] = kz(ep_up_data_r[i]);
      pad_oe[dn_data_pad(i)]  = tb_pad_drive_en;
    end

    // Chip TX-side credit return into EP upstream.
    pad_drv[12] = kz(ep_dn_token_r);
    pad_oe[12]  = tb_pad_drive_en;

    // DFT scan inputs tied off when the scan config enables them.
    pad_drv[11] = 1'b0;
    pad_drv[46] = 1'b0;
    pad_oe[11]  = tb_pad_drive_en;
    pad_oe[46]  = tb_pad_drive_en;
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
  // FPGA endpoint: decode packets from the DUT with axi_link_rx, and emit the
  // FPGA-side WRITE / READ_RESP packet headers directly into bsg_link.
  // --------------------------------------------------------------------------
  logic          ep_tx_awvalid = 1'b0;
  logic          ep_tx_awready;
  logic [AW-1:0] ep_tx_awaddr = '0;
  logic [   7:0] ep_tx_awlen = '0;
  logic [   2:0] ep_tx_awsize = 3'b010;
  logic [   1:0] ep_tx_awburst = BURST_INCR;
  logic [   1:0] ep_tx_awid = '0;

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
  logic          ep_tx_ar_is_burst = 1'b0;
  logic [   1:0] ep_tx_arid = '0;
  logic [   3:0] ep_tx_ar_tid = '0;
  logic [   2:0] ep_tx_ar_eblock = '0;
  logic [   4:0] ep_tx_ar_regaddr = '0;

  logic          ep_tx_rvalid = 1'b0;
  logic [DW-1:0] ep_tx_rdata = '0;
  logic          ep_tx_rlast = 1'b0;
  logic [   1:0] ep_tx_rresp = '0;
  logic [   1:0] ep_tx_rid = '0;
  logic          ep_tx_r_is_burst = 1'b0;
  logic [   7:0] ep_tx_rlen = '0;
  logic          ep_tx_rready;

  logic          ep_tx_bvalid = 1'b0;
  logic [   1:0] ep_tx_bresp = '0;
  logic          ep_tx_bready;

  logic          ep_rx_awvalid;
  logic [AW-1:0] ep_rx_awaddr;
  logic [   7:0] ep_rx_awlen;
  logic [   1:0] ep_rx_awid;
  logic          ep_rx_wvalid;
  logic [DW-1:0] ep_rx_wdata;
  logic          ep_rx_wlast;
  logic          ep_rx_arvalid;
  logic          ep_rx_arready;
  logic [AW-1:0] ep_rx_araddr;
  logic [   7:0] ep_rx_arlen;
  logic          ep_rx_ar_is_burst;
  logic [   1:0] ep_rx_arid;
  logic [   3:0] ep_rx_ar_tid;
  logic [   2:0] ep_rx_ar_eblock;
  logic [   4:0] ep_rx_ar_regaddr;
  logic          ep_rx_aruser_is_meta;
  logic [  12:0] ep_rx_aruser_meta;
  logic          ep_rx_rvalid;
  logic          ep_rx_rready = 1'b0;
  logic [DW-1:0] ep_rx_rdata;
  logic [   1:0] ep_rx_rresp;
  logic          ep_rx_rlast;
  logic [   1:0] ep_rx_rid;
  logic          ep_rx_r_is_burst;
  logic          ep_rx_bvalid;
  logic          ep_rx_bready = 1'b0;
  logic [   1:0] ep_rx_bresp;

  logic [FW-1:0] ep_link_rx_data;
  logic          ep_link_rx_valid;
  logic          ep_link_rx_yumi;
  logic [FW-1:0] ep_link_tx_data;
  logic          ep_link_tx_valid;
  logic          ep_link_tx_ready;

  bsg_link_ddr_upstream #(
      .width_p        (FW),
      .channel_width_p(CW),
      .num_channels_p (1),
      .lg_fifo_depth_p(4)
  ) u_fpga_tx_link (
      .core_clk_i         (clk_i),
      .core_link_reset_i  (rst_i),
      .core_data_i        (ep_link_tx_data),
      .core_valid_i       (ep_link_tx_valid),
      .core_ready_o       (ep_link_tx_ready),
      .io_clk_i           (dn_io_clk),
      .io_link_reset_i    (ep_upstream_io_link_reset),
      .async_token_reset_i(ep_async_token_reset),
      .io_clk_r_o         (ep_up_clk_r),
      .io_data_r_o        (ep_up_data_r),
      .io_valid_r_o       (ep_up_valid_r),
      .token_clk_i        (dut_dn_token_r)
  );

  bsg_sync_sync #(
      .width_p(1)
  ) u_fpga_rx_reset_sync (
      .oclk_i     (dut_up_clk_r),
      .iclk_data_i(ep_downstream_io_link_reset),
      .oclk_data_o(ep_downstream_io_link_reset_sync)
  );

  bsg_link_ddr_downstream #(
      .width_p        (FW),
      .channel_width_p(CW),
      .num_channels_p (1),
      .lg_fifo_depth_p(4)
  ) u_fpga_rx_link (
      .core_clk_i       (clk_i),
      .core_link_reset_i(rst_i),
      .io_link_reset_i  (ep_downstream_io_link_reset_sync),
      .core_data_o      (ep_link_rx_data),
      .core_valid_o     (ep_link_rx_valid),
      .core_yumi_i      (ep_link_rx_yumi),
      .io_clk_i         (dut_up_clk_r),
      .io_data_i        (dut_up_data_r),
      .io_valid_i       (dut_up_valid_r),
      .core_token_r_o   (ep_dn_token_r)
  );

  axi_link_rx #(
      .flit_width_p      (FW),
      .addr_width_p      (AW),
      .link_fifo_els_p   (64),
      .aw_desc_fifo_els_p(2),
      .ar_desc_fifo_els_p(2),
      .w_len_fifo_els_p  (4),
      .w_data_fifo_els_p (8),
      .r_len_fifo_els_p  (4),
      .r_data_fifo_els_p (64)
  ) u_fpga_ep_rx (
      .clk_i  (clk_i),
      .reset_i(rst_i),

      .link_rx_data_i(ep_link_rx_data),
      .link_rx_v_i   (ep_link_rx_valid),
      .link_rx_yumi_o(ep_link_rx_yumi),

      .awvalid_o    (ep_rx_awvalid),
      .awready_i    (1'b1),
      .awaddr_o     (ep_rx_awaddr),
      .awlen_o      (ep_rx_awlen),
      .awsize_o     (),
      .awburst_o    (),
      .awid_o       (ep_rx_awid),
      .wvalid_o     (ep_rx_wvalid),
      .wready_i     (1'b1),
      .wdata_o      (ep_rx_wdata),
      .wlast_o      (ep_rx_wlast),
      .arvalid_o    (ep_rx_arvalid),
      .arready_i    (ep_rx_arready),
      .araddr_o     (ep_rx_araddr),
      .arlen_o      (ep_rx_arlen),
      .arsize_o     (),
      .arburst_o    (),
      .ar_is_burst_o(ep_rx_ar_is_burst),
      .arid_o       (ep_rx_arid),
      .ar_tid_o     (ep_rx_ar_tid),
      .ar_eblock_o  (ep_rx_ar_eblock),
      .ar_regaddr_o (ep_rx_ar_regaddr),
      .rvalid_o     (ep_rx_rvalid),
      .rready_i     (ep_rx_rready),
      .rdata_o      (ep_rx_rdata),
      .rresp_o      (ep_rx_rresp),
      .rlast_o      (ep_rx_rlast),
      .rid_o        (ep_rx_rid),
      .r_is_burst_o (ep_rx_r_is_burst)
  );

  localparam logic [1:0] EP_OP_WRITE = 2'b00;
  localparam logic [1:0] EP_OP_READ_RESP = 2'b01;

  typedef enum logic [1:0] {
    EP_TX_IDLE,
    EP_TX_WR_DATA,
    EP_TX_R_DATA
  } ep_tx_state_e;

  ep_tx_state_e ep_tx_state_q, ep_tx_state_n;

  always_comb begin
    ep_link_tx_valid = 1'b0;
    ep_link_tx_data  = '0;
    ep_tx_awready    = 1'b0;
    ep_tx_wready     = 1'b0;
    ep_tx_arready    = 1'b0;
    ep_tx_rready     = 1'b0;
    ep_tx_bready     = 1'b1;
    ep_tx_state_n    = ep_tx_state_q;

    unique case (ep_tx_state_q)
      EP_TX_IDLE: begin
        if (ep_tx_rvalid) begin
          ep_link_tx_valid = 1'b1;
          ep_link_tx_data = {EP_OP_READ_RESP, ep_tx_rid, ep_tx_r_is_burst, 3'b0, ep_tx_rlen, 16'b0};
          if (ep_link_tx_ready) ep_tx_state_n = EP_TX_R_DATA;
        end else if (ep_tx_awvalid) begin
          ep_link_tx_valid = 1'b1;
          ep_link_tx_data  = {EP_OP_WRITE, ep_tx_awid, 12'b0, ep_tx_awaddr};
          ep_tx_awready    = ep_link_tx_ready;
          if (ep_link_tx_ready) ep_tx_state_n = EP_TX_WR_DATA;
        end
      end

      EP_TX_WR_DATA: begin
        ep_link_tx_valid = ep_tx_wvalid;
        ep_link_tx_data  = ep_tx_wdata;
        ep_tx_wready     = ep_link_tx_ready;
        if (ep_tx_wvalid && ep_link_tx_ready) ep_tx_state_n = EP_TX_IDLE;
      end

      EP_TX_R_DATA: begin
        ep_link_tx_valid = ep_tx_rvalid;
        ep_link_tx_data  = ep_tx_rdata;
        ep_tx_rready     = ep_link_tx_ready;
        if (ep_tx_rvalid && ep_link_tx_ready && ep_tx_rlast) ep_tx_state_n = EP_TX_IDLE;
      end

      default: ep_tx_state_n = EP_TX_IDLE;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ep_tx_state_q <= EP_TX_IDLE;
      ep_rx_bvalid  <= 1'b0;
      ep_rx_bresp   <= '0;
    end else begin
      ep_tx_state_q <= ep_tx_state_n;
      if (ep_rx_bvalid && ep_rx_bready) ep_rx_bvalid <= 1'b0;
      if (ep_tx_state_q == EP_TX_WR_DATA && ep_tx_wvalid && ep_link_tx_ready) begin
        ep_rx_bvalid <= 1'b1;
        ep_rx_bresp  <= 2'b00;
      end
    end
  end

  assign ep_rx_aruser_is_meta = !ep_rx_ar_is_burst;
  assign ep_rx_aruser_meta    = {1'b0, ep_rx_ar_tid, ep_rx_ar_eblock, ep_rx_ar_regaddr};

  // --------------------------------------------------------------------------
  // FPGA memory model
  // --------------------------------------------------------------------------
  localparam int MetaBeatBytes = DW / 8;

  localparam int unsigned TB_READ_RESP_DELAY_CYC = 10;
  localparam int unsigned TB_READ_RESP_DELAY_W = (TB_READ_RESP_DELAY_CYC <= 1) ? 1 : $clog2(
      TB_READ_RESP_DELAY_CYC + 1
  );

  typedef enum logic [1:0] {
    RD_IDLE,
    RD_WAIT,
    RD_ACTIVE
  } rd_state_e;
  rd_state_e rd_state_q;
  logic [AW-1:0] rd_base_addr_q;
  logic [7:0] rd_arlen_q;
  logic [7:0] rd_beat_idx_q;
  logic [TB_READ_RESP_DELAY_W-1:0] rd_delay_q;
  logic [1:0] rd_kind_q;
  logic rd_aruser_is_meta_q;
  logic [12:0] rd_aruser_q;
  logic [15:0] csr_values[0:7];
  logic [15:0] start_pc_val;
  dice_cta_desc_t launch_desc;

  // Number of CTAs in the grid (= number of per_cta_csr_overrides entries
  // parsed from runtime.json). Zero from the DPI means single-CTA, which we
  // coerce to 1 so the launch loop runs exactly once -- byte-identical to the
  // legacy single-shot path.
  int unsigned num_ctas;

  // Per-CTA completion is sensed by polling REG_STATUS[0] (sticky `complete`
  // bit defined in rtl/cgra_core/internal_memory/cgra_io_csr.sv). The chip
  // clears that bit on the next CTRL.START write, so each CTA's wait sees a
  // fresh edge. This is the same handshake the post-tapeout host driver will
  // use -- only the chip's public CSR/AXI interface, no internal XMRs --
  // which keeps the multi-CTA launch loop working under post-syn / PnR sims
  // where instance names get mangled. See `wait_for_cta_done` below.
  //
  // Flag the run_grid loop raises after the last CTA's status-poll succeeds.
  // Declared at module scope so the (gated) TB_RTL_HIER_DEBUG fast-exit
  // monitor can watch it without an XMR. Always defined so the initial
  // block can set it unconditionally.
  logic all_ctas_done_q = 1'b0;

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
      rd_delay_q          <= '0;
      rd_kind_q           <= '0;
      rd_aruser_is_meta_q <= 1'b0;
      rd_aruser_q         <= '0;
      ep_tx_rvalid        <= 1'b0;
      ep_tx_rlast         <= 1'b0;
      ep_tx_rdata         <= '0;
      ep_tx_rresp         <= '0;
      ep_tx_rid           <= '0;
      ep_tx_r_is_burst    <= 1'b0;
      ep_tx_rlen          <= '0;
      ep_tx_bvalid        <= 1'b0;
      ep_aw_pending       <= 1'b0;
      ep_aw_addr_lat      <= '0;
    end else begin
      unique case (rd_state_q)
        RD_IDLE: begin
          if (ep_rx_arvalid && ep_rx_arready) begin
            logic [1:0] kind;
            if (ep_rx_ar_is_burst) kind = ep_rx_arid[0] ? 2'd2 : 2'd1;
            else kind = 2'd0;
            rd_base_addr_q <= ep_rx_araddr;
            rd_arlen_q <= ep_rx_arlen;
            rd_beat_idx_q <= '0;
            rd_kind_q <= kind;
            rd_aruser_is_meta_q <= ep_rx_aruser_is_meta;
            rd_aruser_q <= ep_rx_aruser_meta;
            ep_tx_rid <= ep_rx_arid;
            ep_tx_r_is_burst <= ep_rx_ar_is_burst;
            ep_tx_rlen <= ep_rx_arlen;
            ep_tx_rresp <= 2'b00;
            rd_delay_q <= TB_READ_RESP_DELAY_W'(TB_READ_RESP_DELAY_CYC);
            rd_state_q <= RD_WAIT;
          end
        end
        RD_WAIT: begin
          if (rd_delay_q == TB_READ_RESP_DELAY_W'(1)) begin
            rd_delay_q <= '0;
            ep_tx_rdata <= pack_read_beat(
                rd_kind_q, rd_base_addr_q, 0, rd_aruser_is_meta_q, rd_aruser_q
            );
            ep_tx_rlast <= (rd_arlen_q == 8'd0);
            ep_tx_rvalid <= 1'b1;
            rd_state_q <= RD_ACTIVE;
          end else begin
            rd_delay_q <= rd_delay_q - TB_READ_RESP_DELAY_W'(1);
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

  // Fast-exit completion / drain monitor (gated by TB_RTL_HIER_DEBUG above).
  //
  // After the run_grid initial block has dispatched and waited on every
  // CTA's STATUS bit, it sets `all_ctas_done_q` (a normal SV variable, no
  // XMRs). This monitor then arms a short drain timer and runs the DPI
  // diff -- giving devs in RTL sim a fast-exit path vs. the initial
  // block's longer 500 000-cycle settle. The TIMEOUT_CYC watchdog stays
  // as a final safety net.
  //
  // Removed in this revision: the cta_done_pulse handshake counter that
  // tapped `u_dut.u_mini_dice_top.u_cta_if.complete_*` directly. Driving
  // completion off `run_grid`'s loop variable keeps this block compatible
  // with gate-level / PnR sims that mangle internal instance names.
  int unsigned cyc_count;
  int unsigned complete_seen_cycle;
  // `all_ctas_done_q` lives at module scope (see declaration above) so
  // run_grid can set it whether or not TB_RTL_HIER_DEBUG is defined.
  localparam int unsigned POST_COMPLETE_DRAIN_CYC = 1024;
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cyc_count           <= 0;
      complete_seen_cycle <= 0;
    end else begin
      cyc_count <= cyc_count + 1;

      // Arm the post-grid drain timer the cycle run_grid finishes the
      // last CTA. `complete_seen_cycle == 0` guard latches on first rise.
      if (all_ctas_done_q && complete_seen_cycle == 0)
        complete_seen_cycle <= cyc_count;

      if ((complete_seen_cycle != 0)
          && ((cyc_count - complete_seen_cycle) >= POST_COMPLETE_DRAIN_CYC)) begin
        if (dice_core_tb_check_done() != 0) begin
          $display("[TB] PASS: all %0d CTAs complete and DPI write diff clean after drain",
                   num_ctas);
          print_param_debug();
          $finish;
        end
        $fatal(1, "all %0d CTAs complete but DPI write diff failed after drain", num_ctas);
      end
      if (cyc_count >= TIMEOUT_CYC) begin
        $display("[TB] TIMEOUT at %0d cycles (all_ctas_done_q=%0b)",
                 cyc_count, all_ctas_done_q);
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
            "[EP] t=%0t AR addr=0x%04x len=%0d kind=%0d is_burst=%0b id=%0d tid=%0d eblock=%0d reg=%0d meta=0x%03x",
            $time,
            ep_rx_araddr,
            ep_rx_arlen,
            ep_rx_ar_is_burst ? (ep_rx_arid[0] ? 2'd2 : 2'd1) : 2'd0,
            ep_rx_ar_is_burst,
            ep_rx_arid,
            ep_rx_ar_tid,
            ep_rx_ar_eblock,
            ep_rx_ar_regaddr,
            ep_rx_aruser_meta
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
      if (|u_dut.u_mini_dice_top.dfetch_wvalid && |u_dut.u_mini_dice_top.dfetch_wready)
        $display(
            "[HIER][DC] t=%0t dfetch W  valid=%b ready=%b data=%p",
            $time,
            u_dut.u_mini_dice_top.dfetch_wvalid,
            u_dut.u_mini_dice_top.dfetch_wready,
            u_dut.u_mini_dice_top.dfetch_wdata
        );
      if (|u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_port_valid_lo) begin
        $display(
            "[HIER][CGRA_MEM] t=%0t tid=%0d eblock=%0d valid=%b op=%b p0={addr=0x%04x data=0x%04x} p1={addr=0x%04x data=0x%04x} p2={addr=0x%04x data=0x%04x} p3={addr=0x%04x data=0x%04x}",
            $time, u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_tid_lo,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_e_block_id_lo,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_port_valid_lo,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_port_op_lo,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_addr_lo_0,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_data_lo_0,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_addr_lo_1,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_data_lo_1,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_addr_lo_2,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_data_lo_2,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_addr_lo_3,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.cgra_mem_data_lo_3);
      end
      if (|u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awvalid_o
          || |u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wvalid_o)
        $display(
            "[HIER][FIFO_AXI] t=%0t awv=%b awr=%b wv=%b wr=%b p0={aw=0x%04x w=0x%04x} p1={aw=0x%04x w=0x%04x} p2={aw=0x%04x w=0x%04x} p3={aw=0x%04x w=0x%04x}",
            $time,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awvalid_o,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awready_i,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wvalid_o,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wready_i,
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awaddr_o[0],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wdata_o[0],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awaddr_o[1],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wdata_o[1],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awaddr_o[2],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wdata_o[2],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_awaddr_o[3],
            u_dut.u_mini_dice_top.u_dice_core.u_dice_backend.axi_wdata_o[3]
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
      ep_tx_awid    = '0;
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

  // AXI-Lite single-beat read. Mirrors axi_write: drives AR on the EP_TX
  // side, waits for the chip's R response on EP_RX. Used to poll the chip's
  // CSR space (e.g. REG_STATUS for the sticky-complete bit).
  task automatic axi_read(input  logic [AW-1:0] addr,
                          output logic [DW-1:0] data);
    begin
      @(posedge clk_i);
      #1;
      ep_tx_araddr  = addr;
      ep_tx_arlen   = '0;
      ep_tx_arsize  = 3'b010;
      ep_tx_arburst = BURST_INCR;
      ep_tx_arid    = '0;
      ep_tx_arvalid = 1'b1;
      do @(posedge clk_i); while (!ep_tx_arready);
      #1;
      ep_tx_arvalid = 1'b0;

      ep_rx_rready = 1'b1;
      begin : r_hs
        int unsigned rwait = 0;
        do begin
          @(posedge clk_i);
          rwait++;
          if (rwait == 200)
            $display("[AXI_RD] t=%0t R STUCK addr=0x%04x", $time, addr);
        end while (!ep_rx_rvalid);
        data = ep_rx_rdata;
      end
      @(posedge clk_i);
      #1;
      ep_rx_rready = 1'b0;
    end
  endtask

  task automatic csr_read(input  logic [AW-1:0] reg_offset,
                          output logic [15:0]   data16);
    logic [DW-1:0] dw;
    axi_read(reg_offset, dw);
    data16 = dw[15:0];
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
      tb_pad_drive_en             = 1'b0;


      #(1ns);
      tb_pad_drive_en = 1'b1;

      // 1) Pulse FPGA TX async_token_reset while the FPGA TX I/O link is still
      // in reset.  This initializes the sender-side credit counters.
      repeat (8) @(posedge clk_i);
      @(posedge clk_i);
      #1;
      ep_async_token_reset = 1'b1;
      repeat (2) @(posedge clk_i);
      #1;
      ep_async_token_reset = 1'b0;

      // 2) Release FPGA TX I/O reset so the forwarded dn_clk on PAD[8] is
      // running before the chip's RX async FIFO reset is released.
      repeat (8) @(posedge dn_io_clk);
      @(posedge clk_i);
      #1;
      ep_upstream_io_link_reset = 1'b0;

      // 3) Release chip hard reset; chip_top internally sequences its bsg_link
      // reset domains over the next ~32 core clocks.
      @(posedge clk_i);
      @(negedge clk_i);
      hard_reset = 1'b0;
      repeat (64) @(posedge clk_i);

      // 4) The chip is now driving up_clk, so the FPGA-side downstream receiver
      // can safely start sampling the chip -> FPGA link.
      @(posedge clk_i);
      #1ns;
      ep_downstream_io_link_reset = 1'b0;
      repeat (8) @(posedge clk_i);

      // 5) Release FPGA core-side logic last.
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

    // Read the per-CTA override count. The DPI returns 0 for single-CTA test
    // vectors that lack a per_cta_csr_overrides key; coerce to 1 so the
    // launch loop runs once and behaves identically to the legacy path.
    num_ctas = dice_core_tb_num_ctas();
    if (num_ctas == 0) num_ctas = 1;

    $display("[TB] Test vector stem      : %s", test_vector_stem);
    $display("[TB] csrX0..7 (launch)     : %04x %04x %04x %04x %04x %04x %04x %04x", csr_values[0],
             csr_values[1], csr_values[2], csr_values[3], csr_values[4], csr_values[5],
             csr_values[6], csr_values[7]);
    $display("[TB] start_pc              : 0x%04x", start_pc_val);
    $display("[TB] num_ctas              : %0d (1 = no per_cta_csr_overrides in runtime.json)",
             num_ctas);
  endtask

  // Program csrX0..7 for one CTA via the host-side bsg_link path. Uses the
  // DPI getter that transparently falls back to the launch csr_values[] for
  // any CSR not overridden in this CTA's entry (so single-CTA kernels reduce
  // to the legacy one-shot programming).
  task automatic program_csrs_for_cta(input int unsigned cta_idx);
    logic [15:0] v;
    $display("[TB] CTA %0d: programming csrX0..7", cta_idx);
    for (int i = 0; i < 8; i++) begin
      v = 16'(dice_core_tb_get_per_cta_csr(cta_idx, i));
      csr_write(REG_CSRX0 + AW'(i * 2), v);
    end
  endtask

  // Wait for the per-CTA complete handshake via REG_STATUS polling.
  //
  // This is the same handshake the post-tapeout host driver will use: read
  // the chip's public STATUS CSR and wait for bit [0] (sticky `complete`)
  // to go high. The chip clears it on the next CTRL.START, so each CTA's
  // wait sees a fresh edge with no XMRs into chip internals.
  //
  // We poll on a coarse cadence (every POLL_INTERVAL_CYC) so the bsg_link
  // bandwidth stays mostly available for the chip's own mfetch / bsfetch /
  // dfetch traffic. Each csr_read traverses the link AR+R roundtrip once,
  // which is fine at this cadence.
  task automatic wait_for_cta_done(input int unsigned cta_idx);
    localparam int unsigned POLL_INTERVAL_CYC = 256;
    int unsigned cyc          = 0;
    int unsigned timeout_cyc  = 200_000;
    logic [15:0] status;
    void'($value$plusargs("PER_CTA_TIMEOUT=%d", timeout_cyc));

    forever begin
      repeat (POLL_INTERVAL_CYC) @(posedge clk_i);
      cyc += POLL_INTERVAL_CYC;
      csr_read(REG_STATUS, status);
      if (status[0]) begin
        $display("[TB] CTA %0d complete: STATUS=0x%04x after ~%0d cycles",
                 cta_idx, status, cyc);
        return;
      end
      if (cyc >= timeout_cyc) begin
        $fatal(1, "[TB] CTA %0d timed out after %0d cycles (last STATUS=0x%04x)",
               cta_idx, cyc, status);
      end
    end
  endtask

  // Replace the legacy single-shot program_csrs_and_launch() with a grid
  // loop. start_pc and thread_count are kernel-wide so they're written once;
  // csrX0..7 are reprogrammed per CTA from the override table.
  task automatic run_grid();
    $display("[TB] Programming kernel-wide CSRs via bsg_link");
    $display("[TB] Setting start_pc      = 0x%04x", start_pc_val);
    csr_write(REG_STARTPC, start_pc_val);
    $display("[TB] Setting thread_count  = %0d", launch_desc.kernel_desc.thread_count);
    csr_write(REG_THREAD_COUNT, 16'(launch_desc.kernel_desc.thread_count));

    for (int unsigned c = 0; c < num_ctas; c++) begin
      program_csrs_for_cta(c);
      $display("[TB] CTA %0d: pulsing CTRL.start", c);
      csr_write(REG_CTRL, CTRL_START);
      wait_for_cta_done(c);
    end
    // Signal to the (gated) TB_RTL_HIER_DEBUG monitor that the whole grid
    // is done -- it can then arm its short drain check. The post-tapeout
    // path doesn't care about this flag; the main `initial` block below
    // will continue into wait_for_complete() and dice_core_tb_check_done().
    all_ctas_done_q <= 1'b1;
  endtask

  // Final post-grid drain so any in-flight AXI writes settle before the DPI
  // diff check. Unchanged from the legacy task body.
  task automatic wait_for_complete();
    int unsigned settle_cycles = 500000;
    void'($value$plusargs("SETTLE=%d", settle_cycles));
    $display("[TB] Post-grid drain: up to %0d cycles, then checking DPI", settle_cycles);
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
    run_grid();  // was: program_csrs_and_launch()
    wait_for_complete();

    ok = dice_core_tb_check_done();

    if (ok != 0) begin
      $display("[TB] PASS: chip_top DPI checks clean (num_ctas=%0d)", num_ctas);
      $display("TID W: %0d", DICE_TID_WIDTH);
      $display("REG W: %0d", DICE_REG_ADDR_WIDTH);
      $finish;
    end
    $display("[TB] FAIL: DPI reported AXI write mismatch (num_ctas=%0d)", num_ctas);
    $fatal(1, "FAIL");
  end

endmodule
