// =============================================================================
// cgra_io_axi4_burst_top.sv
//
// Duplicate of cgra_io_axi4_top for standalone burst development.
// Instantiates flit_axi4_bridge (local copy) instead of flit_axil_bridge
// so burst changes can be made here without touching the original io/ tree.
//
// No functional changes from cgra_io_axi4_top — this is the starting point.
// =============================================================================

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module cgra_io_axi4_burst_top
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
    input  logic rst_i,

    // CGRA link interface
    input  logic                  link_rx_v_i,
    input  logic [LINK_WIDTH-1:0] link_rx_data_i,
    output logic                  link_rx_ready_o,

    output logic                  link_tx_v_o,
    output logic [LINK_WIDTH-1:0] link_tx_data_o,
    input  logic                  link_tx_ready_i,

    // FPGA AXI-Lite master (flat pins)
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

    // AXI4 slave ports (connect to external behavioral or RTL slaves)
    output mst_req_t  fpga_mem_req_o,
    input  mst_resp_t fpga_mem_resp_i,

    output mst_req_t  cgra_csr_req_o,
    input  mst_resp_t cgra_csr_resp_i
);

  // Internal PHY wires
  logic                  phy_rx_v,    phy_tx_v;
  logic [FLIT_WIDTH-1:0] phy_rx_data, phy_tx_data;
  logic                  phy_rx_ready, phy_tx_ready;

  // AXI4 wires from flit_axi4_bridge outputs
  logic [ADDR_WIDTH-1:0]         fab_awaddr;
  logic [7:0]                    fab_awlen;
  logic [2:0]                    fab_awprot;
  logic                          fab_awvalid;
  logic [DATA_WIDTH-1:0]         fab_wdata;
  logic [(DATA_WIDTH/8)-1:0]     fab_wstrb;
  logic                          fab_wlast;
  logic                          fab_wvalid;
  logic                          fab_bready;
  logic [ADDR_WIDTH-1:0]         fab_araddr;
  logic [7:0]                    fab_arlen;
  logic [2:0]                    fab_arprot;
  logic                          fab_arvalid;
  logic                          fab_rready;

  logic                          fab_awready, fab_wready;
  logic [1:0]                    fab_bresp;
  logic                          fab_bvalid;
  logic                          fab_arready;
  logic [DATA_WIDTH-1:0]         fab_rdata;
  logic [1:0]                    fab_rresp;
  logic                          fab_rlast;
  logic                          fab_rvalid;

  // Crossbar request/response structs
  slv_req_t  fpga_mst_req,  dfetch_req;
  slv_resp_t fpga_mst_resp, dfetch_resp;
  slv_req_t  mfetch_req,    bsfetch_req;
  slv_resp_t mfetch_resp,   bsfetch_resp;

  // FPGA flat AXI-Lite → slv_req_t
  always_comb begin
    fpga_mst_req           = '0;
    fpga_mst_req.aw_valid  = fpga_axi_i_aw_valid;
    fpga_mst_req.aw.addr   = axi_addr_t'(fpga_axi_i_aw_addr);
    fpga_mst_req.aw.prot   = fpga_axi_i_aw_prot;
    fpga_mst_req.aw.len    = '0;
    fpga_mst_req.aw.size   = 3'b001;
    fpga_mst_req.aw.burst  = BURST_INCR;
    fpga_mst_req.w_valid   = fpga_axi_i_w_valid;
    fpga_mst_req.w.data    = axi_data_t'(fpga_axi_i_w_data);
    fpga_mst_req.w.strb    = axi_strb_t'(fpga_axi_i_w_strb);
    fpga_mst_req.w.last    = 1'b1;
    fpga_mst_req.b_ready   = fpga_axi_i_b_ready;
    fpga_mst_req.ar_valid  = fpga_axi_i_ar_valid;
    fpga_mst_req.ar.addr   = axi_addr_t'(fpga_axi_i_ar_addr);
    fpga_mst_req.ar.prot   = fpga_axi_i_ar_prot;
    fpga_mst_req.ar.len    = '0;
    fpga_mst_req.ar.size   = 3'b001;
    fpga_mst_req.ar.burst  = BURST_INCR;
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

  // flit_axi4_bridge outputs → slv_req_t (dfetch port)
  always_comb begin
    dfetch_req           = '0;
    dfetch_req.aw_valid  = fab_awvalid;
    dfetch_req.aw.addr   = axi_addr_t'(fab_awaddr);
    dfetch_req.aw.len    = fab_awlen;       // burst length from bridge
    dfetch_req.aw.prot   = fab_awprot;
    dfetch_req.aw.size   = 3'b001;
    dfetch_req.aw.burst  = BURST_INCR;
    dfetch_req.w_valid   = fab_wvalid;
    dfetch_req.w.data    = axi_data_t'(fab_wdata);
    dfetch_req.w.strb    = axi_strb_t'(fab_wstrb);
    dfetch_req.w.last    = fab_wlast;       // wlast from bridge
    dfetch_req.b_ready   = fab_bready;
    dfetch_req.ar_valid  = fab_arvalid;
    dfetch_req.ar.addr   = axi_addr_t'(fab_araddr);
    dfetch_req.ar.len    = fab_arlen;       // burst length from bridge
    dfetch_req.ar.prot   = fab_arprot;
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
  assign fab_rlast   = dfetch_resp.r.last;  // RLAST back to bridge
  assign fab_rvalid  = dfetch_resp.r_valid;

  // Idle masters
  always_comb begin
    mfetch_req          = '0;
    mfetch_req.b_ready  = 1'b1;
    mfetch_req.r_ready  = 1'b1;
    bsfetch_req         = '0;
    bsfetch_req.b_ready = 1'b1;
    bsfetch_req.r_ready = 1'b1;
  end

  // io_rx_tx_adapter
  io_rx_tx_adapter #(
    .flit_width_p      ( FLIT_WIDTH  ),
    .link_word_width_p ( LINK_WIDTH  ),
    .rx_fifo_els_p     ( RX_FIFO_ELS ),
    .tx_fifo_els_p     ( TX_FIFO_ELS )
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

  // flit_axi4_bridge (local copy for burst development)
  flit_axi4_bridge #(
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
    .m_axi_awaddr_o   ( fab_awaddr  ),
    .m_axi_awlen_o    ( fab_awlen   ),
    .m_axi_awprot_o   ( fab_awprot  ),
    .m_axi_awvalid_o  ( fab_awvalid ),
    .m_axi_awready_i  ( fab_awready ),
    .m_axi_wdata_o    ( fab_wdata   ),
    .m_axi_wstrb_o    ( fab_wstrb   ),
    .m_axi_wlast_o    ( fab_wlast   ),
    .m_axi_wvalid_o   ( fab_wvalid  ),
    .m_axi_wready_i   ( fab_wready  ),
    .m_axi_bresp_i    ( fab_bresp   ),
    .m_axi_bvalid_i   ( fab_bvalid  ),
    .m_axi_bready_o   ( fab_bready  ),
    .m_axi_araddr_o   ( fab_araddr  ),
    .m_axi_arlen_o    ( fab_arlen   ),
    .m_axi_arprot_o   ( fab_arprot  ),
    .m_axi_arvalid_o  ( fab_arvalid ),
    .m_axi_arready_i  ( fab_arready ),
    .m_axi_rdata_i    ( fab_rdata   ),
    .m_axi_rresp_i    ( fab_rresp   ),
    .m_axi_rlast_i    ( fab_rlast   ),
    .m_axi_rvalid_i   ( fab_rvalid  ),
    .m_axi_rready_o   ( fab_rready  )
  );

  // Full AXI4 crossbar
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

endmodule : cgra_io_axi4_burst_top
