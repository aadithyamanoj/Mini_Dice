`timescale 1ns/1ps
`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

// Virtual interface wrapping all dice_core ports.
// Passed through uvm_config_db to every agent.
interface dice_core_vif
  import axi4_xbar_pkg::*;
  import dice_pkg::*;
(
  input logic clk,
  input logic rst
);

  // -------------------------------------------------------------------------
  // CTA dispatch / complete channel
  // -------------------------------------------------------------------------
  logic           cta_dispatch_valid;
  dice_cta_desc_t cta_dispatch_data;
  logic           cta_dispatch_ready;   // driven by DUT
  logic           cta_complete_valid;   // driven by DUT
  logic           cta_complete_ready;

  // -------------------------------------------------------------------------
  // Instruction-fetch memory (AXI4 full, DUT is master)
  // -------------------------------------------------------------------------
  slv_req_t  mfetch_req;    // DUT drives
  slv_resp_t mfetch_resp;   // TB drives

  // -------------------------------------------------------------------------
  // Bitstream-fetch memory (AXI4 full, DUT is master)
  // -------------------------------------------------------------------------
  slv_req_t  bsfetch_req;   // DUT drives
  slv_resp_t bsfetch_resp;  // TB drives

  // -------------------------------------------------------------------------
  // CSR input sources
  // -------------------------------------------------------------------------
  logic [15:0] csrX [0:7];

  // -------------------------------------------------------------------------
  // CGRA scan-chain programming outputs (top-level)
  // -------------------------------------------------------------------------
  logic cgra_prog_dout;
  logic cgra_prog_we;

  // Internal probes: bits actually being shifted INTO the chain
  // (driven by hierarchical-reference assigns in tb_top)
  logic cgra_prog_din;
  logic cgra_prog_we_in;

  // -------------------------------------------------------------------------
  // AXI-Lite master (flat signals, LDST FIFO → crossbar)
  // -------------------------------------------------------------------------
  logic [15:0] axi_awaddr;
  logic        axi_awvalid;
  logic        axi_awready;   // TB drives
  logic [15:0] axi_wdata;
  logic [1:0]  axi_wstrb;
  logic        axi_wvalid;
  logic        axi_wready;    // TB drives
  logic [1:0]  axi_bresp;     // TB drives
  logic        axi_bvalid;    // TB drives
  logic        axi_bready;
  logic [15:0] axi_araddr;
  logic        axi_arvalid;
  logic        axi_arready;   // TB drives
  logic [15:0] axi_rdata;     // TB drives
  logic [1:0]  axi_rresp;     // TB drives
  logic        axi_rvalid;    // TB drives
  logic        axi_rready;

endinterface
