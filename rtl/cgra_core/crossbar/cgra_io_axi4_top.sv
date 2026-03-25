// =============================================================================
// cgra_io_axi4_top.sv
//
// Integration wrapper: IO adapter + flit bridge → full AXI4 crossbar.
//
// Replaces cgra_io_mem_top (which used AXI-Lite + cgra_mem_system_16bit) with
// the new axi4_full_crossbar.  The existing io_rx_tx_adapter and
// flit_axil_bridge are reused unchanged; their AXI-Lite outputs are promoted
// to full AXI4 (single-beat, INCR) at the crossbar slave ports.
//
// Data flow
// ---------
//   CGRA link words ──► io_rx_tx_adapter ──► flit_axil_bridge
//                                                  │ AXI-Lite master
//                                                  ▼
//                                         [AXI-Lite → AXI4 promotion]
//                                                  │ slv_req_t (dfetch port)
//                                                  ▼
//                                        axi4_full_crossbar  ──► fpga_mem_req_o
//                                                            ──► cgra_csr_req_o
//                                                  ▲
//   FPGA AXI-Lite flat pins ──[AXI-Lite → AXI4]──► (fpga_mst port)
//
// Slave ports (fpga_mem and cgra_csr) are exposed as AXI4 struct ports so
// the testbench (or synthesis wrapper) can connect behavioral / RTL slaves.
//
// Constraints inherited from cgra_io_mem_top
// -------------------------------------------
//   * Single 16-bit physical link: all CGRA traffic serialises through one
//     adapter.  mfetch and bsfetch crossbar ports are tied idle.
//   * FLIT_WIDTH == LINK_WIDTH == DATA_WIDTH == 16 b.
// =============================================================================

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module cgra_io_axi4_top
  import axi4_xbar_pkg::*;
  import axi_pkg::*;
#(
    parameter int ADDR_WIDTH    = 16,
    parameter int DATA_WIDTH    = 16,
    parameter int FLIT_WIDTH    = 16,
    parameter int LINK_WIDTH    = 16,
    parameter int RX_FIFO_ELS   = 16,
    parameter int TX_FIFO_ELS   = 16
)(
    input  logic clk_i,
    input  logic rst_i,   // active-high

    // --------------------------------------------------------------------------
    // CGRA link interface  (same pinout as cgra_io_mem_top)
    // --------------------------------------------------------------------------
    input  logic                  link_rx_v_i,
    input  logic [LINK_WIDTH-1:0] link_rx_data_i,
    output logic                  link_rx_ready_o,

    output logic                  link_tx_v_o,
    output logic [LINK_WIDTH-1:0] link_tx_data_o,
    input  logic                  link_tx_ready_i,

    // --------------------------------------------------------------------------
    // FPGA AXI-Lite master  (flat pins, same pinout as cgra_io_mem_top)
    // --------------------------------------------------------------------------
    input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_aw_addr,
    input  logic [2:0]                fpga_axi_i_aw_prot,
    input  logic                      fpga_axi_i_aw_valid,
    output logic                      fpga_axi_i_aw_ready,

    input  logic [DATA_WIDTH-1:0]     fpga_axi_i_w_data,
    input  logic [(DATA_WIDTH/8)-1:0] fpga_axi_i_w_strb,
    input  logic                      fpga_axi_i_w_valid,
    output logic                      fpga_axi_i_w_ready,

    output logic [1:0]                fpga_axi_i_b_resp,
    output logic                      fpga_axi_i_b_valid,
    input  logic                      fpga_axi_i_b_ready,

    input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_ar_addr,
    input  logic [2:0]                fpga_axi_i_ar_prot,
    input  logic                      fpga_axi_i_ar_valid,
    output logic                      fpga_axi_i_ar_ready,

    output logic [DATA_WIDTH-1:0]     fpga_axi_i_r_data,
    output logic [1:0]                fpga_axi_i_r_resp,
    output logic                      fpga_axi_i_r_valid,
    input  logic                      fpga_axi_i_r_ready,

    // --------------------------------------------------------------------------
    // AXI4 slave ports  (connect to external behavioral or RTL slaves)
    // --------------------------------------------------------------------------
    output mst_req_t  fpga_mem_req_o,    // [0] FPGA SRAM  0x0800–0x0FFF
    input  mst_resp_t fpga_mem_resp_i,

    output mst_req_t  cgra_csr_req_o,    // [1] CGRA CSRs  0x0000–0x00FF
    input  mst_resp_t cgra_csr_resp_i
);

  // --------------------------------------------------------------------------
  // Internal PHY wires  (io_rx_tx_adapter ↔ flit_axil_bridge)
  // --------------------------------------------------------------------------
  logic                  phy_rx_v,    phy_tx_v;
  logic [FLIT_WIDTH-1:0] phy_rx_data, phy_tx_data;
  logic                  phy_rx_ready, phy_tx_ready;

  // --------------------------------------------------------------------------
  // Flat AXI-Lite wires from flit_axil_bridge master outputs
  // --------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0]         fab_awaddr;
  logic [2:0]                    fab_awprot;
  logic                          fab_awvalid;
  logic [DATA_WIDTH-1:0]         fab_wdata;
  logic [(DATA_WIDTH/8)-1:0]     fab_wstrb;
  logic                          fab_wvalid;
  logic                          fab_bready;
  logic [ADDR_WIDTH-1:0]         fab_araddr;
  logic [2:0]                    fab_arprot;
  logic                          fab_arvalid;
  logic                          fab_rready;

  // AXI-Lite slave-direction feedback to flit_axil_bridge
  logic                          fab_awready, fab_wready;
  logic [1:0]                    fab_bresp;
  logic                          fab_bvalid;
  logic                          fab_arready;
  logic [DATA_WIDTH-1:0]         fab_rdata;
  logic [1:0]                    fab_rresp;
  logic                          fab_rvalid;

  // --------------------------------------------------------------------------
  // Crossbar request/response structs
  // --------------------------------------------------------------------------
  slv_req_t  fpga_mst_req,  dfetch_req;
  slv_resp_t fpga_mst_resp, dfetch_resp;
  slv_req_t  mfetch_req,    bsfetch_req;
  slv_resp_t mfetch_resp,   bsfetch_resp;  // outputs ignored (idle)

  // --------------------------------------------------------------------------
  // Promote flat FPGA AXI-Lite pins → slv_req_t  (single-beat AXI4)
  // --------------------------------------------------------------------------
  always_comb begin
    fpga_mst_req           = '0;

    // AW
    fpga_mst_req.aw_valid  = fpga_axi_i_aw_valid;
    fpga_mst_req.aw.addr   = axi_addr_t'(fpga_axi_i_aw_addr);
    fpga_mst_req.aw.prot   = fpga_axi_i_aw_prot;
    fpga_mst_req.aw.len    = '0;
    fpga_mst_req.aw.size   = 3'b001;   // 2 bytes
    fpga_mst_req.aw.burst  = BURST_INCR;

    // W
    fpga_mst_req.w_valid   = fpga_axi_i_w_valid;
    fpga_mst_req.w.data    = axi_data_t'(fpga_axi_i_w_data);
    fpga_mst_req.w.strb    = axi_strb_t'(fpga_axi_i_w_strb);
    fpga_mst_req.w.last    = 1'b1;

    // B
    fpga_mst_req.b_ready   = fpga_axi_i_b_ready;

    // AR
    fpga_mst_req.ar_valid  = fpga_axi_i_ar_valid;
    fpga_mst_req.ar.addr   = axi_addr_t'(fpga_axi_i_ar_addr);
    fpga_mst_req.ar.prot   = fpga_axi_i_ar_prot;
    fpga_mst_req.ar.len    = '0;
    fpga_mst_req.ar.size   = 3'b001;
    fpga_mst_req.ar.burst  = BURST_INCR;

    // R
    fpga_mst_req.r_ready   = fpga_axi_i_r_ready;
  end

  assign fpga_axi_i_aw_ready = fpga_mst_resp.aw_ready;
  assign fpga_axi_i_w_ready  = fpga_mst_resp.w_ready;
  assign fpga_axi_i_b_resp   = fpga_mst_resp.b.resp;
  assign fpga_axi_i_b_valid  = fpga_mst_resp.b_valid;
  assign fpga_axi_i_ar_ready = fpga_mst_resp.ar_ready;
  assign fpga_axi_i_r_data   = DATA_WIDTH'(fpga_mst_resp.r.data);
  assign fpga_axi_i_r_resp   = fpga_mst_resp.r.resp;
  assign fpga_axi_i_r_valid  = fpga_mst_resp.r_valid;

  // --------------------------------------------------------------------------
  // Promote flit_axil_bridge AXI-Lite outputs → slv_req_t (dfetch port)
  // --------------------------------------------------------------------------
  always_comb begin
    dfetch_req           = '0;

    dfetch_req.aw_valid  = fab_awvalid;
    dfetch_req.aw.addr   = axi_addr_t'(fab_awaddr);
    dfetch_req.aw.prot   = fab_awprot;
    dfetch_req.aw.len    = '0;
    dfetch_req.aw.size   = 3'b001;
    dfetch_req.aw.burst  = BURST_INCR;

    dfetch_req.w_valid   = fab_wvalid;
    dfetch_req.w.data    = axi_data_t'(fab_wdata);
    dfetch_req.w.strb    = axi_strb_t'(fab_wstrb);
    dfetch_req.w.last    = 1'b1;

    dfetch_req.b_ready   = fab_bready;

    dfetch_req.ar_valid  = fab_arvalid;
    dfetch_req.ar.addr   = axi_addr_t'(fab_araddr);
    dfetch_req.ar.prot   = fab_arprot;
    dfetch_req.ar.len    = '0;
    dfetch_req.ar.size   = 3'b001;
    dfetch_req.ar.burst  = BURST_INCR;

    dfetch_req.r_ready   = fab_rready;
  end

  assign fab_awready = dfetch_resp.aw_ready;
  assign fab_wready  = dfetch_resp.w_ready;
  assign fab_bresp   = dfetch_resp.b.resp;
  assign fab_bvalid  = dfetch_resp.b_valid;
  assign fab_arready = dfetch_resp.ar_ready;
  assign fab_rdata   = DATA_WIDTH'(dfetch_resp.r.data);
  assign fab_rresp   = dfetch_resp.r.resp;
  assign fab_rvalid  = dfetch_resp.r_valid;

  // --------------------------------------------------------------------------
  // Idle masters (mfetch, bsfetch) – no physical link allocated
  // --------------------------------------------------------------------------
  always_comb begin
    mfetch_req          = '0;
    mfetch_req.b_ready  = 1'b1;
    mfetch_req.r_ready  = 1'b1;
    bsfetch_req         = '0;
    bsfetch_req.b_ready = 1'b1;
    bsfetch_req.r_ready = 1'b1;
  end

  // --------------------------------------------------------------------------
  // io_rx_tx_adapter  (link ↔ flit converter, same as cgra_io_mem_top)
  // --------------------------------------------------------------------------
  io_rx_tx_adapter #(
    .flit_width_p      ( FLIT_WIDTH   ),
    .link_word_width_p ( LINK_WIDTH   ),
    .rx_fifo_els_p     ( RX_FIFO_ELS  ),
    .tx_fifo_els_p     ( TX_FIFO_ELS  )
  ) u_io_adapter (
    .clk_i           ( clk_i           ),
    .reset_i         ( rst_i           ),
    .link_rx_v_i     ( link_rx_v_i     ),
    .link_rx_data_i  ( link_rx_data_i  ),
    .link_rx_ready_o ( link_rx_ready_o ),
    .link_tx_v_o     ( link_tx_v_o     ),
    .link_tx_data_o  ( link_tx_data_o  ),
    .link_tx_ready_i ( link_tx_ready_i ),
    .phy_rx_v_o      ( phy_rx_v        ),
    .phy_rx_data_o   ( phy_rx_data     ),
    .phy_rx_ready_i  ( phy_rx_ready    ),
    .phy_tx_v_i      ( phy_tx_v        ),
    .phy_tx_data_i   ( phy_tx_data     ),
    .phy_tx_ready_o  ( phy_tx_ready    )
  );

  // --------------------------------------------------------------------------
  // flit_axil_bridge  (LEN-framed flit ↔ AXI-Lite, same as cgra_io_mem_top)
  // --------------------------------------------------------------------------
  flit_axil_bridge #(
    .flit_width_p      ( FLIT_WIDTH  ),
    .axil_addr_width_p ( ADDR_WIDTH  ),
    .axil_data_width_p ( DATA_WIDTH  )
  ) u_bridge (
    .clk_i              ( clk_i       ),
    .rst_i              ( rst_i       ),

    .phy_rx_v_i         ( phy_rx_v    ),
    .phy_rx_data_i      ( phy_rx_data ),
    .phy_rx_ready_o     ( phy_rx_ready),

    .phy_tx_v_o         ( phy_tx_v    ),
    .phy_tx_data_o      ( phy_tx_data ),
    .phy_tx_ready_i     ( phy_tx_ready),

    .m_axil_awaddr_o    ( fab_awaddr  ),
    .m_axil_awprot_o    ( fab_awprot  ),
    .m_axil_awvalid_o   ( fab_awvalid ),
    .m_axil_awready_i   ( fab_awready ),

    .m_axil_wdata_o     ( fab_wdata   ),
    .m_axil_wstrb_o     ( fab_wstrb   ),
    .m_axil_wvalid_o    ( fab_wvalid  ),
    .m_axil_wready_i    ( fab_wready  ),

    .m_axil_bresp_i     ( fab_bresp   ),
    .m_axil_bvalid_i    ( fab_bvalid  ),
    .m_axil_bready_o    ( fab_bready  ),

    .m_axil_araddr_o    ( fab_araddr  ),
    .m_axil_arprot_o    ( fab_arprot  ),
    .m_axil_arvalid_o   ( fab_arvalid ),
    .m_axil_arready_i   ( fab_arready ),

    .m_axil_rdata_i     ( fab_rdata   ),
    .m_axil_rresp_i     ( fab_rresp   ),
    .m_axil_rvalid_i    ( fab_rvalid  ),
    .m_axil_rready_o    ( fab_rready  )
  );

  // --------------------------------------------------------------------------
  // Full AXI4 crossbar
  // --------------------------------------------------------------------------
  axi4_full_crossbar u_xbar (
    .clk_i           ( clk_i          ),
    .rst_i           ( rst_i          ),
    .test_i          ( 1'b0           ),

    .fpga_mst_req_i  ( fpga_mst_req   ),
    .fpga_mst_resp_o ( fpga_mst_resp  ),

    .dfetch_req_i    ( dfetch_req     ),
    .dfetch_resp_o   ( dfetch_resp    ),

    .mfetch_req_i    ( mfetch_req     ),
    .mfetch_resp_o   ( mfetch_resp    ),

    .bsfetch_req_i   ( bsfetch_req    ),
    .bsfetch_resp_o  ( bsfetch_resp   ),

    .fpga_mem_req_o  ( fpga_mem_req_o  ),
    .fpga_mem_resp_i ( fpga_mem_resp_i ),

    .cgra_csr_req_o  ( cgra_csr_req_o  ),
    .cgra_csr_resp_i ( cgra_csr_resp_i )
  );

endmodule : cgra_io_axi4_top
