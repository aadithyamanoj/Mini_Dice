`timescale 1ns/1ps
`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module tb_top;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import axi4_xbar_pkg::*;
  import dice_pkg::*;

  // -------------------------------------------------------------------------
  // Clock / reset  (active-high reset)
  // -------------------------------------------------------------------------
  localparam int CLK_PERIOD_NS = 10;
  logic clk, rst;

  initial clk = 0;
  always #(CLK_PERIOD_NS/2) clk = ~clk;

  initial begin
    rst = 1;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 0;
  end

  // -------------------------------------------------------------------------
  // Virtual interface
  // -------------------------------------------------------------------------
  dice_core_vif vif (.clk(clk), .rst(rst));

  // -------------------------------------------------------------------------
  // cta_if instance  (existing SV interface used by dice_core)
  // -------------------------------------------------------------------------
  cta_if cta_if_inst ();

  // Bridge vif CTA signals ↔ cta_if_inst
  // TB acts as the CTA master: drives dispatch, accepts complete
  assign cta_if_inst.dispatch_valid = vif.cta_dispatch_valid;
  assign cta_if_inst.dispatch_data  = vif.cta_dispatch_data;
  assign vif.cta_dispatch_ready     = cta_if_inst.dispatch_ready;
  assign vif.cta_complete_valid     = cta_if_inst.complete_valid;
  assign cta_if_inst.complete_ready = vif.cta_complete_ready;

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  dice_core u_dut (
    .clk_i            (clk),
    .rst_i            (rst),

    .cta_if_inst      (cta_if_inst),

    .mfetch_req_o     (vif.mfetch_req),
    .mfetch_resp_i    (vif.mfetch_resp),
    .bsfetch_req_o    (vif.bsfetch_req),
    .bsfetch_resp_i   (vif.bsfetch_resp),

    .csrX0_i          (vif.csrX[0]),
    .csrX1_i          (vif.csrX[1]),
    .csrX2_i          (vif.csrX[2]),
    .csrX3_i          (vif.csrX[3]),
    .csrX4_i          (vif.csrX[4]),
    .csrX5_i          (vif.csrX[5]),
    .csrX6_i          (vif.csrX[6]),
    .csrX7_i          (vif.csrX[7]),

    .cgra_prog_dout_o (vif.cgra_prog_dout),
    .cgra_prog_we_o   (vif.cgra_prog_we),

    .axi_awaddr_o     (vif.axi_awaddr),
    .axi_awvalid_o    (vif.axi_awvalid),
    .axi_awready_i    (vif.axi_awready),
    .axi_wdata_o      (vif.axi_wdata),
    .axi_wstrb_o      (vif.axi_wstrb),
    .axi_wvalid_o     (vif.axi_wvalid),
    .axi_wready_i     (vif.axi_wready),
    .axi_bresp_i      (vif.axi_bresp),
    .axi_bvalid_i     (vif.axi_bvalid),
    .axi_bready_o     (vif.axi_bready),
    .axi_araddr_o     (vif.axi_araddr),
    .axi_arvalid_o    (vif.axi_arvalid),
    .axi_arready_i    (vif.axi_arready),
    .axi_rdata_i      (vif.axi_rdata),
    .axi_rresp_i      (vif.axi_rresp),
    .axi_rvalid_i     (vif.axi_rvalid),
    .axi_rready_o     (vif.axi_rready)
  );

  // -------------------------------------------------------------------------
  // Safe tie-offs — overridden by agents once they start
  // -------------------------------------------------------------------------
  initial begin
    vif.mfetch_resp          = '0;
    vif.bsfetch_resp         = '0;
    vif.csrX                 = '{default: '0};
    // AXI-Lite slave: always ready, never sending data until axil_agent takes over
    vif.axi_awready          = 1'b1;
    vif.axi_wready           = 1'b1;
    vif.axi_bresp            = 2'b00;
    vif.axi_bvalid           = 1'b0;
    vif.axi_arready          = 1'b1;
    vif.axi_rdata            = '0;
    vif.axi_rresp            = 2'b00;
    vif.axi_rvalid           = 1'b0;
    // CTA: no dispatch yet
    vif.cta_dispatch_valid   = 1'b0;
    vif.cta_dispatch_data    = '0;
    vif.cta_complete_ready   = 1'b1;
  end

  // -------------------------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------------------------
  initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb_top);
  end

  // -------------------------------------------------------------------------
  // UVM config DB + test launch
  // -------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual dice_core_vif)::set(null, "uvm_test_top.*", "vif", vif);
    run_test();
  end

endmodule
