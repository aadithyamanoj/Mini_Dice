module axi_link_tx
  #(parameter int flit_width_p          = 32
   ,parameter int addr_width_p          = 16
   ,parameter int link_fifo_els_p       = 8
   ,parameter int aw_desc_fifo_els_p    = 2
   ,parameter int ar_desc_fifo_els_p    = 2
   ,parameter int w_len_fifo_els_p      = 4
   ,parameter int w_data_fifo_els_p     = 8
   ,parameter int r_len_fifo_els_p      = 4
   ,parameter int r_data_fifo_els_p     = 8
   ,parameter int b_resp_fifo_els_p     = 4
   ,parameter int pkt_order_fifo_els_p  = 8
   )
  (input  logic                     clk_i
   ,input logic                     reset_i

   ,input  logic                    awvalid_i
   ,output logic                    awready_o
   ,input  logic [addr_width_p-1:0] awaddr_i
   ,input  logic [7:0]              awlen_i
   ,input  logic [2:0]              awsize_i
   ,input  logic [1:0]              awburst_i

   ,input  logic                    wvalid_i
   ,output logic                    wready_o
   ,input  logic [31:0]             wdata_i
   ,input  logic                    wlast_i

   ,input  logic                    arvalid_i
   ,output logic                    arready_o
   ,input  logic [addr_width_p-1:0] araddr_i
   ,input  logic [7:0]              arlen_i
   ,input  logic [2:0]              arsize_i
   ,input  logic [1:0]              arburst_i
   ,input  logic [13:0]             aruser_i

   ,input  logic                    rvalid_i
   ,output logic                    rready_o
   ,input  logic [31:0]             rdata_i
   ,input  logic [1:0]              rresp_i
   ,input  logic                    rlast_i
   ,input  logic                    tx_r_len_v_i
   ,input  logic [7:0]              tx_r_len_i
   ,output logic                    tx_r_len_yumi_o

   ,input  logic                    bvalid_i
   ,output logic                    bready_o
   ,input  logic [1:0]              bresp_i

   ,output logic                    link_tx_v_o
   ,output logic [flit_width_p-1:0] link_tx_data_o
   ,input  logic                    link_tx_ready_i
   );

  // --------------------------------------------------------------------------
  // Combined transport packets over a 32-bit flit link.
  //
  // Opcode mapping:
  //   3'b000 = WRITE_REQ
  //   3'b001 = READ_REQ
  //   3'b010 = READ_RESP
  //   3'b011 = WRITE_RESP
  //   3'b100 = META_REQ
  //
  // Header flit layout (32 bits):
  //   WRITE_REQ : [31:29] opcode, [28:16] length,        [15:0] address
  //   READ_REQ  : [31:29] opcode, [28:16] length,        [15:0] address
  //   META_REQ  : [31:29] opcode, [28:16] aruser_i[12:0],[15:0] address
  //               aruser_i[13] selects META_REQ over READ_REQ on AR
  //               acceptance (TX-side only — never serialized). The lower
  //               13 bits aruser_i[12:0] are carried verbatim in the
  //               middle field as opaque metadata. No payload follows.
  //   READ_RESP : [31:29] opcode, [28:16] length,        [15:2] reserved, [1:0] rresp
  //   WRITE_RESP: [31:29] opcode, [28:16] 1,             [15:0] 16'b0
  //
  // AXI semantics are preserved at the module boundary:
  //   requests  : AW, W, AR
  //   responses : R, B
  //
  // Transport:
  //   WRITE_REQ  = header(opcode,len,addr) + len W beats
  //   READ_REQ   = header(opcode,len,addr)
  //   META_REQ   = header(opcode,0,addr)
  //   READ_RESP  = header(opcode,len,rresp) + len R beats
  //   WRITE_RESP = header(opcode,1,0)      + padded BRESP flit
  //
  // Strict FIFO assumption:
  //   No AXI IDs or reorder logic exist here. Associations rely purely on
  //   strict FIFO order across accepted bursts and responses.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32)
      $error("axi_link_tx requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_tx requires addr_width_p=16, got %0d", addr_width_p);
  end

  typedef enum logic [2:0] {
    OP_WRITE_REQ  = 3'b000,
    OP_READ_REQ   = 3'b001,
    OP_READ_RESP  = 3'b010,
    OP_WRITE_RESP = 3'b011,
    OP_META_REQ   = 3'b100
  } pkt_opcode_e;

  typedef enum logic [1:0] {
    PKT_WR_REQ  = 2'd0,
    PKT_RD_REQ  = 2'd1,
    PKT_RD_RESP = 2'd2,
    PKT_WR_RESP = 2'd3
  } pkt_kind_e;

  typedef enum logic [2:0] {
    TX_IDLE    = 3'd0,
    TX_HEADER  = 3'd1,
    TX_DATA    = 3'd2,
    TX_RESP    = 3'd3
  } tx_state_e;

  localparam int beat_count_width_lp = 13;
  localparam int wr_desc_width_lp    = addr_width_p + beat_count_width_lp;
  localparam int rd_desc_width_lp    = addr_width_p + 1 + beat_count_width_lp;
  localparam int r_desc_width_lp     = beat_count_width_lp + 2;
  localparam logic [2:0] axi_size_lp   = 3'b010;
  localparam logic [1:0] axi_burst_lp  = 2'b01;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [beat_count_width_lp-1:0] beats;
  } req_desc_s;

  // For non-meta reads, `payload` carries the AXI burst length. For meta
  // reads, it carries the captured aruser_i[12:0] for transport to RX.
  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic                           is_meta;
    logic [beat_count_width_lp-1:0] payload;
  } rd_req_desc_s;

  typedef struct packed {
    logic [beat_count_width_lp-1:0] beats;
    logic [1:0]                     resp;
  } r_desc_s;

  // --------------------------------------------------------------------------
  // Internal FIFOs
  // --------------------------------------------------------------------------
  // `wr_desc_fifo_i` stores one combined write-request descriptor per AW burst.
  // `w_len_fifo_i` is the matching beat-count queue that lets the W channel
  // consume beats later in the same strict FIFO order without IDs.
  // `pkt_order_fifo_i` records only packet start order across request/response
  // classes; the serializer follows it exactly to preserve end-to-end order.

  logic                     wr_desc_push_v_li, wr_desc_push_ready_lo;
  logic [wr_desc_width_lp-1:0] wr_desc_push_data_li;
  logic                     wr_desc_v_lo, wr_desc_yumi_li;
  logic [wr_desc_width_lp-1:0] wr_desc_data_lo;

  logic                     rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [rd_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                     rd_desc_v_lo, rd_desc_yumi_li;
  logic [rd_desc_width_lp-1:0] rd_desc_data_lo;

  logic                        w_len_push_v_li, w_len_push_ready_lo;
  logic [beat_count_width_lp-1:0] w_len_push_data_li;
  logic                        w_len_v_lo, w_len_yumi_li;
  logic [beat_count_width_lp-1:0] w_len_data_lo;

  logic                     w_data_push_v_li, w_data_push_ready_lo;
  logic [31:0]              w_data_push_data_li;
  logic                     w_data_v_lo, w_data_yumi_li;
  logic [31:0]              w_data_lo;

  logic                     r_desc_push_v_li, r_desc_push_ready_lo;
  logic [r_desc_width_lp-1:0] r_desc_push_data_li;
  logic                     r_desc_v_lo, r_desc_yumi_li;
  logic [r_desc_width_lp-1:0] r_desc_data_lo;

  logic                     r_data_push_v_li, r_data_push_ready_lo;
  logic [31:0]              r_data_push_data_li;
  logic                     r_data_v_lo, r_data_yumi_li;
  logic [31:0]              r_data_lo;

  logic                     b_resp_push_v_li, b_resp_push_ready_lo;
  logic [1:0]               b_resp_push_data_li;
  logic                     b_resp_v_lo, b_resp_yumi_li;
  logic [1:0]               b_resp_lo;

  logic                     pkt_order_push_v_li, pkt_order_push_ready_lo;
  logic [1:0]               pkt_order_push_data_li;
  logic                     pkt_order_v_lo, pkt_order_yumi_li;
  logic [1:0]               pkt_order_lo;

  bsg_fifo_1r1w_small #(
    .width_p            (wr_desc_width_lp),
    .els_p              (aw_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) wr_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (wr_desc_push_v_li),
    .data_i (wr_desc_push_data_li),
    .ready_o(wr_desc_push_ready_lo),
    .v_o    (wr_desc_v_lo),
    .data_o (wr_desc_data_lo),
    .yumi_i (wr_desc_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (rd_desc_width_lp),
    .els_p              (ar_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) rd_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (rd_desc_push_v_li),
    .data_i (rd_desc_push_data_li),
    .ready_o(rd_desc_push_ready_lo),
    .v_o    (rd_desc_v_lo),
    .data_o (rd_desc_data_lo),
    .yumi_i (rd_desc_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (beat_count_width_lp),
    .els_p              (w_len_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) w_len_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (w_len_push_v_li),
    .data_i (w_len_push_data_li),
    .ready_o(w_len_push_ready_lo),
    .v_o    (w_len_v_lo),
    .data_o (w_len_data_lo),
    .yumi_i (w_len_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (32),
    .els_p              (w_data_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) w_data_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (w_data_push_v_li),
    .data_i (w_data_push_data_li),
    .ready_o(w_data_push_ready_lo),
    .v_o    (w_data_v_lo),
    .data_o (w_data_lo),
    .yumi_i (w_data_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (r_desc_width_lp),
    .els_p              (r_len_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) r_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (r_desc_push_v_li),
    .data_i (r_desc_push_data_li),
    .ready_o(r_desc_push_ready_lo),
    .v_o    (r_desc_v_lo),
    .data_o (r_desc_data_lo),
    .yumi_i (r_desc_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (32),
    .els_p              (r_data_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) r_data_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (r_data_push_v_li),
    .data_i (r_data_push_data_li),
    .ready_o(r_data_push_ready_lo),
    .v_o    (r_data_v_lo),
    .data_o (r_data_lo),
    .yumi_i (r_data_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (2),
    .els_p              (b_resp_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) b_resp_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (b_resp_push_v_li),
    .data_i (b_resp_push_data_li),
    .ready_o(b_resp_push_ready_lo),
    .v_o    (b_resp_v_lo),
    .data_o (b_resp_lo),
    .yumi_i (b_resp_yumi_li)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (2),
    .els_p              (pkt_order_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) pkt_order_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (pkt_order_push_v_li),
    .data_i (pkt_order_push_data_li),
    .ready_o(pkt_order_push_ready_lo),
    .v_o    (pkt_order_v_lo),
    .data_o (pkt_order_lo),
    .yumi_i (pkt_order_yumi_li)
  );

  // --------------------------------------------------------------------------
  // Packet start arbitration
  // --------------------------------------------------------------------------
  // Only one new packet start is accepted per cycle. This keeps the packet
  // order FIFO unambiguous when several AXI channels become ready together.
  // The round-robin pointer avoids permanently favoring one class.

  logic [3:0] start_req, start_grant;
  logic [1:0] rr_start_r, rr_start_n;
  logic aw_req, ar_req, r_start_req, b_req;

  logic [beat_count_width_lp-1:0] aw_beats, ar_beats;
  logic [beat_count_width_lp-1:0] tx_r_beats_li;
  logic aw_ctrl_ok, ar_ctrl_ok;

  assign aw_beats   = {5'b0, awlen_i} + beat_count_width_lp'(1);
  assign ar_beats   = {5'b0, arlen_i} + beat_count_width_lp'(1);
  assign tx_r_beats_li = {5'b0, tx_r_len_i} + beat_count_width_lp'(1);
  assign aw_ctrl_ok = (awsize_i == axi_size_lp) && (awburst_i == axi_burst_lp) && (aw_beats != '0);
  assign ar_ctrl_ok = (arsize_i == axi_size_lp) && (arburst_i == axi_burst_lp) && (ar_beats != '0);

  logic r_capture_active_r, r_capture_active_n;
  logic [beat_count_width_lp-1:0] r_capture_beats_left_r, r_capture_beats_left_n;
  logic [1:0] r_capture_resp_r, r_capture_resp_n;
  logic [beat_count_width_lp-1:0] r_accept_loaded_beats;
  logic r_first_accept;

  assign aw_req      = awvalid_i && wr_desc_push_ready_lo && w_len_push_ready_lo && pkt_order_push_ready_lo && aw_ctrl_ok;
  assign ar_req      = arvalid_i && rd_desc_push_ready_lo && pkt_order_push_ready_lo && ar_ctrl_ok;
  assign r_start_req = rvalid_i && !r_capture_active_r
                       && tx_r_len_v_i && r_data_push_ready_lo && r_desc_push_ready_lo
                       && pkt_order_push_ready_lo;
  assign b_req       = bvalid_i && b_resp_push_ready_lo && pkt_order_push_ready_lo;

  assign start_req[pkt_kind_e'(PKT_WR_REQ)]  = aw_req;
  assign start_req[pkt_kind_e'(PKT_RD_REQ)]  = ar_req;
  assign start_req[pkt_kind_e'(PKT_RD_RESP)] = r_start_req;
  assign start_req[pkt_kind_e'(PKT_WR_RESP)] = b_req;

  integer start_scan_i;
  integer start_scan_idx;
  always_comb begin
    start_grant = '0;
    for (start_scan_i = 0; start_scan_i < 4; start_scan_i++) begin
      start_scan_idx = rr_start_r + start_scan_i;
      if (start_scan_idx >= 4)
        start_scan_idx = start_scan_idx - 4;
      if ((start_grant == '0) && start_req[start_scan_idx])
        start_grant[start_scan_idx] = 1'b1;
    end
  end

  always_comb begin
    rr_start_n = rr_start_r;
    if (start_grant != '0) begin
      if (start_grant[0]) rr_start_n = 2'd1;
      if (start_grant[1]) rr_start_n = 2'd2;
      if (start_grant[2]) rr_start_n = 2'd3;
      if (start_grant[3]) rr_start_n = 2'd0;
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i)
      rr_start_r <= '0;
    else
      rr_start_r <= rr_start_n;
  end

  // --------------------------------------------------------------------------
  // AXI request / response capture
  // --------------------------------------------------------------------------
  // AW acceptance creates a pending WRITE_REQ descriptor immediately, while the
  // corresponding W burst can arrive later and is matched purely by FIFO order.
  // This is safe only under the module's strict in-order, no-ID assumption.

  logic [beat_count_width_lp-1:0] w_accept_beats_left_r, w_accept_beats_left_n;
  logic [beat_count_width_lp-1:0] w_accept_loaded_beats;
  logic w_accept_active_r, w_accept_active_n;
  logic aw_accept, ar_accept, r_accept, b_accept, w_accept;
  logic r_final_accept;

  assign aw_accept = start_grant[pkt_kind_e'(PKT_WR_REQ)];
  assign ar_accept = start_grant[pkt_kind_e'(PKT_RD_REQ)];
  assign b_accept  = start_grant[pkt_kind_e'(PKT_WR_RESP)];

  assign awready_o = aw_accept;
  assign arready_o = ar_accept;
  assign bready_o  = b_accept;

  assign wr_desc_push_v_li    = aw_accept;
  assign wr_desc_push_data_li = {awaddr_i, aw_beats};
  assign w_len_push_v_li      = aw_accept;
  assign w_len_push_data_li   = aw_beats;
  assign pkt_order_push_v_li  = aw_accept || ar_accept || b_accept || (r_accept && !r_capture_active_r);
  assign pkt_order_push_data_li = aw_accept ? pkt_kind_e'(PKT_WR_REQ)
                                  : ar_accept ? pkt_kind_e'(PKT_RD_REQ)
                                  : (r_accept && !r_capture_active_r) ? pkt_kind_e'(PKT_RD_RESP)
                                  : pkt_kind_e'(PKT_WR_RESP);

  // aruser_i[13] selects META_REQ at the link layer (TX-only — not
  // serialized). For META_REQ the lower 13 bits aruser_i[12:0] are
  // captured into `payload` for transport; for READ_REQ `payload`
  // carries the beat count instead.
  assign rd_desc_push_v_li    = ar_accept;
  assign rd_desc_push_data_li = {araddr_i, aruser_i[13],
                                 aruser_i[13] ? aruser_i[12:0] : ar_beats};

  assign b_resp_push_v_li     = b_accept;
  assign b_resp_push_data_li  = bresp_i;

  assign w_accept_loaded_beats = w_accept_active_r ? w_accept_beats_left_r : w_len_data_lo;
  assign wready_o = w_data_push_ready_lo
                    && (w_accept_active_r || w_len_v_lo);
  assign w_accept = wvalid_i && wready_o;
  assign w_data_push_v_li    = w_accept;
  assign w_data_push_data_li = wdata_i;
  assign w_len_yumi_li       = w_accept && !w_accept_active_r;

  always_comb begin
    // `w_accept_active_r` tracks whether we are in the middle of consuming the
    // current burst's W beats. On the first beat we load the older AW length
    // from `w_len_fifo_i`; subsequent beats count down locally until WLAST.
    w_accept_active_n     = w_accept_active_r;
    w_accept_beats_left_n = w_accept_beats_left_r;

    if (w_accept) begin
      if (!w_accept_active_r) begin
        if (w_accept_loaded_beats == beat_count_width_lp'(1)) begin
          w_accept_active_n     = 1'b0;
          w_accept_beats_left_n = '0;
        end
        else begin
          w_accept_active_n     = 1'b1;
          w_accept_beats_left_n = w_accept_loaded_beats - beat_count_width_lp'(1);
        end
      end
      else if (w_accept_beats_left_r == beat_count_width_lp'(1)) begin
        w_accept_active_n     = 1'b0;
        w_accept_beats_left_n = '0;
      end
      else begin
        w_accept_beats_left_n = w_accept_beats_left_r - beat_count_width_lp'(1);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      w_accept_active_r     <= 1'b0;
      w_accept_beats_left_r <= '0;
    end
    else begin
      w_accept_active_r     <= w_accept_active_n;
      w_accept_beats_left_r <= w_accept_beats_left_n;
    end
  end

  assign rready_o = r_data_push_ready_lo
                    && (r_capture_active_r || start_grant[pkt_kind_e'(PKT_RD_RESP)]);
  assign r_accept = rvalid_i && rready_o;
  assign r_first_accept = r_accept && !r_capture_active_r;
  assign r_accept_loaded_beats = r_capture_active_r ? r_capture_beats_left_r : tx_r_beats_li;

  // R beats stream straight into `r_data_fifo_i`. The matching `{len,rresp}`
  // descriptor is emitted on the first beat using the stored AR length from
  // `top_level_io`, so the serializer can emit the READ_RESP header before the
  // full burst has completed.

  assign r_data_push_v_li    = r_accept;
  assign r_data_push_data_li = rdata_i;
  assign r_final_accept      = r_accept && (r_accept_loaded_beats == beat_count_width_lp'(1));
  assign r_desc_push_v_li    = r_first_accept;
  assign r_desc_push_data_li = {tx_r_beats_li, rresp_i};
  assign tx_r_len_yumi_o     = r_first_accept;

  always_comb begin
    r_capture_active_n     = r_capture_active_r;
    r_capture_beats_left_n = r_capture_beats_left_r;
    r_capture_resp_n       = r_capture_resp_r;

    if (r_accept) begin
      if (!r_capture_active_r) begin
        if (r_accept_loaded_beats == beat_count_width_lp'(1)) begin
          r_capture_active_n     = 1'b0;
          r_capture_beats_left_n = '0;
          r_capture_resp_n       = rresp_i;
        end
        else begin
          r_capture_active_n     = 1'b1;
          r_capture_beats_left_n = r_accept_loaded_beats - beat_count_width_lp'(1);
          r_capture_resp_n       = rresp_i;
        end
      end
      else if (r_capture_beats_left_r == beat_count_width_lp'(1)) begin
        r_capture_active_n     = 1'b0;
        r_capture_beats_left_n = '0;
      end
      else begin
        r_capture_beats_left_n = r_capture_beats_left_r - beat_count_width_lp'(1);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      r_capture_active_r     <= 1'b0;
      r_capture_beats_left_r <= '0;
      r_capture_resp_r       <= '0;
    end
    else begin
      r_capture_active_r     <= r_capture_active_n;
      r_capture_beats_left_r <= r_capture_beats_left_n;
      r_capture_resp_r       <= r_capture_resp_n;
    end
  end

  // --------------------------------------------------------------------------
  // Link serializer
  // --------------------------------------------------------------------------
  // The serializer is intentionally simple:
  //   TX_HEADER emits the 32-bit header flit {opcode, beats, addr}
  //   TX_DATA   streams W or R payload beats from the corresponding FIFO
  //   TX_RESP   emits the padded BRESP flit when required
  //
  // Only one packet is active at a time, and packet start order is supplied by
  // `pkt_order_fifo_i`, so no cross-packet reordering is possible.

  tx_state_e state_r, state_n;
  logic [1:0] cur_kind_r, cur_kind_n;
  logic [addr_width_p-1:0] cur_addr_r, cur_addr_n;
  logic [beat_count_width_lp-1:0] cur_beats_r, cur_beats_n;
  logic [beat_count_width_lp-1:0] cur_data_beats_left_r, cur_data_beats_left_n;
  logic [1:0] cur_resp_r, cur_resp_n;
  logic                        cur_rd_is_meta_r, cur_rd_is_meta_n;

  req_desc_s    wr_desc_cast;
  rd_req_desc_s rd_desc_cast;
  r_desc_s      r_desc_cast;

  assign wr_desc_cast = req_desc_s'(wr_desc_data_lo);
  assign rd_desc_cast = rd_req_desc_s'(rd_desc_data_lo);
  assign r_desc_cast  = r_desc_s'(r_desc_data_lo);

  logic start_wr_pkt, start_rd_pkt, start_r_pkt, start_b_pkt;
  logic link_handshake;

  assign start_wr_pkt = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_WR_REQ)) && wr_desc_v_lo;
  assign start_rd_pkt = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_RD_REQ)) && rd_desc_v_lo;
  assign start_r_pkt  = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_RD_RESP)) && r_desc_v_lo;
  assign start_b_pkt  = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_WR_RESP)) && b_resp_v_lo;

  assign pkt_order_yumi_li = start_wr_pkt || start_rd_pkt || start_r_pkt || start_b_pkt;
  assign wr_desc_yumi_li   = start_wr_pkt;
  assign rd_desc_yumi_li   = start_rd_pkt;
  assign r_desc_yumi_li    = start_r_pkt;
  assign b_resp_yumi_li    = start_b_pkt;

  assign w_data_yumi_li = (state_r == TX_DATA) && link_handshake
                          && (cur_kind_r == pkt_kind_e'(PKT_WR_REQ));
  assign r_data_yumi_li = (state_r == TX_DATA) && link_handshake
                          && (cur_kind_r == pkt_kind_e'(PKT_RD_RESP));

  always_comb begin
    state_n               = state_r;
    cur_kind_n            = cur_kind_r;
    cur_addr_n            = cur_addr_r;
    cur_beats_n           = cur_beats_r;
    cur_data_beats_left_n = cur_data_beats_left_r;
    cur_resp_n            = cur_resp_r;
    cur_rd_is_meta_n      = cur_rd_is_meta_r;

    if (start_wr_pkt) begin
      // WRITE_REQ = header + address + W data beats.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_WR_REQ);
      cur_addr_n            = wr_desc_cast.addr;
      cur_beats_n           = wr_desc_cast.beats;
      cur_data_beats_left_n = wr_desc_cast.beats;
      cur_resp_n            = '0;
      cur_rd_is_meta_n      = 1'b0;
    end
    else if (start_rd_pkt) begin
      // READ_REQ / META_REQ = header only. `payload` is either the burst
      // length or the captured aruser content; either way it goes into the
      // middle 13 bits of the header flit.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_RD_REQ);
      cur_addr_n            = rd_desc_cast.addr;
      cur_beats_n           = rd_desc_cast.payload;
      cur_data_beats_left_n = '0;
      cur_resp_n            = '0;
      cur_rd_is_meta_n      = rd_desc_cast.is_meta;
    end
    else if (start_r_pkt) begin
      // READ_RESP = header + R data beats.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_RD_RESP);
      cur_addr_n            = '0;
      cur_beats_n           = r_desc_cast.beats;
      cur_data_beats_left_n = r_desc_cast.beats;
      cur_resp_n            = r_desc_cast.resp;
      cur_rd_is_meta_n      = 1'b0;
    end
    else if (start_b_pkt) begin
      // WRITE_RESP = header + one padded BRESP flit.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_WR_RESP);
      cur_addr_n            = '0;
      cur_beats_n           = beat_count_width_lp'(1);
      cur_data_beats_left_n = '0;
      cur_resp_n            = b_resp_lo;
      cur_rd_is_meta_n      = 1'b0;
    end
    else if (link_handshake) begin
      unique case (state_r)
        TX_HEADER: begin
          case (cur_kind_r)
            pkt_kind_e'(PKT_WR_REQ):  state_n = TX_DATA;
            pkt_kind_e'(PKT_RD_REQ):  state_n = TX_IDLE;
            pkt_kind_e'(PKT_RD_RESP): state_n = TX_DATA;
            default:                  state_n = TX_RESP;
          endcase
        end

        TX_DATA: begin
          if (cur_data_beats_left_r == beat_count_width_lp'(1)) begin
            cur_data_beats_left_n = '0;
            state_n = TX_IDLE;
          end
          else begin
            cur_data_beats_left_n = cur_data_beats_left_r - beat_count_width_lp'(1);
          end
        end

        TX_RESP: begin
          state_n               = TX_IDLE;
          cur_kind_n            = '0;
          cur_addr_n            = '0;
          cur_beats_n           = '0;
          cur_data_beats_left_n = '0;
          cur_resp_n            = '0;
          cur_rd_is_meta_n      = 1'b0;
        end

        default: begin
          state_n = TX_IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      state_r               <= TX_IDLE;
      cur_kind_r            <= '0;
      cur_addr_r            <= '0;
      cur_beats_r           <= '0;
      cur_data_beats_left_r <= '0;
      cur_resp_r            <= '0;
      cur_rd_is_meta_r      <= 1'b0;
    end
    else begin
      state_r               <= state_n;
      cur_kind_r            <= cur_kind_n;
      cur_addr_r            <= cur_addr_n;
      cur_beats_r           <= cur_beats_n;
      cur_data_beats_left_r <= cur_data_beats_left_n;
      cur_resp_r            <= cur_resp_n;
      cur_rd_is_meta_r      <= cur_rd_is_meta_n;
    end
  end

  always_comb begin
    link_tx_v_o    = 1'b0;
    link_tx_data_o = '0;

    unique case (state_r)
      TX_HEADER: begin
        link_tx_v_o = 1'b1;
        unique case (cur_kind_r)
          pkt_kind_e'(PKT_WR_REQ):  link_tx_data_o = {OP_WRITE_REQ,  cur_beats_r, cur_addr_r};
          pkt_kind_e'(PKT_RD_REQ):  link_tx_data_o = {cur_rd_is_meta_r ? OP_META_REQ : OP_READ_REQ,
                                                       cur_beats_r, cur_addr_r};
          pkt_kind_e'(PKT_RD_RESP): link_tx_data_o = {OP_READ_RESP,  cur_beats_r, 14'b0, cur_resp_r};
          default:                  link_tx_data_o = {OP_WRITE_RESP, beat_count_width_lp'(1), 16'b0};
        endcase
      end

      TX_DATA: begin
        if (cur_kind_r == pkt_kind_e'(PKT_WR_REQ)) begin
          link_tx_v_o    = w_data_v_lo;
          link_tx_data_o = w_data_lo;
        end
        else begin
          link_tx_v_o    = r_data_v_lo;
          link_tx_data_o = r_data_lo;
        end
      end

      TX_RESP: begin
        link_tx_v_o    = 1'b1;
        link_tx_data_o = {30'b0, cur_resp_r};
      end

      default: begin
        link_tx_v_o    = 1'b0;
        link_tx_data_o = '0;
      end
    endcase
  end

  assign link_handshake = link_tx_v_o && link_tx_ready_i;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if (w_accept) begin
        if (!w_accept_active_r && (w_len_data_lo == '0))
          $error("axi_link_tx accepted W without an older AW burst length");
        if (wlast_i != (w_accept_loaded_beats == beat_count_width_lp'(1)))
          $error("axi_link_tx saw WLAST misaligned with AW/W FIFO order");
      end

      if (r_accept && r_capture_active_r && (rresp_i != r_capture_resp_r))
        $error("axi_link_tx observed varying RRESP inside one R burst");

      if (r_accept && (rlast_i != (r_accept_loaded_beats == beat_count_width_lp'(1))))
        $error("axi_link_tx observed RLAST misaligned with stored AR length");

      if (awvalid_i && !aw_ctrl_ok && awready_o)
        $error("axi_link_tx accepted malformed AW control");

      if (arvalid_i && !ar_ctrl_ok && arready_o)
        $error("axi_link_tx accepted malformed AR control");
    end
  end
`endif

endmodule
