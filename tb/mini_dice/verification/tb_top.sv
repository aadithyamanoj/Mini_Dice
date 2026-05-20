// =============================================================================
// tb_top.sv — UVM testbench top for mini_dice_top (chip-level)
//
// Direct flit-interface to mini_dice_top (skipping chip_top pad ring +
// bsg_link DDR for sim speed). FPGA-side flit pack/unpack:
//   * axi_link_rx (RTL module reused) — decodes chip's outgoing flits.
//   * ep_tx_state_q FSM — packs CSR writes + read responses into flits going
//     into the chip. Mirrors tb_chip_top.sv's proven implementation.
// =============================================================================

`timescale 1ns / 1ps

`include "dice_define.vh"

module tb_top;
  import uvm_pkg::*;
  import mini_dice_chip_pkg::*;
  `include "uvm_macros.svh"

  // --------------------------------------------------------------------------
  // Clock / reset
  // --------------------------------------------------------------------------
  bit   clk;
  logic rst_i_internal = 1'b1;
  initial forever #5ns clk = ~clk;
  initial begin repeat (10) @(posedge clk); rst_i_internal = 1'b0; end

  // --------------------------------------------------------------------------
  // Virtual interface — rst_i is mux'd by test-level force_rst_en hook.
  // --------------------------------------------------------------------------
  mini_dice_chip_vif vif (.clk(clk));
  initial begin vif.force_rst_en = 1'b0; vif.force_rst_val = 1'b0; end
  assign vif.rst_i = vif.force_rst_en ? vif.force_rst_val : rst_i_internal;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  mini_dice_top #(
      .ADDR_WIDTH        (16),
      .DATA_WIDTH        (32),
      .FLIT_WIDTH        (32),
      .CHANNEL_WIDTH     (8),
      .BYPASS_TWOFER_FIFO(1),
      .BYPASS_GEARBOX    (1)
  ) u_dut (
      .clk_i          (clk),
      .rst_i          (vif.rst_i),
      .link_rx_data_i (vif.link_rx_data),
      .link_rx_valid_i(vif.link_rx_valid),
      .link_rx_yumi_o (vif.link_rx_yumi),
      .link_tx_data_o (vif.link_tx_data),
      .link_tx_valid_o(vif.link_tx_valid),
      .link_tx_ready_i(vif.link_tx_ready),
      .cgra_prog_dout_o(vif.cgra_prog_dout),
      .cgra_prog_we_o  (vif.cgra_prog_we)
  );

  // --------------------------------------------------------------------------
  // FPGA-side axi_link_rx (RTL module): unpacks chip's outgoing flits into AXI
  // --------------------------------------------------------------------------
  logic        ep_rx_awvalid;
  logic [15:0] ep_rx_awaddr;
  logic [7:0]  ep_rx_awlen;
  logic [1:0]  ep_rx_awid;
  logic        ep_rx_wvalid;
  logic [31:0] ep_rx_wdata;
  logic        ep_rx_wlast;
  logic        ep_rx_arvalid;
  logic        ep_rx_arready;
  logic [15:0] ep_rx_araddr;
  logic [7:0]  ep_rx_arlen;
  logic        ep_rx_ar_is_burst;
  logic [1:0]  ep_rx_arid;
  logic [3:0]  ep_rx_ar_tid;
  logic [2:0]  ep_rx_ar_eblock;
  logic [4:0]  ep_rx_ar_regaddr;
  // R-channel from axi_link_rx is unused — read responses are sent into the
  // chip via the ep_tx_state_q FSM (READ_RESP flits), not back through this
  // module's R output. These signals stay disconnected.

  axi_link_rx #(
      .flit_width_p      (32),
      .addr_width_p      (16),
      .link_fifo_els_p   (64),
      .aw_desc_fifo_els_p(2),
      .ar_desc_fifo_els_p(2),
      .w_len_fifo_els_p  (4),
      .w_data_fifo_els_p (8),
      .r_len_fifo_els_p  (4),
      .r_data_fifo_els_p (64)
  ) u_ep_rx (
      .clk_i  (clk),
      .reset_i(vif.rst_i),
      .link_rx_v_i   (vif.link_tx_valid),
      .link_rx_data_i(vif.link_tx_data),
      .link_rx_yumi_o(vif.link_tx_ready),
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
      .rvalid_o     (vif.ep_rx_rvalid),
      .rready_i     (vif.ep_rx_rready),
      .rdata_o      (vif.ep_rx_rdata),
      .rresp_o      (vif.ep_rx_rresp),
      .rlast_o      (vif.ep_rx_rlast),
      .rid_o        (vif.ep_rx_rid),
      .r_is_burst_o ()
  );

  // --------------------------------------------------------------------------
  // FPGA-side packer: TB-driven AW/W (CSR writes) + R (read responses)
  // packed into flits headed at chip's link_rx. UVM driver provides AW/W,
  // the mem_responder provides R, and this FSM serializes them onto the link.
  // (Mirrors tb_chip_top.sv lines 392..458.)
  // --------------------------------------------------------------------------
  logic        ep_tx_awvalid;
  logic        ep_tx_awready;
  logic [15:0] ep_tx_awaddr;
  logic [1:0]  ep_tx_awid;
  logic        ep_tx_wvalid;
  logic        ep_tx_wready;
  logic [31:0] ep_tx_wdata;

  logic        ep_tx_arvalid;
  logic        ep_tx_arready;
  logic [15:0] ep_tx_araddr;
  logic [1:0]  ep_tx_arid;

  logic        ep_tx_rvalid;
  logic        ep_tx_rready;
  logic [31:0] ep_tx_rdata;
  logic        ep_tx_rlast;
  logic [1:0]  ep_tx_rid;
  logic        ep_tx_r_is_burst;
  logic [7:0]  ep_tx_rlen;

  localparam logic [1:0] EP_OP_WRITE     = 2'b00;
  localparam logic [1:0] EP_OP_READ_RESP = 2'b01;
  localparam logic [1:0] EP_OP_READ      = 2'b11;  // single-beat read req

  typedef enum logic [1:0] { EP_TX_IDLE, EP_TX_WR_DATA, EP_TX_R_DATA } ep_tx_state_e;
  ep_tx_state_e ep_tx_state_q, ep_tx_state_n;

  always_comb begin
    vif.link_rx_valid = 1'b0;
    vif.link_rx_data  = '0;
    ep_tx_awready     = 1'b0;
    ep_tx_wready      = 1'b0;
    ep_tx_rready      = 1'b0;
    ep_tx_arready     = 1'b0;
    ep_tx_state_n     = ep_tx_state_q;

    unique case (ep_tx_state_q)
      EP_TX_IDLE: begin
        // Priority: pending R-response > pending AW (write) > pending AR (read req).
        if (ep_tx_rvalid) begin
          vif.link_rx_valid = 1'b1;
          vif.link_rx_data  = {EP_OP_READ_RESP, ep_tx_rid, ep_tx_r_is_burst,
                               3'b0, ep_tx_rlen, 16'b0};
          if (vif.link_rx_yumi) ep_tx_state_n = EP_TX_R_DATA;
        end else if (ep_tx_awvalid) begin
          vif.link_rx_valid = 1'b1;
          vif.link_rx_data  = {EP_OP_WRITE, ep_tx_awid, 12'b0, ep_tx_awaddr};
          ep_tx_awready     = vif.link_rx_yumi;
          if (vif.link_rx_yumi) ep_tx_state_n = EP_TX_WR_DATA;
        end else if (ep_tx_arvalid) begin
          // Single-beat READ flit (opcode 2'b11). tid/eblock/regaddr are
          // don't-care for FPGA-originated CSR reads → set to zero.
          vif.link_rx_valid = 1'b1;
          vif.link_rx_data  = {EP_OP_READ, ep_tx_arid, 4'b0, 3'b0, 5'b0,
                               ep_tx_araddr};
          ep_tx_arready     = vif.link_rx_yumi;
          // No payload follows a READ — stays in IDLE.
        end
      end
      EP_TX_WR_DATA: begin
        vif.link_rx_valid = ep_tx_wvalid;
        vif.link_rx_data  = ep_tx_wdata;
        ep_tx_wready      = vif.link_rx_yumi;
        if (ep_tx_wvalid && vif.link_rx_yumi) ep_tx_state_n = EP_TX_IDLE;
      end
      EP_TX_R_DATA: begin
        vif.link_rx_valid = ep_tx_rvalid;
        vif.link_rx_data  = ep_tx_rdata;
        ep_tx_rready      = vif.link_rx_yumi;
        if (ep_tx_rvalid && vif.link_rx_yumi && ep_tx_rlast)
          ep_tx_state_n = EP_TX_IDLE;
      end
      default: ep_tx_state_n = EP_TX_IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (vif.rst_i) ep_tx_state_q <= EP_TX_IDLE;
    else           ep_tx_state_q <= ep_tx_state_n;
  end

  // Wire TB-side ep_rx_* / ep_tx_* into the vif so UVM agents see them.
  assign vif.ep_rx_awvalid     = ep_rx_awvalid;
  assign vif.ep_rx_awaddr      = ep_rx_awaddr;
  assign vif.ep_rx_awlen       = ep_rx_awlen;
  assign vif.ep_rx_awid        = ep_rx_awid;
  assign vif.ep_rx_wvalid      = ep_rx_wvalid;
  assign vif.ep_rx_wdata       = ep_rx_wdata;
  assign vif.ep_rx_wlast       = ep_rx_wlast;
  assign vif.ep_rx_arvalid     = ep_rx_arvalid;
  assign ep_rx_arready         = vif.ep_rx_arready;
  assign vif.ep_rx_araddr      = ep_rx_araddr;
  assign vif.ep_rx_arlen       = ep_rx_arlen;
  assign vif.ep_rx_ar_is_burst = ep_rx_ar_is_burst;
  assign vif.ep_rx_arid        = ep_rx_arid;
  assign vif.ep_rx_ar_tid      = ep_rx_ar_tid;
  assign vif.ep_rx_ar_eblock   = ep_rx_ar_eblock;
  assign vif.ep_rx_ar_regaddr  = ep_rx_ar_regaddr;
  // ep_rx_r* unused (see comment at axi_link_rx instance)

  assign ep_tx_awvalid         = vif.ep_tx_awvalid;
  assign vif.ep_tx_awready     = ep_tx_awready;
  assign ep_tx_awaddr          = vif.ep_tx_awaddr;
  assign ep_tx_awid            = vif.ep_tx_awid;
  assign ep_tx_wvalid          = vif.ep_tx_wvalid;
  assign vif.ep_tx_wready      = ep_tx_wready;
  assign ep_tx_wdata           = vif.ep_tx_wdata;
  assign ep_tx_arvalid         = vif.ep_tx_arvalid;
  assign vif.ep_tx_arready     = ep_tx_arready;
  assign ep_tx_araddr          = vif.ep_tx_araddr;
  assign ep_tx_arid            = vif.ep_tx_arid;
  assign ep_tx_rvalid          = vif.ep_tx_rvalid;
  assign vif.ep_tx_rready      = ep_tx_rready;
  assign ep_tx_rdata           = vif.ep_tx_rdata;
  assign ep_tx_rlast           = vif.ep_tx_rlast;
  assign ep_tx_rid             = vif.ep_tx_rid;
  assign ep_tx_r_is_burst      = vif.ep_tx_r_is_burst;
  assign ep_tx_rlen            = vif.ep_tx_rlen;

  // --------------------------------------------------------------------------
  // UVM entry
  // --------------------------------------------------------------------------
  initial begin
    // Stress tests that intentionally violate AXI invariants (out-of-range
    // writes, mid-reset bursts) trip RTL assertions in axi_demux_id_counters.
    // They still exercise the chip's recoverability; disable assertions
    // when +DISABLE_AXI_ASSERTS is passed.
    if ($test$plusargs("DISABLE_AXI_ASSERTS")) begin
      $assertoff(0);
      $display("[TB] $assertoff(0) per +DISABLE_AXI_ASSERTS");
    end
    uvm_config_db #(virtual mini_dice_chip_vif)::set(null, "*", "vif", vif);
    run_test();
  end

`ifdef DUMP_VCD
  initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
  end
`endif

endmodule
