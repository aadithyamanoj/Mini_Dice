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
//   mem_req_fifo → dfetch → crossbar → axi_link_tx → mem_link_tx → [link] → FPGA SRAM
//   FPGA SRAM → [link] → mem_link_rx → axi_link_rx → ID shim → crossbar → mem_req_fifo
//
// mem_link_tx/rx are physical serial link pins. In simulation the TB acts
// as the FPGA endpoint, decoding flits and returning flit-encoded responses.
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
    parameter int ID_FIFO_DEPTH = 4
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

    // mem_req_fifo enqueue interface (from CGRA backend)
    input  logic                                                                   enq_valid_i,
    output logic                                                                   enq_ready_o,
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                     enq_base_tid_i,
    input  logic [TID_BITMAP_WIDTH-1:0]                                           enq_tid_bitmap_i,
    input  logic [DICE_REG_ADDR_WIDTH-1:0]                                        enq_ld_dest_reg_i,
    input  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]  enq_address_map_i,
    input  logic [15:0]                                                            enq_addr_i,
    input  logic [15:0]                                                            enq_data_i,
    input  logic                                                                   enq_write_en_i,

    // mem_req_fifo response interface (to CGRA backend)
    output logic                                                                   rsp_valid_o,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                     rsp_base_tid_o,
    output logic [TID_BITMAP_WIDTH-1:0]                                           rsp_tid_bitmap_o,
    output logic [DICE_REG_ADDR_WIDTH-1:0]                                        rsp_ld_dest_reg_o,
    output logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]  rsp_address_map_o,
    output logic [(CACHE_LINE_SIZE*8)-1:0]                                        rsp_data_o,

    // Off-chip memory link: chip → FPGA SRAM  (axi_link_tx output)
    output logic                   mem_link_tx_v_o,
    output logic [FLIT_WIDTH-1:0]  mem_link_tx_data_o,
    input  logic                   mem_link_tx_ready_i,

    // Off-chip memory link: FPGA SRAM → chip  (axi_link_rx input)
    // mem_link_rx_ready_o is the yumi signal: high when the flit was consumed
    input  logic                   mem_link_rx_v_i,
    input  logic [FLIT_WIDTH-1:0]  mem_link_rx_data_i,
    output logic                   mem_link_rx_ready_o,

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
    .clk_i             ( clk_i             ),
    .rst_i             ( rst_i             ),
    .enq_valid_i       ( enq_valid_i       ),
    .enq_ready_o       ( enq_ready_o       ),
    .enq_base_tid_i    ( enq_base_tid_i    ),
    .enq_tid_bitmap_i  ( enq_tid_bitmap_i  ),
    .enq_ld_dest_reg_i ( enq_ld_dest_reg_i ),
    .enq_address_map_i ( enq_address_map_i ),
    .enq_addr_i        ( enq_addr_i        ),
    .enq_data_i        ( enq_data_i        ),
    .enq_write_en_i    ( enq_write_en_i    ),
    .axi_awaddr_o      ( fifo_awaddr       ),
    .axi_awvalid_o     ( fifo_awvalid      ),
    .axi_awready_i     ( fifo_awready      ),
    .axi_wdata_o       ( fifo_wdata        ),
    .axi_wstrb_o       ( fifo_wstrb        ),
    .axi_wvalid_o      ( fifo_wvalid       ),
    .axi_wready_i      ( fifo_wready       ),
    .axi_bresp_i       ( fifo_bresp        ),
    .axi_bvalid_i      ( fifo_bvalid       ),
    .axi_bready_o      ( fifo_bready       ),
    .axi_araddr_o      ( fifo_araddr       ),
    .axi_arvalid_o     ( fifo_arvalid      ),
    .axi_arready_i     ( fifo_arready      ),
    .axi_rdata_i       ( fifo_rdata        ),
    .axi_rresp_i       ( fifo_rresp        ),
    .axi_rvalid_i      ( fifo_rvalid       ),
    .axi_rready_o      ( fifo_rready       ),
    .rsp_valid_o       ( rsp_valid_o       ),
    .rsp_base_tid_o    ( rsp_base_tid_o    ),
    .rsp_tid_bitmap_o  ( rsp_tid_bitmap_o  ),
    .rsp_ld_dest_reg_o ( rsp_ld_dest_reg_o ),
    .rsp_address_map_o ( rsp_address_map_o ),
    .rsp_data_o        ( rsp_data_o        )
  );

  // --------------------------------------------------------------------------
  // axi_link_tx — serialize AW/W/AR from crossbar to flits going to FPGA SRAM
  // --------------------------------------------------------------------------
  axi_link_tx #(
    .flit_width_p         ( FLIT_WIDTH ),
    .addr_width_p         ( ADDR_WIDTH ),
    .link_fifo_els_p      ( 8          ),
    .aw_desc_fifo_els_p   ( 2          ),
    .ar_desc_fifo_els_p   ( 2          ),
    .w_len_fifo_els_p     ( 4          ),
    .w_data_fifo_els_p    ( 8          ),
    .r_len_fifo_els_p     ( 4          ),
    .r_data_fifo_els_p    ( 8          ),
    .b_resp_fifo_els_p    ( 4          ),
    .pkt_order_fifo_els_p ( 8          )
  ) u_axi_link_tx (
    .clk_i          ( clk_i                                ),
    .reset_i        ( rst_i                                ),
    // AW
    .awvalid_i      ( xbar_mem_req.aw_valid                ),
    .awready_o      ( tx_awready                           ),
    .awaddr_i       ( xbar_mem_req.aw.addr[ADDR_WIDTH-1:0] ),
    .awlen_i        ( xbar_mem_req.aw.len                  ),
    .awsize_i       ( xbar_mem_req.aw.size                 ),
    .awburst_i      ( xbar_mem_req.aw.burst                ),
    // W
    .wvalid_i       ( xbar_mem_req.w_valid                 ),
    .wready_o       ( tx_wready                            ),
    .wdata_i        ( xbar_mem_req.w.data[15:0]            ),
    .wlast_i        ( xbar_mem_req.w.last                  ),
    // AR
    .arvalid_i      ( xbar_mem_req.ar_valid                ),
    .arready_o      ( tx_arready                           ),
    .araddr_i       ( xbar_mem_req.ar.addr[ADDR_WIDTH-1:0] ),
    .arlen_i        ( xbar_mem_req.ar.len                  ),
    .arsize_i       ( xbar_mem_req.ar.size                 ),
    .arburst_i      ( xbar_mem_req.ar.burst                ),
    // R/B inputs — chip does not send responses to FPGA on this link
    .rvalid_i       ( 1'b0                                 ),
    .rready_o       (                                      ),
    .rdata_i        ( '0                                   ),
    .rresp_i        ( '0                                   ),
    .rlast_i        ( 1'b0                                 ),
    .bvalid_i       ( 1'b0                                 ),
    .bready_o       (                                      ),
    .bresp_i        ( '0                                   ),
    // Flit link output → off-chip
    .link_tx_v_o    ( mem_link_tx_v_o                      ),
    .link_tx_data_o ( mem_link_tx_data_o                   ),
    .link_tx_ready_i( mem_link_tx_ready_i                  )
  );

  // --------------------------------------------------------------------------
  // axi_link_rx — deserialize FPGA SRAM response flits into AXI R/B
  // --------------------------------------------------------------------------
  axi_link_rx #(
    .flit_width_p       ( FLIT_WIDTH ),
    .addr_width_p       ( ADDR_WIDTH ),
    .link_fifo_els_p    ( 8          ),
    .aw_desc_fifo_els_p ( 2          ),
    .ar_desc_fifo_els_p ( 2          ),
    .w_len_fifo_els_p   ( 4          ),
    .w_data_fifo_els_p  ( 8          ),
    .r_len_fifo_els_p   ( 4          ),
    .r_data_fifo_els_p  ( 8          ),
    .b_resp_fifo_els_p  ( 4          )
  ) u_axi_link_rx (
    .clk_i          ( clk_i                      ),
    .reset_i        ( rst_i                      ),
    // Flit link input ← off-chip; yumi = flit consumed
    .link_rx_v_i    ( mem_link_rx_v_i            ),
    .link_rx_data_i ( mem_link_rx_data_i         ),
    .link_rx_yumi_o ( mem_link_rx_ready_o        ),
    // AW/W/AR outputs ignored (FPGA does not issue requests on this link)
    .awvalid_o      (                            ),
    .awready_i      ( 1'b0                       ),
    .awaddr_o       (                            ),
    .awlen_o        (                            ),
    .awsize_o       (                            ),
    .awburst_o      (                            ),
    .wvalid_o       (                            ),
    .wready_i       ( 1'b0                       ),
    .wdata_o        (                            ),
    .wlast_o        (                            ),
    .arvalid_o      (                            ),
    .arready_i      ( 1'b0                       ),
    .araddr_o       (                            ),
    .arlen_o        (                            ),
    .arsize_o       (                            ),
    .arburst_o      (                            ),
    // R → crossbar (ID stamped by shim)
    .rvalid_o       ( rx_rvalid                  ),
    .rready_i       ( xbar_mem_req.r_ready       ),
    .rdata_o        ( rx_rdata                   ),
    .rresp_o        ( rx_rresp                   ),
    .rlast_o        ( rx_rlast                   ),
    // B → crossbar (ID stamped by shim)
    .bvalid_o       ( rx_bvalid                  ),
    .bready_i       ( xbar_mem_req.b_ready       ),
    .bresp_o        ( rx_bresp                   )
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
