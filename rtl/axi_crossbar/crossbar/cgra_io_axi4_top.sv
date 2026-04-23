// =============================================================================
// cgra_io_axi4_top.sv
//
// CGRA IO top-level integrating:
//   fpga_mst  : FPGA-originated AXI4 requests decoded from bsg_link RX
//   dfetch    : CGRA backend AXI4 port — driven directly by dice_core LDST FIFO
//   mfetch    : CGRA frontend metadata fetch (slv_req_t from dice_core)
//   bsfetch   : CGRA frontend bitstream fetch (slv_req_t from dice_core)
//
// Off-chip memory path (chip → FPGA SRAM → chip):
//   dice_core axi_* → [dfetch port] → crossbar → top_level_io TX → bsg_link_ddr_upstream → [DDR] → FPGA SRAM
//   FPGA SRAM → [DDR] → bsg_link_ddr_downstream → top_level_io RX → ID shim → crossbar → dice_core axi_*
//
// Physical DDR IO pins are exposed at the module boundary.  In simulation a
// second top_level_io instance (FPGA endpoint) is connected back-to-back.
// =============================================================================

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module cgra_io_axi4_top
  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;
#(
    parameter int ADDR_WIDTH    = 16,
    parameter int DATA_WIDTH    = 32,
    parameter int FLIT_WIDTH    = 32,
    parameter int CHANNEL_WIDTH = 8,
    parameter int ID_FIFO_DEPTH          = 4,
    // bsg_link DDR parameters
    parameter int LG_FIFO_DEPTH          = 6,  // bsg_link credit-FIFO depth (log2)
    parameter int LG_CREDIT_TO_TOKEN_DEC = 3,  // bsg_link token decimation (log2)
    parameter int BYPASS_TWOFER_FIFO     = 0,  // 1 = bypass twofer FIFO (use in sim)
    parameter int BYPASS_GEARBOX         = 1,  // bypass PISO/SIPO gearbox (piso_ratio=1, always bypassed)
    parameter int USE_HARDENED_FIFO      = 0   // 1 = use hardened FIFO cells
)(
    input  logic clk_i,
    input  logic rst_i,

    // Legacy FPGA AXI4 full master module IO is disabled.  FPGA-originated
    // traffic now enters through top_level_io RX below.
    // input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_aw_addr,
    // input  logic [2:0]                fpga_axi_i_aw_prot,
    // input  logic                      fpga_axi_i_aw_valid,
    // output logic                      fpga_axi_i_aw_ready,
    //
    // input  logic [DATA_WIDTH-1:0]     fpga_axi_i_w_data,
    // input  logic [(DATA_WIDTH/8)-1:0] fpga_axi_i_w_strb,
    // input  logic                      fpga_axi_i_w_valid,
    // output logic                      fpga_axi_i_w_ready,
    //
    // output logic [1:0]                fpga_axi_i_b_resp,
    // output logic                      fpga_axi_i_b_valid,
    // input  logic                      fpga_axi_i_b_ready,
    //
    // input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_ar_addr,
    // input  logic [2:0]                fpga_axi_i_ar_prot,
    // input  logic                      fpga_axi_i_ar_valid,
    // output logic                      fpga_axi_i_ar_ready,
    //
    // output logic [DATA_WIDTH-1:0]     fpga_axi_i_r_data,
    // output logic [1:0]                fpga_axi_i_r_resp,
    // output logic                      fpga_axi_i_r_valid,
    // input  logic                      fpga_axi_i_r_ready,

    // mfetch / bsfetch AXI4 master ports (slv_req_t from dice_core)
    input  slv_req_t   mfetch_req_i,
    output slv_resp_t  mfetch_resp_o,
    input  slv_req_t   bsfetch_req_i,
    output slv_resp_t  bsfetch_resp_o,

    // dfetch AXI4 master (flat pins from dice_core LDST FIFO) — dfetch crossbar port
    input  logic [DATA_WIDTH-1:0]     dfetch_awaddr_i,
    input  logic                      dfetch_awvalid_i,
    output logic                      dfetch_awready_o,

    input  logic [DATA_WIDTH-1:0]     dfetch_wdata_i,
    input  logic [1:0]                dfetch_wstrb_i,
    input  logic                      dfetch_wvalid_i,
    output logic                      dfetch_wready_o,

    output logic [1:0]                dfetch_bresp_o,
    output logic                      dfetch_bvalid_o,
    input  logic                      dfetch_bready_i,

    input  logic [DATA_WIDTH-1:0]     dfetch_araddr_i,
    input  logic                      dfetch_arvalid_i,
    output logic                      dfetch_arready_o,

    output logic [DATA_WIDTH-1:0]     dfetch_rdata_o,
    output logic [1:0]                dfetch_rresp_o,
    output logic                      dfetch_rvalid_o,
    input  logic                      dfetch_rready_i,

    // bsg_link upstream (chip → FPGA SRAM): source-synchronous DDR
    input  logic        io_master_clk_i,            // IO master clock for upstream link
    input  logic        upstream_io_link_reset_i,   // IO-domain reset for upstream link
    input  logic        async_token_reset_i,         // Async token counter reset
    input  logic        token_clk_i,                // Token credit clock from FPGA downstream
    output logic                      upstream_io_clk_r_o,        // Forwarded clock to FPGA
    output logic [CHANNEL_WIDTH-1:0]  upstream_io_data_r_o,       // DDR data to FPGA
    output logic                      upstream_io_valid_r_o,      // DDR valid to FPGA

    // bsg_link downstream (FPGA SRAM → chip): source-synchronous DDR
    input  logic                      downstream_io_link_reset_i, // IO-domain reset for downstream link
    input  logic                      downstream_io_clk_i,        // Forwarded clock from FPGA
    input  logic [CHANNEL_WIDTH-1:0]  downstream_io_data_i,       // DDR data from FPGA
    input  logic                      downstream_io_valid_i,      // DDR valid from FPGA
    output logic        downstream_core_token_r_o,   // Token credit back to FPGA upstream

    // CSR slave port (on-chip)
    output mst_req_t  cgra_csr_req_o,
    input  mst_resp_t cgra_csr_resp_i
);

  // --------------------------------------------------------------------------
  // Crossbar request/response structs — dfetch driven directly from dfetch_* ports
  // --------------------------------------------------------------------------
  slv_req_t  fpga_mst_req,  dfetch_req;
  slv_resp_t fpga_mst_resp, dfetch_resp;
  slv_req_t  mfetch_req,    bsfetch_req;
  slv_resp_t mfetch_resp,   bsfetch_resp;

  // Crossbar fpga_mem slave port wires (internal — replaced by link modules)
  mst_req_t  xbar_mem_req;
  mst_resp_t xbar_mem_resp;

  // --------------------------------------------------------------------------
  // dice_core AXI4 dfetch_* → dfetch_req (single-beat promotion)
  // --------------------------------------------------------------------------
  always_comb begin
    dfetch_req           = '0;
    dfetch_req.aw_valid  = dfetch_awvalid_i;
    dfetch_req.aw.addr   = axi_addr_t'(dfetch_awaddr_i);
    dfetch_req.aw.len    = '0;
    dfetch_req.aw.size   = 3'b010;
    dfetch_req.aw.burst  = BURST_INCR;
    dfetch_req.w_valid   = dfetch_wvalid_i;
    dfetch_req.w.data    = axi_data_t'(dfetch_wdata_i);
    dfetch_req.w.strb    = axi_strb_t'(dfetch_wstrb_i);
    dfetch_req.w.last    = 1'b1;
    dfetch_req.b_ready   = dfetch_bready_i;
    dfetch_req.ar_valid  = dfetch_arvalid_i;
    dfetch_req.ar.addr   = axi_addr_t'(dfetch_araddr_i);
    dfetch_req.ar.len    = '0;
    dfetch_req.ar.size   = 3'b010;
    dfetch_req.ar.burst  = BURST_INCR;
    dfetch_req.r_ready   = dfetch_rready_i;
  end
  assign dfetch_awready_o = dfetch_resp.aw_ready;
  assign dfetch_wready_o  = dfetch_resp.w_ready;
  assign dfetch_bresp_o   = dfetch_resp.b.resp;
  assign dfetch_bvalid_o  = dfetch_resp.b_valid;
  assign dfetch_arready_o = dfetch_resp.ar_ready;
  assign dfetch_rdata_o   = DATA_WIDTH'(dfetch_resp.r.data);
  assign dfetch_rresp_o   = dfetch_resp.r.resp;
  assign dfetch_rvalid_o  = dfetch_resp.r_valid;

  assign mfetch_req    = mfetch_req_i;
  assign mfetch_resp_o = mfetch_resp;
  assign bsfetch_req   = bsfetch_req_i;
  assign bsfetch_resp_o = bsfetch_resp;

  // --------------------------------------------------------------------------
  // ID shim — axi_link_rx carries no IDs; capture crossbar-prepended IDs on
  // outgoing AR/AW and stamp them onto incoming R/B responses so the crossbar
  // can route responses back to the correct master port.
  // --------------------------------------------------------------------------
  logic        tx_awready, tx_wready, tx_arready;
  logic        tx_rready, tx_bready;

  logic        rx_awvalid, rx_awready;
  logic [ADDR_WIDTH-1:0] rx_awaddr;
  logic [7:0]  rx_awlen;
  logic [2:0]  rx_awsize;
  logic [1:0]  rx_awburst;

  logic        rx_wvalid, rx_wready;
  logic [DATA_WIDTH-1:0] rx_wdata;
  logic        rx_wlast;

  logic        rx_arvalid, rx_arready;
  logic [ADDR_WIDTH-1:0] rx_araddr;
  logic [7:0]  rx_arlen;
  logic [2:0]  rx_arsize;
  logic [1:0]  rx_arburst;

  logic        rx_rvalid, rx_rlast;
  logic [DATA_WIDTH-1:0] rx_rdata;
  logic [1:0]  rx_rresp;
  logic        rx_bvalid;
  logic [1:0]  rx_bresp;

  logic [MstIdWidth-1:0] ar_id_q_data, aw_id_q_data;
  logic                  ar_id_q_v,    aw_id_q_v;
  logic                  ar_id_q_yumi, aw_id_q_yumi;

  bsg_fifo_1r1w_small #(
    .width_p            ( MstIdWidth    ),
    .els_p              ( ID_FIFO_DEPTH ),
    .harden_p           ( 0             ),
    .ready_THEN_valid_p ( 0             )
  ) ar_id_fifo_i (
    .clk_i   ( clk_i                                  ),
    .reset_i ( rst_i                                   ),
    .v_i     ( xbar_mem_req.ar_valid && tx_arready     ),
    .data_i  ( xbar_mem_req.ar.id                      ),
    .ready_o (                                         ),
    .v_o     ( ar_id_q_v                              ),
    .data_o  ( ar_id_q_data                           ),
    .yumi_i  ( ar_id_q_yumi                           )
  );

  bsg_fifo_1r1w_small #(
    .width_p            ( MstIdWidth    ),
    .els_p              ( ID_FIFO_DEPTH ),
    .harden_p           ( 0             ),
    .ready_THEN_valid_p ( 0             )
  ) aw_id_fifo_i (
    .clk_i   ( clk_i                                  ),
    .reset_i ( rst_i                                   ),
    .v_i     ( xbar_mem_req.aw_valid && tx_awready     ),
    .data_i  ( xbar_mem_req.aw.id                      ),
    .ready_o (                                         ),
    .v_o     ( aw_id_q_v                              ),
    .data_o  ( aw_id_q_data                           ),
    .yumi_i  ( aw_id_q_yumi                           )
  );

  assign ar_id_q_yumi = rx_rvalid && xbar_mem_req.r_ready && rx_rlast;
  assign aw_id_q_yumi = rx_bvalid && xbar_mem_req.b_ready;

  always_comb begin
    xbar_mem_resp          = '0;
    // Ready signals come from axi_link_tx
    xbar_mem_resp.aw_ready = tx_awready;
    xbar_mem_resp.w_ready  = tx_wready;
    xbar_mem_resp.ar_ready = tx_arready;
    // R response from axi_link_rx, ID stamped from shim
    xbar_mem_resp.r_valid  = rx_rvalid;
    xbar_mem_resp.r.data   = axi_data_t'(rx_rdata);
    xbar_mem_resp.r.resp   = rx_rresp;
    xbar_mem_resp.r.last   = rx_rlast;
    xbar_mem_resp.r.id     = ar_id_q_data;
    // B response from axi_link_rx, ID stamped from shim
    xbar_mem_resp.b_valid  = rx_bvalid;
    xbar_mem_resp.b.resp   = rx_bresp;
    xbar_mem_resp.b.id     = aw_id_q_data;
  end

  // --------------------------------------------------------------------------
  // FPGA-originated AXI requests decoded from bsg_link RX -> fpga_mst_req.
  // Responses from the crossbar return through top_level_io TX R/B.
  //
  // axi_link does not transport AXI IDs or WSTRB.  Host traffic is therefore
  // treated as strict-FIFO, full-strobe traffic on this path.
  // --------------------------------------------------------------------------
  always_comb begin
    fpga_mst_req           = '0;
    fpga_mst_req.aw_valid  = rx_awvalid;
    fpga_mst_req.aw.addr   = axi_addr_t'(rx_awaddr);
    fpga_mst_req.aw.prot   = 3'b000;
    fpga_mst_req.aw.len    = rx_awlen;
    fpga_mst_req.aw.size   = rx_awsize;
    fpga_mst_req.aw.burst  = axi_pkg::burst_t'(rx_awburst);
    fpga_mst_req.w_valid   = rx_wvalid;
    fpga_mst_req.w.data    = axi_data_t'(rx_wdata);
    fpga_mst_req.w.strb    = '1;
    fpga_mst_req.w.last    = rx_wlast;
    fpga_mst_req.b_ready   = tx_bready;
    fpga_mst_req.ar_valid  = rx_arvalid;
    fpga_mst_req.ar.addr   = axi_addr_t'(rx_araddr);
    fpga_mst_req.ar.prot   = 3'b000;
    fpga_mst_req.ar.len    = rx_arlen;
    fpga_mst_req.ar.size   = rx_arsize;
    fpga_mst_req.ar.burst  = axi_pkg::burst_t'(rx_arburst);
    fpga_mst_req.r_ready   = tx_rready;
  end

  assign rx_awready = fpga_mst_resp.aw_ready;
  assign rx_wready  = fpga_mst_resp.w_ready;
  assign rx_arready = fpga_mst_resp.ar_ready;

  // --------------------------------------------------------------------------
  // top_level_io — bsg_link DDR physical layer + axi_link_tx/rx
  //   TX path: crossbar AW/W/AR → axi_link_tx → bsg_link_ddr_upstream → DDR pins
  //   RX path: DDR pins → bsg_link_ddr_downstream → axi_link_rx → R/B to crossbar
  // --------------------------------------------------------------------------
  top_level_io #(
    .flit_width_p                    ( FLIT_WIDTH             ),
    .addr_width_p                    ( ADDR_WIDTH             ),
    .channel_width_p                 ( CHANNEL_WIDTH          ),
    .num_channels_p                  ( 1                      ),
    .lg_fifo_depth_p                 ( LG_FIFO_DEPTH          ),
    .lg_credit_to_token_decimation_p ( LG_CREDIT_TO_TOKEN_DEC ),
    .bypass_twofer_fifo_p            ( BYPASS_TWOFER_FIFO     ),
    .bypass_gearbox_p                ( BYPASS_GEARBOX         ),
    .use_hardened_fifo_p             ( USE_HARDENED_FIFO      ),
    // RX FIFO sizes — large R data FIFO so full bitstream / meta bursts
    // (up to 54 / 16 beats) can be received without backpressuring the link.
    .rx_link_fifo_els_p              ( 64 ),
    .rx_aw_desc_fifo_els_p           ( 2   ),
    .rx_ar_desc_fifo_els_p           ( 2   ),
    .rx_w_len_fifo_els_p             ( 4   ),
    .rx_w_data_fifo_els_p            ( 8   ),
    .rx_r_len_fifo_els_p             ( 4   ),
    .rx_r_data_fifo_els_p            ( 64 ),
    .rx_b_resp_fifo_els_p            ( 4   ),
    // TX FIFO sizes
    .tx_link_fifo_els_p              ( 64 ),
    .tx_aw_desc_fifo_els_p           ( 2   ),
    .tx_ar_desc_fifo_els_p           ( 2   ),
    .tx_w_len_fifo_els_p             ( 4   ),
    .tx_w_data_fifo_els_p            ( 8   ),
    .tx_r_len_fifo_els_p             ( 4   ),
    .tx_r_data_fifo_els_p            ( 64 ),
    .tx_b_resp_fifo_els_p            ( 4   ),
    .tx_pkt_order_fifo_els_p         ( 8   )
  ) u_top_level_io (
    .core_clk_i                 ( clk_i                      ),
    .reset_i                    ( rst_i                      ),
    // bsg_link upstream control
    .io_master_clk_i            ( io_master_clk_i            ),
    .upstream_io_link_reset_i   ( upstream_io_link_reset_i   ),
    .async_token_reset_i        ( async_token_reset_i        ),
    .token_clk_i                ( token_clk_i                ),
    // bsg_link downstream control
    .downstream_io_link_reset_i ( downstream_io_link_reset_i ),
    .downstream_io_clk_i        ( downstream_io_clk_i       ),
    .downstream_io_data_i       ( downstream_io_data_i      ),
    .downstream_io_valid_i      ( downstream_io_valid_i     ),
    // DDR physical outputs
    .upstream_io_clk_r_o        ( upstream_io_clk_r_o       ),
    .upstream_io_data_r_o       ( upstream_io_data_r_o      ),
    .upstream_io_valid_r_o      ( upstream_io_valid_r_o     ),
    .downstream_core_token_r_o  ( downstream_core_token_r_o ),
    // TX: chip → FPGA SRAM (AW/W/AR requests)
    .tx_awvalid_i   ( xbar_mem_req.aw_valid                ),
    .tx_awready_o   ( tx_awready                           ),
    .tx_awaddr_i    ( xbar_mem_req.aw.addr[ADDR_WIDTH-1:0] ),
    .tx_awlen_i     ( xbar_mem_req.aw.len                  ),
    .tx_awsize_i    ( xbar_mem_req.aw.size                 ),
    .tx_awburst_i   ( xbar_mem_req.aw.burst                ),
    .tx_wvalid_i    ( xbar_mem_req.w_valid                 ),
    .tx_wready_o    ( tx_wready                            ),
    .tx_wdata_i     ( xbar_mem_req.w.data[DATA_WIDTH-1:0]   ),
    .tx_wlast_i     ( xbar_mem_req.w.last                  ),
    .tx_arvalid_i   ( xbar_mem_req.ar_valid                ),
    .tx_arready_o   ( tx_arready                           ),
    .tx_araddr_i    ( xbar_mem_req.ar.addr[ADDR_WIDTH-1:0] ),
    .tx_arlen_i     ( xbar_mem_req.ar.len                  ),
    .tx_arsize_i    ( xbar_mem_req.ar.size                 ),
    .tx_arburst_i   ( xbar_mem_req.ar.burst                ),
    // TX: responses to FPGA-originated requests decoded from bsg_link RX
    .tx_rvalid_i    ( fpga_mst_resp.r_valid              ),
    .tx_rready_o    ( tx_rready                          ),
    .tx_rdata_i     ( DATA_WIDTH'(fpga_mst_resp.r.data)   ),
    .tx_rresp_i     ( fpga_mst_resp.r.resp               ),
    .tx_rlast_i     ( fpga_mst_resp.r.last               ),
    .tx_bvalid_i    ( fpga_mst_resp.b_valid              ),
    .tx_bready_o    ( tx_bready                          ),
    .tx_bresp_i     ( fpga_mst_resp.b.resp               ),
    // RX: R/B responses FPGA SRAM → crossbar (ID stamped by shim)
    .rx_rvalid_o    ( rx_rvalid                  ),
    .rx_rready_i    ( xbar_mem_req.r_ready       ),
    .rx_rdata_o     ( rx_rdata                   ),
    .rx_rresp_o     ( rx_rresp                   ),
    .rx_rlast_o     ( rx_rlast                   ),
    .rx_bvalid_o    ( rx_bvalid                  ),
    .rx_bready_i    ( xbar_mem_req.b_ready       ),
    .rx_bresp_o     ( rx_bresp                   ),
    // RX: FPGA-originated requests into the on-chip crossbar
    .rx_awvalid_o   ( rx_awvalid ),
    .rx_awready_i   ( rx_awready ),
    .rx_awaddr_o    ( rx_awaddr  ),
    .rx_awlen_o     ( rx_awlen   ),
    .rx_awsize_o    ( rx_awsize  ),
    .rx_awburst_o   ( rx_awburst ),
    .rx_wvalid_o    ( rx_wvalid  ),
    .rx_wready_i    ( rx_wready  ),
    .rx_wdata_o     ( rx_wdata   ),
    .rx_wlast_o     ( rx_wlast   ),
    .rx_arvalid_o   ( rx_arvalid ),
    .rx_arready_i   ( rx_arready ),
    .rx_araddr_o    ( rx_araddr  ),
    .rx_arlen_o     ( rx_arlen   ),
    .rx_arsize_o    ( rx_arsize  ),
    .rx_arburst_o   ( rx_arburst )
  );

  // --------------------------------------------------------------------------
  // Full AXI4 crossbar
  // --------------------------------------------------------------------------
  axi4_full_crossbar u_xbar (
    .clk_i           ( clk_i           ),
    .rst_i           ( rst_i           ),
    .test_i          ( 1'b0            ),
    .fpga_mst_req_i  ( fpga_mst_req    ),
    .fpga_mst_resp_o ( fpga_mst_resp   ),
    .dfetch_req_i    ( dfetch_req      ),
    .dfetch_resp_o   ( dfetch_resp     ),
    .mfetch_req_i    ( mfetch_req      ),
    .mfetch_resp_o   ( mfetch_resp     ),
    .bsfetch_req_i   ( bsfetch_req     ),
    .bsfetch_resp_o  ( bsfetch_resp    ),
    .fpga_mem_req_o  ( xbar_mem_req    ),
    .fpga_mem_resp_i ( xbar_mem_resp   ),
    .cgra_csr_req_o  ( cgra_csr_req_o  ),
    .cgra_csr_resp_i ( cgra_csr_resp_i )
  );

endmodule : cgra_io_axi4_top
