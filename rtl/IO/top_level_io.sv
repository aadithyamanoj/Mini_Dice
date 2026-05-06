module top_level_io
  #(parameter int flit_width_p         = 32
   ,parameter int addr_width_p         = 16
   ,parameter int data_width_p         = 32
   ,parameter int channel_width_p      = 16
   ,parameter int num_channels_p       = 1
   ,parameter int lg_fifo_depth_p      = 6
   ,parameter int lg_credit_to_token_decimation_p = 3
   ,parameter int use_extra_data_bit_p = 0
   ,parameter int use_encode_p         = 0
   ,parameter int bypass_twofer_fifo_p = 0
   ,parameter int bypass_gearbox_p     = 0
   ,parameter int use_hardened_fifo_p  = 0
   ,parameter int rx_link_fifo_els_p   = 8
   ,parameter int rx_aw_desc_fifo_els_p = 2
   ,parameter int rx_ar_desc_fifo_els_p = 2
   ,parameter int rx_w_len_fifo_els_p  = 4
   ,parameter int rx_w_data_fifo_els_p = 8
   ,parameter int rx_r_len_fifo_els_p  = 4
   ,parameter int rx_r_data_fifo_els_p = 8
   ,parameter int tx_link_fifo_els_p   = 8
   ,parameter int tx_aw_desc_fifo_els_p = 2
   ,parameter int tx_ar_desc_fifo_els_p = 2
   ,parameter int tx_w_len_fifo_els_p  = 4
   ,parameter int tx_w_data_fifo_els_p = 8
   ,parameter int tx_r_len_fifo_els_p  = 4
   ,parameter int tx_r_data_fifo_els_p = 8
   ,parameter int tx_pkt_order_fifo_els_p = 8
   // Depth of the locally-synthesized fake-B counter. Sized for the max
   // number of in-flight write bursts the upstream master can have
   // outstanding before pulsing bready; 16 is generous for any AXI master
   // we expect to see here.
   ,parameter int fake_b_max_outstanding_p = 16
   )
  (input  logic                                          core_clk_i
   ,input logic                                          reset_i

   // bsg_link upstream reset/control.
   ,input  logic                                         io_master_clk_i
   ,input  logic                                         upstream_io_link_reset_i
   ,input  logic                                         async_token_reset_i
   ,input  logic [num_channels_p-1:0]                    token_clk_i

   // bsg_link downstream reset/control.
   ,input  logic [num_channels_p-1:0]                    downstream_io_link_reset_i
   ,input  logic [num_channels_p-1:0]                    downstream_io_clk_i
   ,input  logic [num_channels_p*channel_width_p-1:0]    downstream_io_data_i
   ,input  logic [num_channels_p-1:0]                    downstream_io_valid_i

   // Physical outputs driven by upstream link.
   ,output logic [num_channels_p-1:0]                    upstream_io_clk_r_o
   ,output logic [num_channels_p*channel_width_p-1:0]    upstream_io_data_r_o
   ,output logic [num_channels_p-1:0]                    upstream_io_valid_r_o

   // Tokens driven by downstream link.
   ,output logic [num_channels_p-1:0]                    downstream_core_token_r_o

   // RX side toward local AXI crossbar/sinks.
   ,output logic                                         rx_awvalid_o
   ,input  logic                                         rx_awready_i
   ,output logic [addr_width_p-1:0]                      rx_awaddr_o
   ,output logic [7:0]                                   rx_awlen_o
   ,output logic [2:0]                                   rx_awsize_o
   ,output logic [1:0]                                   rx_awburst_o

   ,output logic                                         rx_wvalid_o
   ,input  logic                                         rx_wready_i
   ,output logic [data_width_p-1:0]                      rx_wdata_o
   ,output logic                                         rx_wlast_o

   ,output logic                                         rx_arvalid_o
   ,input  logic                                         rx_arready_i
   ,output logic [addr_width_p-1:0]                      rx_araddr_o
   ,output logic [7:0]                                   rx_arlen_o
   ,output logic [2:0]                                   rx_arsize_o
   ,output logic [1:0]                                   rx_arburst_o
   ,output logic [13:0]                                  rx_aruser_o

   ,output logic                                         rx_rvalid_o
   ,input  logic                                         rx_rready_i
   ,output logic [data_width_p-1:0]                      rx_rdata_o
   ,output logic [1:0]                                   rx_rresp_o
   ,output logic                                         rx_rlast_o

   ,output logic                                         rx_bvalid_o
   ,input  logic                                         rx_bready_i
   ,output logic [1:0]                                   rx_bresp_o

   // TX side from local AXI crossbar/sources.
   ,input  logic                                         tx_awvalid_i
   ,output logic                                         tx_awready_o
   ,input  logic [addr_width_p-1:0]                      tx_awaddr_i
   ,input  logic [7:0]                                   tx_awlen_i
   ,input  logic [2:0]                                   tx_awsize_i
   ,input  logic [1:0]                                   tx_awburst_i

   ,input  logic                                         tx_wvalid_i
   ,output logic                                         tx_wready_o
   ,input  logic [data_width_p-1:0]                      tx_wdata_i
   ,input  logic                                         tx_wlast_i

   ,input  logic                                         tx_arvalid_i
   ,output logic                                         tx_arready_o
   ,input  logic [addr_width_p-1:0]                      tx_araddr_i
   ,input  logic [7:0]                                   tx_arlen_i
   ,input  logic [2:0]                                   tx_arsize_i
   ,input  logic [1:0]                                   tx_arburst_i
   ,input  logic [13:0]                                  tx_aruser_i

   ,input  logic                                         tx_rvalid_i
   ,output logic                                         tx_rready_o
   ,input  logic [data_width_p-1:0]                      tx_rdata_i
   ,input  logic [1:0]                                   tx_rresp_i
   ,input  logic                                         tx_rlast_i

   ,input  logic                                         tx_bvalid_i
   ,output logic                                         tx_bready_o
   ,input  logic [1:0]                                   tx_bresp_i
   );

  // --------------------------------------------------------------------------
  // top_level_io
  // --------------------------------------------------------------------------
  // Full top-level IO subsystem:
  //   AXI source/sink side <-> axi_link_tx/rx <-> 32-bit core-side link flits
  //   <-> bsg_link_ddr_upstream/downstream <-> physical DDR/tokens
  //
  // The bsg_link blocks provide the actual source-synchronous DDR physical
  // transport. axi_link_tx and axi_link_rx sit directly on the 32-bit core-side
  // ready/valid boundary exported by those bsg_link blocks.
  //
  // Ordering model:
  //   Still strict FIFO only. No AXI IDs or reorder logic are introduced here.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32)
      $error("top_level_io requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("top_level_io requires addr_width_p=16, got %0d", addr_width_p);
    if (data_width_p != 32)
      $error("top_level_io requires data_width_p=32, got %0d", data_width_p);
  end

  logic [flit_width_p-1:0] link_rx_core_data_lo;
  logic                    link_rx_core_valid_lo;
  logic                    link_rx_core_yumi_li;

  logic [flit_width_p-1:0] link_tx_core_data_li;
  logic                    link_tx_core_valid_li;
  logic                    link_tx_core_ready_lo;
  logic                    rx_arready_li;
  logic                    tx_r_len_v_lo;
  logic [7:0]              tx_r_len_lo;
  logic                    tx_r_len_yumi_li;
  logic                    tx_r_len_ready_lo;

  logic [num_channels_p-1:0][channel_width_p-1:0] downstream_io_data_li;
  logic [num_channels_p-1:0][channel_width_p-1:0] upstream_io_data_lo;

  for (genvar ch = 0; ch < num_channels_p; ch++) begin : phys_bus
    assign downstream_io_data_li[ch] =
      downstream_io_data_i[ch*channel_width_p +: channel_width_p];
    assign upstream_io_data_r_o[ch*channel_width_p +: channel_width_p] =
      upstream_io_data_lo[ch];
  end

  bsg_link_ddr_downstream #(
    .width_p                        (flit_width_p),
    .channel_width_p                (channel_width_p),
    .num_channels_p                 (num_channels_p),
    .lg_fifo_depth_p                (lg_fifo_depth_p),
    .lg_credit_to_token_decimation_p(lg_credit_to_token_decimation_p),
    .use_extra_data_bit_p           (use_extra_data_bit_p),
    .use_encode_p                   (use_encode_p),
    .bypass_twofer_fifo_p           (bypass_twofer_fifo_p),
    .bypass_gearbox_p               (bypass_gearbox_p),
    .use_hardened_fifo_p            (use_hardened_fifo_p)
  ) link_downstream_i (
    .core_clk_i        (core_clk_i),
    .core_link_reset_i (reset_i),
    .io_link_reset_i   (downstream_io_link_reset_i),
    .core_data_o       (link_rx_core_data_lo),
    .core_valid_o      (link_rx_core_valid_lo),
    .core_yumi_i       (link_rx_core_yumi_li),
    .io_clk_i          (downstream_io_clk_i),
    .io_data_i         (downstream_io_data_li),
    .io_valid_i        (downstream_io_valid_i),
    .core_token_r_o    (downstream_core_token_r_o)
  );

  // Incoming READ_REQ lengths are mirrored into a small FIFO so the local
  // AXI R channel can start streaming a READ_RESP packet back over the link
  // on the very first response beat.
  assign rx_arready_li = rx_arready_i && tx_r_len_ready_lo;

  bsg_fifo_1r1w_small #(
    .width_p            (8),
    .els_p              (tx_r_len_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
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
    .flit_width_p       (flit_width_p),
    .addr_width_p       (addr_width_p),
    .link_fifo_els_p    (rx_link_fifo_els_p),
    .aw_desc_fifo_els_p (rx_aw_desc_fifo_els_p),
    .ar_desc_fifo_els_p (rx_ar_desc_fifo_els_p),
    .w_len_fifo_els_p   (rx_w_len_fifo_els_p),
    .w_data_fifo_els_p  (rx_w_data_fifo_els_p),
    .r_len_fifo_els_p   (rx_r_len_fifo_els_p),
    .r_data_fifo_els_p  (rx_r_data_fifo_els_p)
  ) axi_link_rx_i (
    .clk_i          (core_clk_i),
    .reset_i        (reset_i),
    .link_rx_v_i    (link_rx_core_valid_lo),
    .link_rx_data_i (link_rx_core_data_lo),
    .link_rx_yumi_o (link_rx_core_yumi_li),
    .awvalid_o      (rx_awvalid_o),
    .awready_i      (rx_awready_i),
    .awaddr_o       (rx_awaddr_o),
    .awlen_o        (rx_awlen_o),
    .awsize_o       (rx_awsize_o),
    .awburst_o      (rx_awburst_o),
    .wvalid_o       (rx_wvalid_o),
    .wready_i       (rx_wready_i),
    .wdata_o        (rx_wdata_o),
    .wlast_o        (rx_wlast_o),
    .arvalid_o      (rx_arvalid_o),
    .arready_i      (rx_arready_li),
    .araddr_o       (rx_araddr_o),
    .arlen_o        (rx_arlen_o),
    .arsize_o       (rx_arsize_o),
    .arburst_o      (rx_arburst_o),
    .aruser_o       (rx_aruser_o),
    .rvalid_o       (rx_rvalid_o),
    .rready_i       (rx_rready_i),
    .rdata_o        (rx_rdata_o),
    .rresp_o        (rx_rresp_o),
    .rlast_o        (rx_rlast_o)
  );

  axi_link_tx #(
    .flit_width_p         (flit_width_p),
    .addr_width_p         (addr_width_p),
    .link_fifo_els_p      (tx_link_fifo_els_p),
    .aw_desc_fifo_els_p   (tx_aw_desc_fifo_els_p),
    .ar_desc_fifo_els_p   (tx_ar_desc_fifo_els_p),
    .w_len_fifo_els_p     (tx_w_len_fifo_els_p),
    .w_data_fifo_els_p    (tx_w_data_fifo_els_p),
    .r_len_fifo_els_p     (tx_r_len_fifo_els_p),
    .r_data_fifo_els_p    (tx_r_data_fifo_els_p),
    .pkt_order_fifo_els_p (tx_pkt_order_fifo_els_p)
  ) axi_link_tx_i (
    .clk_i          (core_clk_i),
    .reset_i        (reset_i),
    .awvalid_i      (tx_awvalid_i),
    .awready_o      (tx_awready_o),
    .awaddr_i       (tx_awaddr_i),
    .awlen_i        (tx_awlen_i),
    .awsize_i       (tx_awsize_i),
    .awburst_i      (tx_awburst_i),
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
    .aruser_i       (tx_aruser_i),
    .rvalid_i       (tx_rvalid_i),
    .rready_o       (tx_rready_o),
    .rdata_i        (tx_rdata_i),
    .rresp_i        (tx_rresp_i),
    .rlast_i        (tx_rlast_i),
    .tx_r_len_v_i   (tx_r_len_v_lo),
    .tx_r_len_i     (tx_r_len_lo),
    .tx_r_len_yumi_o(tx_r_len_yumi_li),
    .link_tx_v_o    (link_tx_core_valid_li),
    .link_tx_data_o (link_tx_core_data_li),
    .link_tx_ready_i(link_tx_core_ready_lo)
  );

  // --------------------------------------------------------------------------
  // B-channel handling without WRITE_RESP packets
  // --------------------------------------------------------------------------
  // The link no longer carries WRITE_RESP, so each accepted write must get
  // its B beat synthesized locally:
  //
  //   * Master-facing rx_b* (chip-as-master writes going out via axi_link_tx):
  //     A counter tracks every WLAST accepted on tx_w*. While the counter is
  //     non-zero we present a B beat on rx_bvalid_o; the counter decrements
  //     on each rx_b handshake. BRESP is hard-coded to OKAY because the
  //     real slave's response is not visible here — write errors cannot be
  //     reported back to the master. Strict-FIFO ordering on the link still
  //     guarantees that any read-after-write the master issues after seeing
  //     fake B reaches the slave after the corresponding WRITE_REQ.
  //
  //   * Slave-facing tx_b* (chip-as-slave write responses from local AXI):
  //     The local slave still emits a real B per accepted AW. We hold
  //     tx_bready_o high so the slave never stalls, and the response is
  //     silently discarded — it has no path across the link.
  //
  // The far end of the link must perform the symmetric trick on its own
  // master/slave sides. Both ends must agree to drop WRITE_RESP, otherwise
  // a stale link from the previous protocol would deadlock.

  localparam int fake_b_count_width_lp =
      (fake_b_max_outstanding_p <= 1) ? 1 : $clog2(fake_b_max_outstanding_p + 1);

  logic                              fake_b_push, fake_b_pop;
  logic [fake_b_count_width_lp-1:0]  fake_b_count_r, fake_b_count_n;

  assign fake_b_push = tx_wvalid_i && tx_wready_o && tx_wlast_i;
  assign fake_b_pop  = rx_bvalid_o && rx_bready_i;

  always_comb begin
    fake_b_count_n = fake_b_count_r;
    case ({fake_b_push, fake_b_pop})
      2'b10:   fake_b_count_n = fake_b_count_r + fake_b_count_width_lp'(1);
      2'b01:   fake_b_count_n = fake_b_count_r - fake_b_count_width_lp'(1);
      default: fake_b_count_n = fake_b_count_r;
    endcase
  end

  always_ff @(posedge core_clk_i) begin
    if (reset_i) fake_b_count_r <= '0;
    else         fake_b_count_r <= fake_b_count_n;
  end

  assign rx_bvalid_o = (fake_b_count_r != '0);
  assign rx_bresp_o  = 2'b00;  // OKAY — slave error codes are not observable

  // Permanently accept the local slave's B response and drop it.
  assign tx_bready_o = 1'b1;

  bsg_link_ddr_upstream #(
    .width_p                        (flit_width_p),
    .channel_width_p                (channel_width_p),
    .num_channels_p                 (num_channels_p),
    .lg_fifo_depth_p                (lg_fifo_depth_p),
    .lg_credit_to_token_decimation_p(lg_credit_to_token_decimation_p),
    .use_extra_data_bit_p           (use_extra_data_bit_p),
    .use_encode_p                   (use_encode_p),
    .bypass_twofer_fifo_p           (bypass_twofer_fifo_p),
    .bypass_gearbox_p               (bypass_gearbox_p)
  ) link_upstream_i (
    .core_clk_i         (core_clk_i),
    .core_link_reset_i  (reset_i),
    .core_data_i        (link_tx_core_data_li),
    .core_valid_i       (link_tx_core_valid_li),
    .core_ready_o       (link_tx_core_ready_lo),
    .io_clk_i           (io_master_clk_i),
    .io_link_reset_i    (upstream_io_link_reset_i),
    .async_token_reset_i(async_token_reset_i),
    .io_clk_r_o         (upstream_io_clk_r_o),
    .io_data_r_o        (upstream_io_data_lo),
    .io_valid_r_o       (upstream_io_valid_r_o),
    .token_clk_i        (token_clk_i)
  );

endmodule
