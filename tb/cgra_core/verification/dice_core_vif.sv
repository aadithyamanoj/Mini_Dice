`timescale 1ns/1ps
`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

// Virtual interface wrapping all dice_core ports.
// Passed through uvm_config_db to every agent.
interface dice_core_vif
  import axi4_xbar_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;          // NUM_MEM_PORTS
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
  // AXI-Lite master (LDST FIFO → crossbar).
  // Per-port AW/W/B/AR (NUM_MEM_PORTS = 4); SHARED R channel uses ARUSER
  // tagging to identify which port each rdata response belongs to.
  // -------------------------------------------------------------------------
  logic [NUM_MEM_PORTS-1:0][15:0]                 axi_awaddr;
  logic [NUM_MEM_PORTS-1:0]                       axi_awvalid;
  logic [NUM_MEM_PORTS-1:0]                       axi_awready;   // TB drives
  logic [NUM_MEM_PORTS-1:0][15:0]                 axi_wdata;
  logic [NUM_MEM_PORTS-1:0][1:0]                  axi_wstrb;
  logic [NUM_MEM_PORTS-1:0]                       axi_wvalid;
  logic [NUM_MEM_PORTS-1:0]                       axi_wready;    // TB drives
  logic [NUM_MEM_PORTS-1:0][1:0]                  axi_bresp;     // TB drives
  logic [NUM_MEM_PORTS-1:0]                       axi_bvalid;    // TB drives
  logic [NUM_MEM_PORTS-1:0]                       axi_bready;
  logic [NUM_MEM_PORTS-1:0][15:0]                 axi_araddr;
  logic [NUM_MEM_PORTS-1:0][AxiUserWidth-1:0]     axi_aruser;
  logic [NUM_MEM_PORTS-1:0]                       axi_arvalid;
  logic [NUM_MEM_PORTS-1:0]                       axi_arready;   // TB drives

  // Shared R channel (single port — see ARUSER for routing)
  logic [AxiDataWidth-1:0]                        axi_rdata;     // TB drives
  logic [1:0]                                     axi_rresp;     // TB drives
  logic                                           axi_rvalid;    // TB drives
  logic                                           axi_rready;

endinterface
