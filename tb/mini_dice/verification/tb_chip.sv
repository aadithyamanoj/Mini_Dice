// =============================================================================
// tb_chip.sv — UVM testbench top for chip_top (full chip with pad ring +
// bsg_link DDR).
//
// Same UVM-facing vif as tb_top.sv (link_rx/link_tx 32-bit flits + ep_* AXI),
// so all 12 existing tests + agents + scoreboard work unchanged. The
// difference is what sits between the vif and the chip:
//
//   [vif.link_rx flits] -> [TB axi_link_tx] -> AXI -> [TB bsg_link_ddr_upstream]
//     -> 16-bit DDR -> PAD pins -> chip pad ring -> chip's bsg_link_wrapper
//     -> mini_dice_top.link_rx_*
//
//   chip's mini_dice_top.link_tx_* -> chip's bsg_link_wrapper -> PAD pins ->
//     [TB bsg_link_ddr_downstream] -> 32-bit flits -> [TB axi_link_rx] ->
//     [vif.link_tx flits, ep_rx_* AXI]
//
// Wait — we keep the same flit-level vif. Internally this TB inserts both
// the link DDR and the chip's own bsg_link, so the chip's reset sequencing,
// pad muxing, async FIFOs, and clock forwarding are all exercised.
//
// Reset sequencing mirrors tb_chip_top.sv's bsg_link_bringup() task.
// =============================================================================

`timescale 1ns / 1ps

`include "dice_define.vh"

module tb_chip;
  import uvm_pkg::*;
  import mini_dice_chip_pkg::*;
  `include "uvm_macros.svh"

  localparam int AW = 16;
  localparam int DW = 32;
  localparam int FW = 32;
  localparam int CW = 16;
  localparam int CLK_HALF_NS = 5;  // 100 MHz core clock

  // --------------------------------------------------------------------------
  // Clocks
  // --------------------------------------------------------------------------
  bit clk;
  bit dn_io_clk;
  initial forever #(CLK_HALF_NS * 1ns) clk = ~clk;
  initial forever #(CLK_HALF_NS * 1ns) dn_io_clk = ~dn_io_clk;

  // --------------------------------------------------------------------------
  // Reset controls (manipulated by the bringup process)
  // --------------------------------------------------------------------------
  logic rst_i                        = 1'b1;  // FPGA endpoint/core reset
  logic hard_reset                   = 1'b1;
  logic ep_upstream_io_link_reset    = 1'b1;
  logic ep_async_token_reset         = 1'b0;
  logic ep_downstream_io_link_reset  = 1'b1;
  logic ep_downstream_io_link_reset_sync;
  logic tb_pad_drive_en              = 1'b0;

  // --------------------------------------------------------------------------
  // Virtual interface (same as tb_top.sv).
  // Tests can assert vif.force_rst_en + vif.force_rst_val to override
  // BOTH the FPGA-side rst_i AND the chip's hard_reset PAD mid-run, allowing
  // mid-test reset to be exercised through the full pad-ring reset path.
  // --------------------------------------------------------------------------
  mini_dice_chip_vif vif (.clk(clk));
  initial begin vif.force_rst_en = 1'b0; vif.force_rst_val = 1'b0; end
  assign vif.rst_i = vif.force_rst_en ? vif.force_rst_val : rst_i;

  // --------------------------------------------------------------------------
  // PAD bus — chip_top inout
  // --------------------------------------------------------------------------
  tri   [47:0] PAD;
  logic [47:0] pad_drv;
  logic [47:0] pad_oe;

  // EP upstream outputs -> chip downstream inputs (forwarded by bsg_link).
  wire           ep_up_clk_r;
  wire           ep_up_valid_r;
  wire  [CW-1:0] ep_up_data_r;
  wire           ep_dn_token_r;

  function automatic logic kz(input logic v);
    kz = (v === 1'b1) ? 1'b1 : 1'b0;
  endfunction

  // Pad-drive: TB takes ownership of the PADs that are "inputs to chip"
  // when tb_pad_drive_en is asserted. The pad cells go high-Z internally
  // because chip configures OEN=1 for input pads — so the only driver is
  // this TB-side block.
  genvar pad_idx;
  generate
    for (pad_idx = 0; pad_idx < 48; pad_idx++) begin : gen_pad_drive
      assign PAD[pad_idx] = pad_oe[pad_idx] ? pad_drv[pad_idx] : 1'bz;
    end
  endgenerate

  // dn_data PAD mapping (mirrors chip_top.dn_data_pad())
  function automatic int dn_data_pad(input int bit_idx);
    case (bit_idx)
      0: dn_data_pad = 0;   1: dn_data_pad = 1;   2: dn_data_pad = 2;
      3: dn_data_pad = 3;   4: dn_data_pad = 4;   5: dn_data_pad = 5;
      6: dn_data_pad = 6;   7: dn_data_pad = 7;
      8: dn_data_pad = 37;  9: dn_data_pad = 36;
      10: dn_data_pad = 39; 11: dn_data_pad = 38;
      12: dn_data_pad = 41; 13: dn_data_pad = 40;
      14: dn_data_pad = 43; 15: dn_data_pad = 42;
      default: dn_data_pad = 0;
    endcase
  endfunction

  function automatic int up_data_pad(input int bit_idx);
    case (bit_idx)
      0: up_data_pad = 22;  1: up_data_pad = 23;
      2: up_data_pad = 20;  3: up_data_pad = 21;
      4: up_data_pad = 18;  5: up_data_pad = 19;
      6: up_data_pad = 16;  7: up_data_pad = 17;
      8: up_data_pad = 28;  9: up_data_pad = 29;
      10: up_data_pad = 30; 11: up_data_pad = 31;
      12: up_data_pad = 32; 13: up_data_pad = 33;
      14: up_data_pad = 34; 15: up_data_pad = 35;
      default: up_data_pad = 28;
    endcase
  endfunction

  always_comb begin
    pad_drv = '0;
    pad_oe  = '0;

    // Drive core_clk + hard_reset onto the chip-input pads. force_rst_en
    // overrides hard_reset (so tests can re-assert the chip-internal reset
    // sequencer mid-run through the actual PAD path).
    pad_drv[44] = kz(clk);
    pad_drv[45] = kz(vif.force_rst_en ? vif.force_rst_val : hard_reset);
    pad_oe[44]  = tb_pad_drive_en;
    pad_oe[45]  = tb_pad_drive_en;

    // EP upstream -> chip downstream pads.
    pad_drv[8] = kz(ep_up_clk_r);
    pad_drv[9] = kz(ep_up_valid_r);
    pad_oe[8]  = tb_pad_drive_en;
    pad_oe[9]  = tb_pad_drive_en;
    for (int i = 0; i < CW; i++) begin
      pad_drv[dn_data_pad(i)] = kz(ep_up_data_r[i]);
      pad_oe[dn_data_pad(i)]  = tb_pad_drive_en;
    end

    // Chip TX-side credit return -> EP upstream.
    pad_drv[12] = kz(ep_dn_token_r);
    pad_oe[12]  = tb_pad_drive_en;

    // Tie off DFT scan inputs.
    pad_drv[11] = 1'b0;
    pad_drv[46] = 1'b0;
    pad_oe[11]  = tb_pad_drive_en;
    pad_oe[46]  = tb_pad_drive_en;
  end

  // Chip upstream outputs -> EP downstream inputs.
  wire          dut_up_clk_r   = PAD[15];
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
  // DUT
  // --------------------------------------------------------------------------
  chip_top u_dut (
      .PAD   (PAD),
      .VDDPST(1'b1),
      .VSSPST(1'b0),
      .VDD   (1'b1),
      .VSS   (1'b0)
  );

  // --------------------------------------------------------------------------
  // TB-side bsg_link DDR (mirrors tb_chip_top.sv). Converts flits to the
  // 16-bit DDR pin protocol back-to-back with the chip's bsg_link_wrapper.
  // --------------------------------------------------------------------------
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
      .core_clk_i         (clk),
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
      .core_clk_i       (clk),
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

  // --------------------------------------------------------------------------
  // FPGA-side axi_link_rx (decodes chip's outgoing flits)
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
      .reset_i(rst_i),
      .link_rx_v_i   (ep_link_rx_valid),
      .link_rx_data_i(ep_link_rx_data),
      .link_rx_yumi_o(ep_link_rx_yumi),
      .awvalid_o(ep_rx_awvalid),  .awready_i(1'b1),
      .awaddr_o (ep_rx_awaddr),   .awlen_o  (ep_rx_awlen),
      .awsize_o (),                .awburst_o(),
      .awid_o   (ep_rx_awid),
      .wvalid_o (ep_rx_wvalid),   .wready_i (1'b1),
      .wdata_o  (ep_rx_wdata),    .wlast_o  (ep_rx_wlast),
      .arvalid_o(ep_rx_arvalid),  .arready_i(ep_rx_arready),
      .araddr_o (ep_rx_araddr),   .arlen_o  (ep_rx_arlen),
      .arsize_o (),                .arburst_o(),
      .ar_is_burst_o(ep_rx_ar_is_burst),
      .arid_o   (ep_rx_arid),     .ar_tid_o (ep_rx_ar_tid),
      .ar_eblock_o(ep_rx_ar_eblock), .ar_regaddr_o(ep_rx_ar_regaddr),
      .rvalid_o(vif.ep_rx_rvalid),
      .rready_i(vif.ep_rx_rready),
      .rdata_o (vif.ep_rx_rdata),
      .rresp_o (vif.ep_rx_rresp),
      .rlast_o (vif.ep_rx_rlast),
      .rid_o   (vif.ep_rx_rid),
      .r_is_burst_o()
  );

  // --------------------------------------------------------------------------
  // FPGA-side packer (same as tb_top.sv)
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
  localparam logic [1:0] EP_OP_READ      = 2'b11;

  typedef enum logic [1:0] { EP_TX_IDLE, EP_TX_WR_DATA, EP_TX_R_DATA } ep_tx_state_e;
  ep_tx_state_e ep_tx_state_q, ep_tx_state_n;

  always_comb begin
    ep_link_tx_valid = 1'b0;
    ep_link_tx_data  = '0;
    ep_tx_awready    = 1'b0;
    ep_tx_wready     = 1'b0;
    ep_tx_rready     = 1'b0;
    ep_tx_arready    = 1'b0;
    ep_tx_state_n    = ep_tx_state_q;

    unique case (ep_tx_state_q)
      EP_TX_IDLE: begin
        if (ep_tx_rvalid) begin
          ep_link_tx_valid = 1'b1;
          ep_link_tx_data  = {EP_OP_READ_RESP, ep_tx_rid, ep_tx_r_is_burst,
                              3'b0, ep_tx_rlen, 16'b0};
          if (ep_link_tx_ready) ep_tx_state_n = EP_TX_R_DATA;
        end else if (ep_tx_awvalid) begin
          ep_link_tx_valid = 1'b1;
          ep_link_tx_data  = {EP_OP_WRITE, ep_tx_awid, 12'b0, ep_tx_awaddr};
          ep_tx_awready    = ep_link_tx_ready;
          if (ep_link_tx_ready) ep_tx_state_n = EP_TX_WR_DATA;
        end else if (ep_tx_arvalid) begin
          ep_link_tx_valid = 1'b1;
          ep_link_tx_data  = {EP_OP_READ, ep_tx_arid, 4'b0, 3'b0, 5'b0,
                              ep_tx_araddr};
          ep_tx_arready    = ep_link_tx_ready;
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
        if (ep_tx_rvalid && ep_link_tx_ready && ep_tx_rlast)
          ep_tx_state_n = EP_TX_IDLE;
      end
      default: ep_tx_state_n = EP_TX_IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst_i) ep_tx_state_q <= EP_TX_IDLE;
    else       ep_tx_state_q <= ep_tx_state_n;
  end

  // --------------------------------------------------------------------------
  // Wire TB-side ep_rx_* / ep_tx_* into the vif (same shape as tb_top.sv).
  // --------------------------------------------------------------------------
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

  assign ep_tx_awvalid    = vif.ep_tx_awvalid;
  assign vif.ep_tx_awready = ep_tx_awready;
  assign ep_tx_awaddr     = vif.ep_tx_awaddr;
  assign ep_tx_awid       = vif.ep_tx_awid;
  assign ep_tx_wvalid     = vif.ep_tx_wvalid;
  assign vif.ep_tx_wready = ep_tx_wready;
  assign ep_tx_wdata      = vif.ep_tx_wdata;
  assign ep_tx_arvalid    = vif.ep_tx_arvalid;
  assign vif.ep_tx_arready = ep_tx_arready;
  assign ep_tx_araddr     = vif.ep_tx_araddr;
  assign ep_tx_arid       = vif.ep_tx_arid;
  assign ep_tx_rvalid     = vif.ep_tx_rvalid;
  assign vif.ep_tx_rready = ep_tx_rready;
  assign ep_tx_rdata      = vif.ep_tx_rdata;
  assign ep_tx_rlast      = vif.ep_tx_rlast;
  assign ep_tx_rid        = vif.ep_tx_rid;
  assign ep_tx_r_is_burst = vif.ep_tx_r_is_burst;
  assign ep_tx_rlen       = vif.ep_tx_rlen;

  // The vif's link_rx/link_tx are nominally the chip-direct flit interface.
  // At chip-top level the chip is reached via bsg_link DDR — those signals
  // are internal, so leave them unconnected (the agents use ep_rx_*/ep_tx_*
  // anyway).
  initial begin
    vif.link_rx_data  = '0;
    vif.link_rx_valid = 1'b0;
  end

  // --------------------------------------------------------------------------
  // bsg_link bringup sequence (mirrors tb_chip_top.sv:bsg_link_bringup).
  //
  // Asserts every reset, then releases them in the staged order the
  // bsg_link DDR requires. The chip's own staged reset sequencer (counter
  // in chip_top.sv lines 178-204) handles the chip half of the link
  // automatically off hard_reset; this task handles the FPGA half plus
  // drives the chip's hard_reset PAD.
  //
  // Callable at t=0 (initial bringup, see initial block below) AND mid-run
  // from a UVM test that needs to recover from a mid-kernel reset
  // (e.g. mini_dice_chip_mid_reset_test). The task re-asserts all resets
  // before walking the staged release, so it's safe to invoke regardless
  // of the FPGA-side link's prior state.
  // --------------------------------------------------------------------------
  task automatic bsg_link_bringup();
    hard_reset                  = 1'b1;
    rst_i                       = 1'b1;
    ep_upstream_io_link_reset   = 1'b1;
    ep_downstream_io_link_reset = 1'b1;
    ep_async_token_reset        = 1'b0;

    // 1) Pulse FPGA TX async_token_reset while the FPGA TX I/O link is in reset.
    repeat (8) @(posedge clk);
    @(posedge clk); #1;
    ep_async_token_reset = 1'b1;
    repeat (2) @(posedge clk); #1;
    ep_async_token_reset = 1'b0;

    // 2) Release FPGA TX I/O reset.
    repeat (8) @(posedge dn_io_clk);
    @(posedge clk); #1;
    ep_upstream_io_link_reset = 1'b0;

    // 3) Release chip hard reset.
    @(posedge clk); @(negedge clk);
    hard_reset = 1'b0;
    repeat (64) @(posedge clk);

    // 4) Release FPGA-side downstream IO reset.
    @(posedge clk); #1ns;
    ep_downstream_io_link_reset = 1'b0;
    repeat (8) @(posedge clk);

    // 5) Release FPGA core-side reset last (this also releases vif.rst_i).
    #1;
    rst_i = 1'b0;
    repeat (4) @(posedge clk);
  endtask

  // Initial bringup at t=0.
  initial begin
    hard_reset                  = 1'b1;
    rst_i                       = 1'b1;
    ep_upstream_io_link_reset   = 1'b1;
    ep_downstream_io_link_reset = 1'b1;
    ep_async_token_reset        = 1'b0;
    tb_pad_drive_en             = 1'b0;
    vif.force_bringup           = 1'b0;

    #(1ns);
    tb_pad_drive_en = 1'b1;

    bsg_link_bringup();
    `uvm_info("TB_CHIP", "bsg_link bringup complete; rst_i deasserted", UVM_LOW)
  end

  // Mid-run bringup trigger. UVM tests pulse vif.force_bringup to request
  // a re-bringup (e.g. mid_reset_test). The watcher runs the full task
  // and clears the flag when done; tests block on `wait(!vif.force_bringup)`.
  initial forever begin
    @(posedge vif.force_bringup);
    `uvm_info("TB_CHIP", "vif.force_bringup pulsed; re-running bsg_link_bringup()", UVM_LOW)
    bsg_link_bringup();
    vif.force_bringup = 1'b0;
    `uvm_info("TB_CHIP", "mid-run bsg_link bringup complete", UVM_LOW)
  end

  // --------------------------------------------------------------------------
  // UVM entry
  // --------------------------------------------------------------------------
  // Set a UVM config-db flag the tests can read to detect chip mode.
  initial uvm_config_db #(int)::set(null, "*", "CHIP_MODE", 1);

  initial begin
    if ($test$plusargs("DISABLE_AXI_ASSERTS")) begin
      $assertoff(0);
      $display("[TB] $assertoff(0) per +DISABLE_AXI_ASSERTS");
    end
    uvm_config_db #(virtual mini_dice_chip_vif)::set(null, "*", "vif", vif);
    run_test();
  end

`ifdef DUMP_VCD
  initial begin
    $dumpfile("tb_chip.vcd");
    $dumpvars(0, tb_chip);
  end
`endif

endmodule
