module top_level_io #(
      parameter int flit_width_p                    = 32
    , parameter int addr_width_p                    = 16
    , parameter int data_width_p                    = 32
    , parameter int channel_width_p                 = 16
    , parameter int num_channels_p                  = 1
    , parameter int lg_fifo_depth_p                 = 6
    , parameter int lg_credit_to_token_decimation_p = 3
    , parameter int use_extra_data_bit_p            = 0
    , parameter int use_encode_p                    = 0
    , parameter int bypass_twofer_fifo_p            = 0
    , parameter int bypass_gearbox_p                = 0
    , parameter int use_hardened_fifo_p             = 0
    , parameter int rx_link_fifo_els_p              = 4
    , parameter int rx_aw_desc_fifo_els_p           = 2
    , parameter int rx_ar_desc_fifo_els_p           = 2
    , parameter int rx_w_len_fifo_els_p             = 4
    , parameter int rx_w_data_fifo_els_p            = 4
    , parameter int rx_r_len_fifo_els_p             = 4
    , parameter int rx_r_data_fifo_els_p            = 4
    , parameter int tx_link_fifo_els_p              = 4
    , parameter int tx_aw_desc_fifo_els_p           = 2
    , parameter int tx_ar_desc_fifo_els_p           = 2
    , parameter int tx_w_len_fifo_els_p             = 4
    , parameter int tx_w_data_fifo_els_p            = 4
    , parameter int tx_r_len_fifo_els_p             = 4
    , parameter int tx_r_data_fifo_els_p            = 4
    , parameter int tx_pkt_order_fifo_els_p         = 4
    // Depth of the locally-synthesized fake-B counter. Sized for the max
    // number of in-flight write bursts the upstream master can have
    // outstanding before pulsing bready.
    , parameter int fake_b_max_outstanding_p        = 16
) (
      input logic core_clk_i
    , input logic reset_i

    // Core-side stream from the external bsg_link wrapper.
    , input  logic [flit_width_p-1:0] link_rx_data_i
    , input  logic                    link_rx_valid_i
    , output logic                    link_rx_yumi_o

    // Core-side stream to the external bsg_link wrapper.
    , output logic [flit_width_p-1:0] link_tx_data_o
    , output logic                    link_tx_valid_o
    , input  logic                    link_tx_ready_i

    // RX side toward local AXI crossbar/sinks.
    , output logic                    rx_awvalid_o
    , input  logic                    rx_awready_i
    , output logic [addr_width_p-1:0] rx_awaddr_o
    , output logic [             7:0] rx_awlen_o
    , output logic [             2:0] rx_awsize_o
    , output logic [             1:0] rx_awburst_o
    , output logic [             1:0] rx_awid_o

    , output logic                    rx_wvalid_o
    , input  logic                    rx_wready_i
    , output logic [data_width_p-1:0] rx_wdata_o
    , output logic                    rx_wlast_o

    , output logic                    rx_arvalid_o
    , input  logic                    rx_arready_i
    , output logic [addr_width_p-1:0] rx_araddr_o
    , output logic [             7:0] rx_arlen_o
    , output logic [             2:0] rx_arsize_o
    , output logic [             1:0] rx_arburst_o
    , output logic                    rx_ar_is_burst_o
    , output logic [             1:0] rx_arid_o
    , output logic [             3:0] rx_ar_tid_o
    , output logic [             2:0] rx_ar_eblock_o
    , output logic [             4:0] rx_ar_regaddr_o

    , output logic                    rx_rvalid_o
    , input  logic                    rx_rready_i
    , output logic [data_width_p-1:0] rx_rdata_o
    , output logic [             1:0] rx_rresp_o
    , output logic                    rx_rlast_o
    , output logic [             1:0] rx_rid_o
    , output logic                    rx_r_is_burst_o

    , output logic       rx_bvalid_o
    , input  logic       rx_bready_i
    , output logic [1:0] rx_bresp_o
    , output logic [1:0] rx_bid_o

    // TX side from local AXI crossbar/sources.
    , input  logic                    tx_awvalid_i
    , output logic                    tx_awready_o
    , input  logic [addr_width_p-1:0] tx_awaddr_i
    , input  logic [             7:0] tx_awlen_i
    , input  logic [             2:0] tx_awsize_i
    , input  logic [             1:0] tx_awburst_i
    , input  logic [             1:0] tx_awid_i

    , input  logic                    tx_wvalid_i
    , output logic                    tx_wready_o
    , input  logic [data_width_p-1:0] tx_wdata_i
    , input  logic                    tx_wlast_i

    , input  logic                    tx_arvalid_i
    , output logic                    tx_arready_o
    , input  logic [addr_width_p-1:0] tx_araddr_i
    , input  logic [             7:0] tx_arlen_i
    , input  logic [             2:0] tx_arsize_i
    , input  logic [             1:0] tx_arburst_i
    , input  logic                    tx_ar_is_burst_i
    , input  logic [             1:0] tx_arid_i
    , input  logic [             3:0] tx_ar_tid_i
    , input  logic [             2:0] tx_ar_eblock_i
    , input  logic [             4:0] tx_ar_regaddr_i

    , input  logic                    tx_rvalid_i
    , output logic                    tx_rready_o
    , input  logic [data_width_p-1:0] tx_rdata_i
    , input  logic [             1:0] tx_rresp_i
    , input  logic                    tx_rlast_i
    , input  logic [             1:0] tx_rid_i

    , input  logic       tx_bvalid_i
    , output logic       tx_bready_o
    , input  logic [1:0] tx_bresp_i
);

  // --------------------------------------------------------------------------
  // top_level_io
  // --------------------------------------------------------------------------
  // Full top-level IO subsystem:
  //   AXI source/sink side <-> axi_link_tx/rx <-> 32-bit core-side link flits.
  //
  // The source-synchronous DDR bsg_link PHY lives outside this module, usually
  // at chip_top next to the pad ring. This block only packetizes/depacketizes
  // AXI traffic over the ready/valid flit stream.
  //
  // The link protocol does not carry WRITE_RESP packets. B responses are
  // synthesized locally for outgoing writes and discarded for incoming writes.
  //
  // Writes are single-beat only. The WRITE header has no wire length
  // field — it is implicit (single beat). axi_link_tx rejects AW unless
  // awlen_i=0, so upstream masters must issue single-beat writes; the
  // fake B counter therefore produces exactly one OKAY beat per accepted
  // write.
  //
  // The link also does not transport RRESP. tx_rresp_i is accepted from the
  // local AXI source and ignored (mirroring the dropped B channel), and
  // rx_rresp_o is driven to OKAY (2'b00) for every R beat by axi_link_rx.
  // Per-read error reporting is therefore lost end-to-end.
  //
  // Each request carries a small inline ID on the wire (2 bits for WRITE
  // and READ, 1 bit for BURST_READ) — see axi_link_tx.sv for the wire
  // layout. The IDs are routing tags the FPGA dispatcher uses to
  // demultiplex packets across its downstream FIFOs, and are echoed back
  // in the matching response packet so the upstream wrapper can stamp
  // them onto the local crossbar response-ID line. This retires the
  // chip-side AR-ID side FIFO that previously bridged the missing ID.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32) $error("top_level_io requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16) $error("top_level_io requires addr_width_p=16, got %0d", addr_width_p);
    if (data_width_p != 32) $error("top_level_io requires data_width_p=32, got %0d", data_width_p);
  end

  logic       rx_arready_li;
  logic       tx_r_len_v_lo;
  logic [7:0] tx_r_len_lo;
  logic       tx_r_len_yumi_li;
  logic       tx_r_len_ready_lo;
  logic       tx_awvalid_li;
  logic       tx_awready_link_lo;
  logic       aw_id_mirror_ready_lo;

  // AW is gated by the mirror FIFO so we never accept a write the local
  // fake-B path can't track.
  assign tx_awvalid_li = tx_awvalid_i && aw_id_mirror_ready_lo;
  assign tx_awready_o  = tx_awready_link_lo && aw_id_mirror_ready_lo;

  // Incoming read lengths (from both BURST_READ and READ packets) are
  // mirrored into a small FIFO so the local AXI R channel can start
  // streaming a READ_RESP packet back over the link on the very first
  // response beat. READ always produces arlen=0 (single-beat); BURST_READ
  // can carry up to 256 beats. WRITE does not feed this FIFO — writes are
  // single-beat only and never generate a read response.
  assign rx_arready_li = rx_arready_i && tx_r_len_ready_lo;

  bsg_fifo_1r1w_small #(
      .width_p           (8),
      .els_p             (tx_r_len_fifo_els_p),
      .harden_p          (0),
      .ready_THEN_valid_p(0)
  ) tx_r_len_fifo_i (
      .clk_i  (core_clk_i),
      .reset_i(reset_i),
      .v_i    (rx_arvalid_o && rx_arready_li),
      .data_i (rx_arlen_o),
      .ready_o(tx_r_len_ready_lo),
      .v_o    (tx_r_len_v_lo),
      .data_o (tx_r_len_lo),
      .yumi_i (tx_r_len_yumi_li)
  );

  axi_link_rx #(
      .flit_width_p      (flit_width_p),
      .addr_width_p      (addr_width_p),
      .link_fifo_els_p   (rx_link_fifo_els_p),
      .aw_desc_fifo_els_p(rx_aw_desc_fifo_els_p),
      .ar_desc_fifo_els_p(rx_ar_desc_fifo_els_p),
      .w_len_fifo_els_p  (rx_w_len_fifo_els_p),
      .w_data_fifo_els_p (rx_w_data_fifo_els_p),
      .r_len_fifo_els_p  (rx_r_len_fifo_els_p),
      .r_data_fifo_els_p (rx_r_data_fifo_els_p)
  ) axi_link_rx_i (
      .clk_i         (core_clk_i),
      .reset_i       (reset_i),
      .link_rx_v_i   (link_rx_valid_i),
      .link_rx_data_i(link_rx_data_i),
      .link_rx_yumi_o(link_rx_yumi_o),
      .awvalid_o     (rx_awvalid_o),
      .awready_i     (rx_awready_i),
      .awaddr_o      (rx_awaddr_o),
      .awlen_o       (rx_awlen_o),
      .awsize_o      (rx_awsize_o),
      .awburst_o     (rx_awburst_o),
      .awid_o        (rx_awid_o),
      .wvalid_o      (rx_wvalid_o),
      .wready_i      (rx_wready_i),
      .wdata_o       (rx_wdata_o),
      .wlast_o       (rx_wlast_o),
      .arvalid_o     (rx_arvalid_o),
      .arready_i     (rx_arready_li),
      .araddr_o      (rx_araddr_o),
      .arlen_o       (rx_arlen_o),
      .arsize_o      (rx_arsize_o),
      .arburst_o     (rx_arburst_o),
      .ar_is_burst_o (rx_ar_is_burst_o),
      .arid_o        (rx_arid_o),
      .ar_tid_o      (rx_ar_tid_o),
      .ar_eblock_o   (rx_ar_eblock_o),
      .ar_regaddr_o  (rx_ar_regaddr_o),
      .rvalid_o      (rx_rvalid_o),
      .rready_i      (rx_rready_i),
      .rdata_o       (rx_rdata_o),
      .rresp_o       (rx_rresp_o),
      .rlast_o       (rx_rlast_o),
      .rid_o         (rx_rid_o),
      .r_is_burst_o  (rx_r_is_burst_o)
  );

  axi_link_tx #(
      .flit_width_p        (flit_width_p),
      .addr_width_p        (addr_width_p),
      .link_fifo_els_p     (tx_link_fifo_els_p),
      .aw_desc_fifo_els_p  (tx_aw_desc_fifo_els_p),
      .ar_desc_fifo_els_p  (tx_ar_desc_fifo_els_p),
      .w_len_fifo_els_p    (tx_w_len_fifo_els_p),
      .w_data_fifo_els_p   (tx_w_data_fifo_els_p),
      .r_len_fifo_els_p    (tx_r_len_fifo_els_p),
      .r_data_fifo_els_p   (tx_r_data_fifo_els_p),
      .pkt_order_fifo_els_p(tx_pkt_order_fifo_els_p)
  ) axi_link_tx_i (
      .clk_i          (core_clk_i),
      .reset_i        (reset_i),
      .awvalid_i      (tx_awvalid_li),
      .awready_o      (tx_awready_link_lo),
      .awaddr_i       (tx_awaddr_i),
      .awlen_i        (tx_awlen_i),
      .awsize_i       (tx_awsize_i),
      .awburst_i      (tx_awburst_i),
      .awid_i         (tx_awid_i),
      .wvalid_i       (tx_wvalid_i),
      .wready_o       (tx_wready_o),
      .wdata_i        (tx_wdata_i),
      .wlast_i        (tx_wlast_i),
      .arvalid_i      (tx_arvalid_i),
      .arready_o      (tx_arready_o),
      .araddr_i       (tx_araddr_i),
      .arlen_i        (tx_arlen_i),
      .arsize_i       (tx_arsize_i),
      .arburst_i      (tx_arburst_i),
      .ar_is_burst_i  (tx_ar_is_burst_i),
      .arid_i         (tx_arid_i),
      .ar_tid_i       (tx_ar_tid_i),
      .ar_eblock_i    (tx_ar_eblock_i),
      .ar_regaddr_i   (tx_ar_regaddr_i),
      .rvalid_i       (tx_rvalid_i),
      .rready_o       (tx_rready_o),
      .rdata_i        (tx_rdata_i),
      .rresp_i        (tx_rresp_i),
      .rlast_i        (tx_rlast_i),
      .rid_i          (tx_rid_i),
      .tx_r_len_v_i   (tx_r_len_v_lo),
      .tx_r_len_i     (tx_r_len_lo),
      .tx_r_len_yumi_o(tx_r_len_yumi_li),
      .link_tx_v_o    (link_tx_valid_o),
      .link_tx_data_o (link_tx_data_o),
      .link_tx_ready_i(link_tx_ready_i)
  );

  // --------------------------------------------------------------------------
  // B-channel handling without WRITE_RESP packets
  // --------------------------------------------------------------------------
  // The link no longer carries WRITE_RESP, so each accepted outgoing write
  // gets a local OKAY B beat. Real B responses from the local slave are
  // accepted and dropped because there is no response packet to serialize.
  //
  // A small mirror FIFO captures tx_awid_i at AW-accept so the synthesized
  // B response can reproduce the routing-tag ID inline on rx_bid_o, in the
  // same way the link carries id inline on the request and on READ_RESP.
  // The wrapper consumes that 2-bit id and zero-extends it back into the
  // crossbar's wider master-side ID, retiring the chip-side AW-ID FIFO.
  // fake_b_count_r keeps the AXI B-after-WLAST ordering: B is not asserted
  // until at least one WLAST has been observed since the last B handshake.

  localparam int fake_b_count_width_lp = (fake_b_max_outstanding_p <= 1) ? 1 : $clog2(
      fake_b_max_outstanding_p + 1
  );

  logic fake_b_push, fake_b_pop;
  logic [fake_b_count_width_lp-1:0] fake_b_count_r, fake_b_count_n;

  assign fake_b_push = tx_wvalid_i && tx_wready_o && tx_wlast_i;
  assign fake_b_pop  = rx_bvalid_o && rx_bready_i;

  always_comb begin
    fake_b_count_n = fake_b_count_r;
    unique case ({
      fake_b_push, fake_b_pop
    })
      2'b10:   fake_b_count_n = fake_b_count_r + fake_b_count_width_lp'(1);
      2'b01:   fake_b_count_n = fake_b_count_r - fake_b_count_width_lp'(1);
      default: fake_b_count_n = fake_b_count_r;
    endcase
  end

  always_ff @(posedge core_clk_i) begin
    if (reset_i) fake_b_count_r <= '0;
    else fake_b_count_r <= fake_b_count_n;
  end

  logic aw_id_mirror_push, aw_id_mirror_pop;
  logic       aw_id_mirror_v_lo;
  logic [1:0] aw_id_mirror_data_lo;

  assign aw_id_mirror_push = tx_awvalid_li && tx_awready_link_lo;
  assign aw_id_mirror_pop  = fake_b_pop;

  bsg_fifo_1r1w_small #(
      .width_p           (2),
      .els_p             (fake_b_max_outstanding_p),
      .harden_p          (0),
      .ready_THEN_valid_p(0)
  ) aw_id_mirror_fifo_i (
      .clk_i  (core_clk_i),
      .reset_i(reset_i),
      .v_i    (aw_id_mirror_push),
      .data_i (tx_awid_i),
      .ready_o(aw_id_mirror_ready_lo),
      .v_o    (aw_id_mirror_v_lo),
      .data_o (aw_id_mirror_data_lo),
      .yumi_i (aw_id_mirror_pop)
  );

  assign rx_bvalid_o = (fake_b_count_r != '0) && aw_id_mirror_v_lo;
  assign rx_bresp_o  = 2'b00;
  assign rx_bid_o    = aw_id_mirror_data_lo;

  assign tx_bready_o = 1'b1;

endmodule
