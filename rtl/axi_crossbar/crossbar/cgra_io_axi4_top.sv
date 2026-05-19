// =============================================================================
// cgra_io_axi4_top.sv
//
// CGRA IO top-level integrating:
//   fpga_mst  : FPGA-initiated AXI4 master (arrives via bsg_link RX)
//   fpga_mem  : crossbar master port to off-chip memory (via bsg_link TX/RX)
//   dfetch    : CGRA backend AXI4 port — driven directly by dice_core LDST FIFO
//   mfetch    : CGRA frontend metadata fetch (slv_req_t from dice_core)
//   bsfetch   : CGRA frontend bitstream fetch (slv_req_t from dice_core)
//
// One bsg_link pair carries *both* AXI buses by multiplexing on axi_link_tx/rx
// opcodes (WRITE / BURST_READ / READ / READ_RESP):
//
//   TX (chip → FPGA): fpga_mem AW/W/AR (chip as master) + fpga_mst R/B (chip as slave)
//   RX (FPGA → chip): fpga_mem R/B (FPGA SRAM responds)  + fpga_mst AW/W/AR (FPGA host)
//
// Only core-side bsg_link flit streams are exposed at the module boundary; the
// source-synchronous DDR PHY lives outside this module at chip_top.
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
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 32,
    parameter int FLIT_WIDTH = 32,
    parameter int CHANNEL_WIDTH = 8,
    // Unused — the chip-side AR/AW-ID FIFOs are retired; the link carries
    // a small inline routing-tag ID per packet. Outstanding-write tracking
    // is bounded by fake_b_max_outstanding_p inside top_level_io.
    parameter int ID_FIFO_DEPTH = 4,
    // bsg_link DDR parameters
    parameter int LG_FIFO_DEPTH = 6,  // bsg_link credit-FIFO depth (log2)
    parameter int LG_CREDIT_TO_TOKEN_DEC = 3,  // bsg_link token decimation (log2)
    parameter int BYPASS_TWOFER_FIFO = 0,  // 1 = bypass twofer FIFO (use in sim)
    parameter int BYPASS_GEARBOX = 1,  // bypass PISO/SIPO gearbox (piso_ratio=1, always bypassed)
    parameter int USE_HARDENED_FIFO = 0  // 1 = use hardened FIFO cells
) (
    input logic clk_i,
    input logic rst_i,

    // NOTE: FPGA AXI4 master no longer has flat pins on this module — it
    // arrives via the bsg_link downstream (FPGA → chip) and responses leave
    // via the bsg_link upstream (chip → FPGA). See fpga_mst_req construction
    // below (driven by top_level_io RX AW/W/AR) and the TX R/B inputs on
    // top_level_io (driven by fpga_mst_resp).

    // mfetch / bsfetch AXI4 master ports (slv_req_t from dice_core)
    input  slv_req_t  mfetch_req_i,
    output slv_resp_t mfetch_resp_o,
    input  slv_req_t  bsfetch_req_i,
    output slv_resp_t bsfetch_resp_o,

    // dfetch AXI4 masters (flat pins from dice_core LDST per-port FIFOs)
    input  logic [NUM_MEM_PORTS-1:0][DATA_WIDTH-1:0] dfetch_awaddr_i,
    input  logic [NUM_MEM_PORTS-1:0]                  dfetch_awvalid_i,
    output logic [NUM_MEM_PORTS-1:0]                  dfetch_awready_o,

    input  logic [NUM_MEM_PORTS-1:0][DATA_WIDTH-1:0] dfetch_wdata_i,
    input  logic [NUM_MEM_PORTS-1:0][1:0]            dfetch_wstrb_i,
    input  logic [NUM_MEM_PORTS-1:0]                 dfetch_wvalid_i,
    output logic [NUM_MEM_PORTS-1:0]                 dfetch_wready_o,

    output logic [NUM_MEM_PORTS-1:0][1:0] dfetch_bresp_o,
    output logic [NUM_MEM_PORTS-1:0]      dfetch_bvalid_o,
    input  logic [NUM_MEM_PORTS-1:0]      dfetch_bready_i,

    input  logic [NUM_MEM_PORTS-1:0][DATA_WIDTH-1:0]    dfetch_araddr_i,
    input  logic [NUM_MEM_PORTS-1:0][AxiUserWidth-1:0] dfetch_aruser_i,
    input  logic [NUM_MEM_PORTS-1:0]                    dfetch_arvalid_i,
    output logic [NUM_MEM_PORTS-1:0]                    dfetch_arready_o,

    output logic [DATA_WIDTH-1:0] dfetch_rdata_o,
    output logic [1:0]            dfetch_rresp_o,
    output logic                  dfetch_rvalid_o,
    input  logic                  dfetch_rready_i,

    // Core-side stream from the external bsg_link wrapper.
    input  logic [FLIT_WIDTH-1:0] link_rx_data_i,
    input  logic                  link_rx_valid_i,
    output logic                  link_rx_yumi_o,

    // Core-side stream to the external bsg_link wrapper.
    output logic [FLIT_WIDTH-1:0] link_tx_data_o,
    output logic                  link_tx_valid_o,
    input  logic                  link_tx_ready_i,

    // CSR slave port (on-chip)
    output mst_req_t  cgra_csr_req_o,
    input  mst_resp_t cgra_csr_resp_i
);

  // --------------------------------------------------------------------------
  // Crossbar request/response structs — dfetch driven directly from dfetch_* ports
  // --------------------------------------------------------------------------
  slv_req_t fpga_mst_req;
  slv_resp_t fpga_mst_resp;
  slv_req_t [NUM_MEM_PORTS-1:0] dfetch_req;
  slv_resp_t [NUM_MEM_PORTS-1:0] dfetch_resp;
  slv_req_t mfetch_req, bsfetch_req;
  slv_resp_t mfetch_resp, bsfetch_resp;

  // Crossbar fpga_mem slave port wires (internal — replaced by link modules)
  mst_req_t                   xbar_mem_req;
  mst_resp_t                  xbar_mem_resp;

  // --------------------------------------------------------------------------
  // bsg_link RX → fpga_mst_req
  //   top_level_io RX decodes AW/W/AR out of link flits.  fpga_mst is the
  //   crossbar slave port for FPGA-initiated traffic: we build its slv_req_t
  //   from the RX outputs and drive its slv_resp_t back onto the RX ready
  //   inputs.  No ID shim is needed on the chip side — we stamp a constant
  //   id = '0 here; the FPGA side is responsible for preserving its own
  //   host-side IDs symmetrically.
  //
  //   Fields not carried by the link (id, wstrb, prot, qos, lock, cache,
  //   region, user) are defaulted:
  //     - id    : '0  (single master behind this link, constant is safe)
  //     - wstrb : '1  (full-word writes — cgra_io_csr ignores upper bits)
  //     - prot  : '0
  // --------------------------------------------------------------------------
  logic                       rx_fpga_awvalid;
  logic      [ADDR_WIDTH-1:0] rx_fpga_awaddr;
  logic      [           7:0] rx_fpga_awlen;
  logic      [           2:0] rx_fpga_awsize;
  logic      [           1:0] rx_fpga_awburst;
  logic      [           1:0] rx_fpga_awid;
  logic                       rx_fpga_wvalid;
  logic      [DATA_WIDTH-1:0] rx_fpga_wdata;
  logic                       rx_fpga_wlast;
  logic                       rx_fpga_arvalid;
  logic      [ADDR_WIDTH-1:0] rx_fpga_araddr;
  logic      [           7:0] rx_fpga_arlen;
  logic      [           2:0] rx_fpga_arsize;
  logic      [           1:0] rx_fpga_arburst;
  logic                       rx_fpga_ar_is_burst;
  logic      [           1:0] rx_fpga_arid;
  logic      [           3:0] rx_fpga_ar_tid;
  logic      [           2:0] rx_fpga_ar_eblock;
  logic      [           4:0] rx_fpga_ar_regaddr;

  logic                       tx_fpga_bready;
  logic                       tx_fpga_rready;

  // FPGA-host traffic arriving on fpga_mst uses ID=0 internally — the
  // host-side AXI ID is unused inside the chip. The unpacked tid/eblock/
  // regaddr fields are CGRA load-metadata semantics that the FPGA host
  // does not produce, so ar.user is left zero on this path.
  always_comb begin
    fpga_mst_req          = '0;
    fpga_mst_req.aw_valid = rx_fpga_awvalid;
    fpga_mst_req.aw.addr  = axi_addr_t'(rx_fpga_awaddr);
    fpga_mst_req.aw.len   = rx_fpga_awlen;
    fpga_mst_req.aw.size  = rx_fpga_awsize;
    fpga_mst_req.aw.burst = rx_fpga_awburst;
    fpga_mst_req.aw.id    = '0;
    fpga_mst_req.w_valid  = rx_fpga_wvalid;
    fpga_mst_req.w.data   = axi_data_t'(rx_fpga_wdata);
    fpga_mst_req.w.strb   = '1;
    fpga_mst_req.w.last   = rx_fpga_wlast;
    fpga_mst_req.b_ready  = tx_fpga_bready;
    fpga_mst_req.ar_valid = rx_fpga_arvalid;
    fpga_mst_req.ar.addr  = axi_addr_t'(rx_fpga_araddr);
    fpga_mst_req.ar.len   = rx_fpga_arlen;
    fpga_mst_req.ar.size  = rx_fpga_arsize;
    fpga_mst_req.ar.burst = rx_fpga_arburst;
    fpga_mst_req.ar.id    = '0;
    fpga_mst_req.ar.user  = '0;
    fpga_mst_req.r_ready  = tx_fpga_rready;
  end

  // --------------------------------------------------------------------------
  // dice_core AXI4 dfetch_* → dfetch_req (single-beat promotion)
  // --------------------------------------------------------------------------
  logic [NUM_MEM_PORTS-1:0] dfetch_r_grant;

  for (genvar dfetch_i = 0; dfetch_i < NUM_MEM_PORTS; dfetch_i++) begin : gen_dfetch_req
    always_comb begin
      dfetch_req[dfetch_i]          = '0;
      dfetch_req[dfetch_i].aw_valid = dfetch_awvalid_i[dfetch_i];
      dfetch_req[dfetch_i].aw.addr  = axi_addr_t'(dfetch_awaddr_i[dfetch_i]);
      dfetch_req[dfetch_i].aw.len   = '0;
      dfetch_req[dfetch_i].aw.size  = 3'b010;
      dfetch_req[dfetch_i].aw.burst = BURST_INCR;
      dfetch_req[dfetch_i].w_valid  = dfetch_wvalid_i[dfetch_i];
      dfetch_req[dfetch_i].w.data   = axi_data_t'(dfetch_wdata_i[dfetch_i]);
      dfetch_req[dfetch_i].w.strb   = axi_strb_t'(dfetch_wstrb_i[dfetch_i]);
      dfetch_req[dfetch_i].w.last   = 1'b1;
      dfetch_req[dfetch_i].b_ready  = dfetch_bready_i[dfetch_i];
      dfetch_req[dfetch_i].ar_valid = dfetch_arvalid_i[dfetch_i];
      dfetch_req[dfetch_i].ar.addr  = axi_addr_t'(dfetch_araddr_i[dfetch_i]);
      dfetch_req[dfetch_i].ar.user  = axi_user_t'(dfetch_aruser_i[dfetch_i]);
      dfetch_req[dfetch_i].ar.len   = '0;
      dfetch_req[dfetch_i].ar.size  = 3'b010;
      dfetch_req[dfetch_i].ar.burst = BURST_INCR;
      dfetch_req[dfetch_i].r_ready  = dfetch_rready_i && dfetch_r_grant[dfetch_i];
    end

    assign dfetch_awready_o[dfetch_i] = dfetch_resp[dfetch_i].aw_ready;
    assign dfetch_wready_o[dfetch_i]  = dfetch_resp[dfetch_i].w_ready;
    assign dfetch_bresp_o[dfetch_i]   = dfetch_resp[dfetch_i].b.resp;
    assign dfetch_bvalid_o[dfetch_i]  = dfetch_resp[dfetch_i].b_valid;
    assign dfetch_arready_o[dfetch_i] = dfetch_resp[dfetch_i].ar_ready;
  end

  always_comb begin
    dfetch_r_grant = '0;
    dfetch_rdata_o = '0;
    dfetch_rresp_o = '0;
    dfetch_rvalid_o = 1'b0;

    for (int i = 0; i < NUM_MEM_PORTS; i++) begin
      if ((dfetch_r_grant == '0) && dfetch_resp[i].r_valid) begin
        dfetch_r_grant[i] = 1'b1;
        dfetch_rdata_o = DATA_WIDTH'(dfetch_resp[i].r.data);
        dfetch_rresp_o = dfetch_resp[i].r.resp;
        dfetch_rvalid_o = 1'b1;
      end
    end
  end

  assign mfetch_req    = mfetch_req_i;
  assign mfetch_resp_o = mfetch_resp;
  assign bsfetch_req   = bsfetch_req_i;
  assign bsfetch_resp_o = bsfetch_resp;

  // --------------------------------------------------------------------------
  // Crossbar-side ID translation
  // --------------------------------------------------------------------------
  // The link carries a small (1- or 2-bit) routing-tag ID inline on every
  // request and response header. The crossbar still uses its native
  // MstIdWidth-bit AXI ID, so the wrapper translates between the two:
  //
  //   request direction  : compress the crossbar's slave-index portion of
  //                        ar.id / aw.id into the link's routing tag, plus
  //                        pick the BURST_READ vs READ class.
  //   response direction : expand the link's routing tag back into a full
  //                        master-side ID by inserting the matching
  //                        slave-index bits. The slave-side id portion is
  //                        always zero because every producing slave port
  //                        drives its outgoing id with 0.
  //
  // ID layout reminder (matches axi4_full_crossbar.sv):
  //   MstId[MstIdWidth-1 -: $clog2(NoMasters)] = slave-port index
  //   MstId[SlvIdWidth-1 : 0]                  = per-slave AXI id (always 0)
  //
  // Slave-port index assignments:
  //   0 = fpga_mst, 1..4 = dfetch[0..3], 5 = mfetch, 6 = bsfetch
  //
  // Wire ID encoding:
  //   BURST_READ : 0 = metadata fetch (mfetch),   1 = bitstream fetch (bsfetch)
  //   READ       : 0..3 = dfetch[0..3] memory-port index
  //   WRITE      : 0..3 = dfetch[0..3] memory-port index
  // --------------------------------------------------------------------------
  localparam int unsigned XBAR_SLV_IDX_W = $clog2(axi4_xbar_pkg::NoMasters);

  logic [XBAR_SLV_IDX_W-1:0] xbar_ar_slv_idx, xbar_aw_slv_idx;
  assign xbar_ar_slv_idx = xbar_mem_req.ar.id[MstIdWidth-1 -: XBAR_SLV_IDX_W];
  assign xbar_aw_slv_idx = xbar_mem_req.aw.id[MstIdWidth-1 -: XBAR_SLV_IDX_W];

  // BURST_READ vs READ class for outgoing AR. Slave indices 5/6 are the
  // burst-read producers (mfetch, bsfetch). Indices 1..4 are dfetch ports.
  logic tx_ar_is_burst_li;
  logic [1:0] tx_arid_li, tx_awid_li;

  always_comb begin
    case (xbar_ar_slv_idx)
      XBAR_SLV_IDX_W'(5): begin
        tx_ar_is_burst_li = 1'b1;
        tx_arid_li        = 2'd0;  // metadata
      end
      XBAR_SLV_IDX_W'(6): begin
        tx_ar_is_burst_li = 1'b1;
        tx_arid_li        = 2'd1;  // bitstream
      end
      default: begin
        // dfetch[i] -> slv_idx i+1, link id = i (0..3)
        tx_ar_is_burst_li = 1'b0;
        tx_arid_li        = 2'(xbar_ar_slv_idx - XBAR_SLV_IDX_W'(1));
      end
    endcase
  end

  // dfetch is the only producer of writes through fpga_mem (mfetch/bsfetch
  // are read-only). Link id = dfetch port index.
  assign tx_awid_li = 2'(xbar_aw_slv_idx - XBAR_SLV_IDX_W'(1));

  // tid / eblock / regaddr come from pack_load_meta in mem_req_fifo:
  //   ar.user[AxiUserWidth-1]                                      = is_meta
  //   ar.user[DICE_REG_ADDR_WIDTH+DICE_EBLOCK_ID_WIDTH +: TID_W]   = tid
  //   ar.user[DICE_REG_ADDR_WIDTH                       +: EBL_W]  = eblock
  //   ar.user[0                                         +: REG_W]  = regaddr
  // These fields are only meaningful on the dfetch (single-read) path.
  localparam int unsigned LINK_TID_W = 4;
  logic [LINK_TID_W-1:0]            tx_ar_tid_li;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]  tx_ar_eblock_li;
  logic [DICE_REG_ADDR_WIDTH-1:0]   tx_ar_regaddr_li;

  assign tx_ar_tid_li     = xbar_mem_req.ar.user[DICE_REG_ADDR_WIDTH+DICE_EBLOCK_ID_WIDTH +: LINK_TID_W];
  assign tx_ar_eblock_li  = xbar_mem_req.ar.user[DICE_REG_ADDR_WIDTH                       +: DICE_EBLOCK_ID_WIDTH];
  assign tx_ar_regaddr_li = xbar_mem_req.ar.user[0                                         +: DICE_REG_ADDR_WIDTH];

  // R response decode: recover the slave-port index from the inline routing
  // tag and is_burst class flag carried in the READ_RESP header.
  logic                          rx_r_is_burst;
  logic [1:0]                    rx_rid_link;
  logic [XBAR_SLV_IDX_W-1:0]     rx_r_slv_idx;
  logic [MstIdWidth-1:0]         rx_r_id_expanded;

  always_comb begin
    if (rx_r_is_burst) begin
      // burst-read response: link_id[0] selects mfetch (5) vs bsfetch (6)
      rx_r_slv_idx = XBAR_SLV_IDX_W'(5) + {{(XBAR_SLV_IDX_W-1){1'b0}}, rx_rid_link[0]};
    end
    else begin
      // single-read response: link_id 0..3 -> dfetch slave idx 1..4
      rx_r_slv_idx = XBAR_SLV_IDX_W'(rx_rid_link) + XBAR_SLV_IDX_W'(1);
    end
  end

  assign rx_r_id_expanded = {rx_r_slv_idx, {SlvIdWidth{1'b0}}};

  // B response decode: B is locally synthesized in top_level_io and the
  // inline 2-bit link id is replayed on rx_bid; B traffic only ever comes
  // from dfetch ports, so the slave-idx is link_id + 1.
  logic [1:0]                    rx_bid_link;
  logic [XBAR_SLV_IDX_W-1:0]     rx_b_slv_idx;
  logic [MstIdWidth-1:0]         rx_b_id_expanded;

  assign rx_b_slv_idx     = XBAR_SLV_IDX_W'(rx_bid_link) + XBAR_SLV_IDX_W'(1);
  assign rx_b_id_expanded = {rx_b_slv_idx, {SlvIdWidth{1'b0}}};

  // tx_rid_i is the chip→FPGA READ_RESP id (responses to FPGA-host CSR
  // reads). The fpga_mst slave port stamps the AR id as 0 already; the
  // crossbar prepends slave-idx 0 -> r.id top bits = 0. Truncate to 2 bits.
  logic [1:0] tx_rid_li;
  assign tx_rid_li = fpga_mst_resp.r.id[1:0];

  logic tx_wready, tx_arready_link, tx_awready_link;
  logic rx_rvalid, rx_rlast;
  logic [DATA_WIDTH-1:0] rx_rdata;
  logic [           1:0] rx_rresp;
  logic                  rx_bvalid;
  logic [           1:0] rx_bresp;

  always_comb begin
    xbar_mem_resp          = '0;
    // Ready signals come from axi_link_tx (via top_level_io's AW gating).
    xbar_mem_resp.aw_ready = tx_awready_link;  // already gated for aw-id mirror inside top_level_io
    xbar_mem_resp.w_ready  = tx_wready;
    xbar_mem_resp.ar_ready = tx_arready_link;
    // R response from axi_link_rx, ID expanded from inline routing tag.
    xbar_mem_resp.r_valid  = rx_rvalid;
    xbar_mem_resp.r.data   = axi_data_t'(rx_rdata);
    xbar_mem_resp.r.resp   = rx_rresp;
    xbar_mem_resp.r.last   = rx_rlast;
    xbar_mem_resp.r.id     = rx_r_id_expanded;
    // B response locally synthesized by top_level_io; ID expanded from
    // its inline mirror.
    xbar_mem_resp.b_valid  = rx_bvalid;
    xbar_mem_resp.b.resp   = rx_bresp;
    xbar_mem_resp.b.id     = rx_b_id_expanded;
  end

  // --------------------------------------------------------------------------
  // top_level_io — AXI packetizer/depacketizer around core-side link streams.
  //   TX path: crossbar AW/W/AR -> axi_link_tx -> link_tx_*
  //   RX path: link_rx_* -> axi_link_rx -> R/B to crossbar
  // --------------------------------------------------------------------------
  top_level_io #(
      .flit_width_p                   (FLIT_WIDTH),
      .addr_width_p                   (ADDR_WIDTH),
      .channel_width_p                (CHANNEL_WIDTH),
      .num_channels_p                 (1),
      .lg_fifo_depth_p                (LG_FIFO_DEPTH),
      .lg_credit_to_token_decimation_p(LG_CREDIT_TO_TOKEN_DEC),
      .bypass_twofer_fifo_p           (BYPASS_TWOFER_FIFO),
      .bypass_gearbox_p               (BYPASS_GEARBOX),
      .use_hardened_fifo_p            (USE_HARDENED_FIFO),
      // RX FIFO sizes — large R data FIFO so full bitstream / meta bursts
      // (up to 54 / 16 beats) can be received without backpressuring the link.
      .rx_link_fifo_els_p             (8),
      .rx_aw_desc_fifo_els_p          (2),
      .rx_ar_desc_fifo_els_p          (2),
      .rx_w_len_fifo_els_p            (4),
      .rx_w_data_fifo_els_p           (8),
      .rx_r_len_fifo_els_p            (4),
      .rx_r_data_fifo_els_p           (8),
      // TX FIFO sizes
      .tx_link_fifo_els_p             (8),
      .tx_aw_desc_fifo_els_p          (2),
      .tx_ar_desc_fifo_els_p          (2),
      .tx_w_len_fifo_els_p            (4),
      .tx_w_data_fifo_els_p           (8),
      .tx_r_len_fifo_els_p            (4),
      .tx_r_data_fifo_els_p           (8),
      .tx_pkt_order_fifo_els_p        (8)
  ) u_top_level_io (
      .core_clk_i                (clk_i),
      .reset_i                   (rst_i),
      // Core-side bsg_link streams.
      .link_rx_data_i            (link_rx_data_i),
      .link_rx_valid_i           (link_rx_valid_i),
      .link_rx_yumi_o            (link_rx_yumi_o),
      .link_tx_data_o            (link_tx_data_o),
      .link_tx_valid_o           (link_tx_valid_o),
      .link_tx_ready_i           (link_tx_ready_i),
      // TX: chip → FPGA SRAM (AW/W/AR requests)
      .tx_awvalid_i              (xbar_mem_req.aw_valid),
      .tx_awready_o              (tx_awready_link),
      .tx_awaddr_i               (xbar_mem_req.aw.addr[ADDR_WIDTH-1:0]),
      .tx_awlen_i                (xbar_mem_req.aw.len),
      .tx_awsize_i               (xbar_mem_req.aw.size),
      .tx_awburst_i              (xbar_mem_req.aw.burst),
      .tx_awid_i                 (tx_awid_li),
      .tx_wvalid_i               (xbar_mem_req.w_valid),
      .tx_wready_o               (tx_wready),
      .tx_wdata_i                (xbar_mem_req.w.data[DATA_WIDTH-1:0]),
      .tx_wlast_i                (xbar_mem_req.w.last),
      .tx_arvalid_i              (xbar_mem_req.ar_valid),
      .tx_arready_o              (tx_arready_link),
      .tx_araddr_i               (xbar_mem_req.ar.addr[ADDR_WIDTH-1:0]),
      .tx_arlen_i                (xbar_mem_req.ar.len),
      .tx_arsize_i               (xbar_mem_req.ar.size),
      .tx_arburst_i              (xbar_mem_req.ar.burst),
      .tx_ar_is_burst_i          (tx_ar_is_burst_li),
      .tx_arid_i                 (tx_arid_li),
      .tx_ar_tid_i               (tx_ar_tid_li),
      .tx_ar_eblock_i            (tx_ar_eblock_li),
      .tx_ar_regaddr_i           (tx_ar_regaddr_li),
      // TX: R/B from crossbar fpga_mst slave port → FPGA host
      .tx_rvalid_i               (fpga_mst_resp.r_valid),
      .tx_rready_o               (tx_fpga_rready),
      .tx_rdata_i                (fpga_mst_resp.r.data[DATA_WIDTH-1:0]),
      .tx_rresp_i                (fpga_mst_resp.r.resp),
      .tx_rlast_i                (fpga_mst_resp.r.last),
      .tx_rid_i                  (tx_rid_li),
      .tx_bvalid_i               (fpga_mst_resp.b_valid),
      .tx_bready_o               (tx_fpga_bready),
      .tx_bresp_i                (fpga_mst_resp.b.resp),
      // RX: R/B responses FPGA SRAM → crossbar fpga_mem port (ID expanded
      // from the inline routing tag carried in the response header).
      .rx_rvalid_o               (rx_rvalid),
      .rx_rready_i               (xbar_mem_req.r_ready),
      .rx_rdata_o                (rx_rdata),
      .rx_rresp_o                (rx_rresp),
      .rx_rlast_o                (rx_rlast),
      .rx_rid_o                  (rx_rid_link),
      .rx_r_is_burst_o           (rx_r_is_burst),
      .rx_bvalid_o               (rx_bvalid),
      .rx_bready_i               (xbar_mem_req.b_ready),
      .rx_bresp_o                (rx_bresp),
      .rx_bid_o                  (rx_bid_link),
      // RX: AW/W/AR from FPGA host → crossbar fpga_mst slave port
      .rx_awvalid_o              (rx_fpga_awvalid),
      .rx_awready_i              (fpga_mst_resp.aw_ready),
      .rx_awaddr_o               (rx_fpga_awaddr),
      .rx_awlen_o                (rx_fpga_awlen),
      .rx_awsize_o               (rx_fpga_awsize),
      .rx_awburst_o              (rx_fpga_awburst),
      .rx_awid_o                 (rx_fpga_awid),
      .rx_wvalid_o               (rx_fpga_wvalid),
      .rx_wready_i               (fpga_mst_resp.w_ready),
      .rx_wdata_o                (rx_fpga_wdata),
      .rx_wlast_o                (rx_fpga_wlast),
      .rx_arvalid_o              (rx_fpga_arvalid),
      .rx_arready_i              (fpga_mst_resp.ar_ready),
      .rx_araddr_o               (rx_fpga_araddr),
      .rx_arlen_o                (rx_fpga_arlen),
      .rx_arsize_o               (rx_fpga_arsize),
      .rx_arburst_o              (rx_fpga_arburst),
      .rx_ar_is_burst_o          (rx_fpga_ar_is_burst),
      .rx_arid_o                 (rx_fpga_arid),
      .rx_ar_tid_o               (rx_fpga_ar_tid),
      .rx_ar_eblock_o            (rx_fpga_ar_eblock),
      .rx_ar_regaddr_o           (rx_fpga_ar_regaddr)
  );

  // --------------------------------------------------------------------------
  // Full AXI4 crossbar
  // --------------------------------------------------------------------------
  axi4_full_crossbar u_xbar (
      .clk_i          (clk_i),
      .rst_i          (rst_i),
      .test_i         (1'b0),
      .fpga_mst_req_i (fpga_mst_req),
      .fpga_mst_resp_o(fpga_mst_resp),
      .dfetch0_req_i  (dfetch_req[0]),
      .dfetch0_resp_o (dfetch_resp[0]),
      .dfetch1_req_i  (dfetch_req[1]),
      .dfetch1_resp_o (dfetch_resp[1]),
      .dfetch2_req_i  (dfetch_req[2]),
      .dfetch2_resp_o (dfetch_resp[2]),
      .dfetch3_req_i  (dfetch_req[3]),
      .dfetch3_resp_o (dfetch_resp[3]),
      .mfetch_req_i   (mfetch_req),
      .mfetch_resp_o  (mfetch_resp),
      .bsfetch_req_i  (bsfetch_req),
      .bsfetch_resp_o (bsfetch_resp),
      .fpga_mem_req_o (xbar_mem_req),
      .fpga_mem_resp_i(xbar_mem_resp),
      .cgra_csr_req_o (cgra_csr_req_o),
      .cgra_csr_resp_i(cgra_csr_resp_i)
  );

endmodule : cgra_io_axi4_top