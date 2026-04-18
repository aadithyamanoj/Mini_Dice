// =============================================================================
// cgra_io_axi4_top.sv
//
// CGRA IO top-level integrating:
//   fpga_mst  : FPGA flat AXI-Lite direct master port
//   dfetch    : CGRA backend memory requests via mem_req_fifo
//   mfetch    : idle (future metadata fetch)
//   bsfetch   : idle (future bitstream fetch)
//
// Off-chip memory path (chip → FPGA SRAM → chip):
//   mem_req_fifo → [dfetch port] → crossbar → top_level_io TX → bsg_link_ddr_upstream → [DDR] → FPGA SRAM
//   FPGA SRAM → [DDR] → bsg_link_ddr_downstream → top_level_io RX → ID shim → crossbar → mem_req_fifo
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
    parameter int DATA_WIDTH    = 16,
    parameter int FLIT_WIDTH    = 16,
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

    // FPGA AXI-Lite master (flat pins) — fpga_mst crossbar port
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

    // mem_req_fifo enqueue interface (from CGRA backend) — 4 parallel ports
    input  logic enq_valid_i_0,
    input  logic enq_valid_i_1,
    input  logic enq_valid_i_2,
    input  logic enq_valid_i_3,
    output logic enq_ready_o,
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] enq_tid_i,
    input  logic [15:0] enq_addr_i_0,
    input  logic [15:0] enq_addr_i_1,
    input  logic [15:0] enq_addr_i_2,
    input  logic [15:0] enq_addr_i_3,
    input  logic [15:0] enq_data_i_0,
    input  logic [15:0] enq_data_i_1,
    input  logic [15:0] enq_data_i_2,
    input  logic [15:0] enq_data_i_3,
    input  logic enq_op_i_0,   // 0 = load, 1 = store
    input  logic enq_op_i_1,
    input  logic enq_op_i_2,
    input  logic enq_op_i_3,

    // mem_req_fifo response interface (to CGRA backend)
    input  logic                                              rsp_data_ready_i,
    output logic                                              pop_o,
    output logic                                              rsp_valid_o,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] rsp_tid_o,
    output logic [15:0]                                       rsp_addr_o,
    output logic [DICE_REG_DATA_WIDTH-1:0]                    rsp_data_o,

    // bsg_link upstream (chip → FPGA SRAM): source-synchronous DDR
    input  logic        io_master_clk_i,            // IO master clock for upstream link
    input  logic        upstream_io_link_reset_i,   // IO-domain reset for upstream link
    input  logic        async_token_reset_i,         // Async token counter reset
    input  logic        token_clk_i,                // Token credit clock from FPGA downstream
    output logic        upstream_io_clk_r_o,         // Forwarded clock to FPGA
    output logic [7:0]  upstream_io_data_r_o,        // DDR data to FPGA (channel_width=8, DDR)
    output logic        upstream_io_valid_r_o,       // DDR valid to FPGA

    // bsg_link downstream (FPGA SRAM → chip): source-synchronous DDR
    input  logic        downstream_io_link_reset_i,  // IO-domain reset for downstream link
    input  logic        downstream_io_clk_i,         // Forwarded clock from FPGA
    input  logic [7:0]  downstream_io_data_i,        // DDR data from FPGA (channel_width=8, DDR)
    input  logic        downstream_io_valid_i,       // DDR valid from FPGA
    output logic        downstream_core_token_r_o,   // Token credit back to FPGA upstream

    // CSR slave port (on-chip)
    output mst_req_t  cgra_csr_req_o,
    input  mst_resp_t cgra_csr_resp_i
);

  // --------------------------------------------------------------------------
  // AXI-Lite wires: mem_req_fifo → dfetch_req
  // --------------------------------------------------------------------------
  logic [15:0] fifo_awaddr, fifo_araddr;
  logic [15:0] fifo_wdata;
  logic [1:0]  fifo_wstrb, fifo_bresp, fifo_rresp;
  logic        fifo_awvalid, fifo_awready;
  logic        fifo_wvalid,  fifo_wready;
  logic        fifo_bvalid,  fifo_bready;
  logic        fifo_arvalid, fifo_arready;
  logic [DATA_WIDTH-1:0] fifo_rdata;
  logic        fifo_rvalid,  fifo_rready;

  // --------------------------------------------------------------------------
  // Crossbar request/response structs
  // --------------------------------------------------------------------------
  slv_req_t  fpga_mst_req,  dfetch_req;
  slv_resp_t fpga_mst_resp, dfetch_resp;
  slv_req_t  mfetch_req,    bsfetch_req;
  slv_resp_t mfetch_resp,   bsfetch_resp;

  // Crossbar fpga_mem slave port wires (internal — replaced by link modules)
  mst_req_t  xbar_mem_req;
  mst_resp_t xbar_mem_resp;

  // --------------------------------------------------------------------------
  // FPGA flat AXI-Lite → fpga_mst_req
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // mem_req_fifo AXI-Lite → dfetch_req (AXI4 promotion)
  // --------------------------------------------------------------------------
  always_comb begin
    dfetch_req           = '0;
    dfetch_req.aw_valid  = fifo_awvalid;
    dfetch_req.aw.addr   = axi_addr_t'(fifo_awaddr);
    dfetch_req.aw.len    = '0;
    dfetch_req.aw.size   = 3'b001;
    dfetch_req.aw.burst  = BURST_INCR;
    dfetch_req.w_valid   = fifo_wvalid;
    dfetch_req.w.data    = axi_data_t'(fifo_wdata);
    dfetch_req.w.strb    = axi_strb_t'(fifo_wstrb);
    dfetch_req.w.last    = 1'b1;
    dfetch_req.b_ready   = fifo_bready;
    dfetch_req.ar_valid  = fifo_arvalid;
    dfetch_req.ar.addr   = axi_addr_t'(fifo_araddr);
    dfetch_req.ar.len    = '0;
    dfetch_req.ar.size   = 3'b001;
    dfetch_req.ar.burst  = BURST_INCR;
    dfetch_req.r_ready   = fifo_rready;
  end
  assign fifo_awready = dfetch_resp.aw_ready;
  assign fifo_wready  = dfetch_resp.w_ready;
  assign fifo_bresp   = dfetch_resp.b.resp;
  assign fifo_bvalid  = dfetch_resp.b_valid;
  assign fifo_arready = dfetch_resp.ar_ready;
  assign fifo_rdata   = DATA_WIDTH'(dfetch_resp.r.data);
  assign fifo_rresp   = dfetch_resp.r.resp;
  assign fifo_rvalid  = dfetch_resp.r_valid;

  // mfetch / bsfetch idle
  always_comb begin
    mfetch_req          = '0;
    mfetch_req.b_ready  = 1'b1;
    mfetch_req.r_ready  = 1'b1;
    bsfetch_req         = '0;
    bsfetch_req.b_ready = 1'b1;
    bsfetch_req.r_ready = 1'b1;
  end

  // --------------------------------------------------------------------------
  // ID shim — axi_link_rx carries no IDs; capture crossbar-prepended IDs on
  // outgoing AR/AW and stamp them onto incoming R/B responses so the crossbar
  // can route responses back to the correct master port.
  // --------------------------------------------------------------------------
  logic        tx_awready, tx_wready, tx_arready;
  logic        rx_rvalid, rx_rlast;
  logic [15:0] rx_rdata;
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
  // mem_req_fifo (CGRA backend → dfetch crossbar port)
  // --------------------------------------------------------------------------
  mem_req_fifo u_mem_req_fifo (
    .clk_i            ( clk_i            ),
    .rst_i            ( rst_i            ),
    .enq_valid_i_0    ( enq_valid_i_0    ),
    .enq_valid_i_1    ( enq_valid_i_1    ),
    .enq_valid_i_2    ( enq_valid_i_2    ),
    .enq_valid_i_3    ( enq_valid_i_3    ),
    .enq_ready_o      ( enq_ready_o      ),
    .enq_tid_i        ( enq_tid_i        ),
    .enq_e_block_id_i ( '0               ),  // not used in crossbar test
    .enq_addr_i_0     ( enq_addr_i_0     ),
    .enq_addr_i_1     ( enq_addr_i_1     ),
    .enq_addr_i_2     ( enq_addr_i_2     ),
    .enq_addr_i_3     ( enq_addr_i_3     ),
    .enq_data_i_0     ( enq_data_i_0     ),
    .enq_data_i_1     ( enq_data_i_1     ),
    .enq_data_i_2     ( enq_data_i_2     ),
    .enq_data_i_3     ( enq_data_i_3     ),
    .enq_rsp_addr_i_0 ( '0               ),  // not used in crossbar test
    .enq_rsp_addr_i_1 ( '0               ),
    .enq_rsp_addr_i_2 ( '0               ),
    .enq_rsp_addr_i_3 ( '0               ),
    .enq_op_i_0       ( enq_op_i_0       ),
    .enq_op_i_1       ( enq_op_i_1       ),
    .enq_op_i_2       ( enq_op_i_2       ),
    .enq_op_i_3       ( enq_op_i_3       ),
    .axi_awaddr_o     ( fifo_awaddr      ),
    .axi_awvalid_o    ( fifo_awvalid     ),
    .axi_awready_i    ( fifo_awready     ),
    .axi_wdata_o      ( fifo_wdata       ),
    .axi_wstrb_o      ( fifo_wstrb       ),
    .axi_wvalid_o     ( fifo_wvalid      ),
    .axi_wready_i     ( fifo_wready      ),
    .axi_bresp_i      ( fifo_bresp       ),
    .axi_bvalid_i     ( fifo_bvalid      ),
    .axi_bready_o     ( fifo_bready      ),
    .axi_araddr_o     ( fifo_araddr      ),
    .axi_arvalid_o    ( fifo_arvalid     ),
    .axi_arready_i    ( fifo_arready     ),
    .axi_rdata_i      ( fifo_rdata       ),
    .axi_rresp_i      ( fifo_rresp       ),
    .axi_rvalid_i     ( fifo_rvalid      ),
    .axi_rready_o     ( fifo_rready      ),
    .rsp_data_ready_i ( {DICE_NUM_BANKS{rsp_data_ready_i}} ),  // replicate 1-bit to all banks
    .rsp_special_ready_i ( 1'b1          ),  // not used in crossbar test
    .pop_o            ( pop_o            ),
    .rsp_valid_o      ( rsp_valid_o      ),
    .rsp_tid_o        ( rsp_tid_o        ),
    .rsp_e_block_id_o        (            ),  // not used in crossbar test
    .rsp_addr_o              ( rsp_addr_o       ),
    .rsp_data_o              ( rsp_data_o       ),
    .store_pop_o             (            ),  // not used in crossbar test
    .store_pop_e_block_id_o  (            )   // not used in crossbar test
  );

  // --------------------------------------------------------------------------
  // top_level_io — bsg_link DDR physical layer + axi_link_tx/rx
  //   TX path: crossbar AW/W/AR → axi_link_tx → bsg_link_ddr_upstream → DDR pins
  //   RX path: DDR pins → bsg_link_ddr_downstream → axi_link_rx → R/B to crossbar
  // --------------------------------------------------------------------------
  top_level_io #(
    .flit_width_p                    ( FLIT_WIDTH             ),
    .addr_width_p                    ( ADDR_WIDTH             ),
    .channel_width_p                 ( 8                      ),
    .num_channels_p                  ( 1                      ),
    .lg_fifo_depth_p                 ( LG_FIFO_DEPTH          ),
    .lg_credit_to_token_decimation_p ( LG_CREDIT_TO_TOKEN_DEC ),
    .bypass_twofer_fifo_p            ( BYPASS_TWOFER_FIFO     ),
    .bypass_gearbox_p                ( BYPASS_GEARBOX         ),
    .use_hardened_fifo_p             ( USE_HARDENED_FIFO      ),
    // RX FIFO sizes
    .rx_link_fifo_els_p              ( 8  ),
    .rx_aw_desc_fifo_els_p           ( 2  ),
    .rx_ar_desc_fifo_els_p           ( 2  ),
    .rx_w_len_fifo_els_p             ( 4  ),
    .rx_w_data_fifo_els_p            ( 8  ),
    .rx_r_len_fifo_els_p             ( 4  ),
    .rx_r_data_fifo_els_p            ( 8  ),
    .rx_b_resp_fifo_els_p            ( 4  ),
    // TX FIFO sizes
    .tx_link_fifo_els_p              ( 8  ),
    .tx_aw_desc_fifo_els_p           ( 2  ),
    .tx_ar_desc_fifo_els_p           ( 2  ),
    .tx_w_len_fifo_els_p             ( 4  ),
    .tx_w_data_fifo_els_p            ( 8  ),
    .tx_r_len_fifo_els_p             ( 4  ),
    .tx_r_data_fifo_els_p            ( 8  ),
    .tx_b_resp_fifo_els_p            ( 4  ),
    .tx_pkt_order_fifo_els_p         ( 8  )
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
    .tx_wdata_i     ( xbar_mem_req.w.data[15:0]            ),
    .tx_wlast_i     ( xbar_mem_req.w.last                  ),
    .tx_arvalid_i   ( xbar_mem_req.ar_valid                ),
    .tx_arready_o   ( tx_arready                           ),
    .tx_araddr_i    ( xbar_mem_req.ar.addr[ADDR_WIDTH-1:0] ),
    .tx_arlen_i     ( xbar_mem_req.ar.len                  ),
    .tx_arsize_i    ( xbar_mem_req.ar.size                 ),
    .tx_arburst_i   ( xbar_mem_req.ar.burst                ),
    // TX: chip does NOT send R/B responses back to FPGA
    .tx_rvalid_i    ( 1'b0 ),
    .tx_rready_o    (      ),
    .tx_rdata_i     ( '0   ),
    .tx_rresp_i     ( '0   ),
    .tx_rlast_i     ( 1'b0 ),
    .tx_bvalid_i    ( 1'b0 ),
    .tx_bready_o    (      ),
    .tx_bresp_i     ( '0   ),
    // RX: R/B responses FPGA SRAM → crossbar (ID stamped by shim)
    .rx_rvalid_o    ( rx_rvalid                  ),
    .rx_rready_i    ( xbar_mem_req.r_ready       ),
    .rx_rdata_o     ( rx_rdata                   ),
    .rx_rresp_o     ( rx_rresp                   ),
    .rx_rlast_o     ( rx_rlast                   ),
    .rx_bvalid_o    ( rx_bvalid                  ),
    .rx_bready_i    ( xbar_mem_req.b_ready       ),
    .rx_bresp_o     ( rx_bresp                   ),
    // RX: AW/W/AR ignored (FPGA does not initiate requests to chip)
    .rx_awvalid_o   (      ),
    .rx_awready_i   ( 1'b0 ),
    .rx_awaddr_o    (      ),
    .rx_awlen_o     (      ),
    .rx_awsize_o    (      ),
    .rx_awburst_o   (      ),
    .rx_wvalid_o    (      ),
    .rx_wready_i    ( 1'b0 ),
    .rx_wdata_o     (      ),
    .rx_wlast_o     (      ),
    .rx_arvalid_o   (      ),
    .rx_arready_i   ( 1'b0 ),
    .rx_araddr_o    (      ),
    .rx_arlen_o     (      ),
    .rx_arsize_o    (      ),
    .rx_arburst_o   (      )
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
