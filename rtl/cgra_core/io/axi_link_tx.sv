module axi_link_tx
  #(parameter int flit_width_p          = 16
   ,parameter int addr_width_p          = 16
   ,parameter int link_fifo_els_p       = 16
   ,parameter int aw_desc_fifo_els_p    = 4
   ,parameter int ar_desc_fifo_els_p    = 4
   ,parameter int w_len_fifo_els_p      = 8
   ,parameter int w_data_fifo_els_p     = 16
   ,parameter int r_len_fifo_els_p      = 8
   ,parameter int r_data_fifo_els_p     = 16
   ,parameter int b_resp_fifo_els_p     = 8
   ,parameter int pkt_order_fifo_els_p  = 16
   )
  (input  logic                     clk_i
   ,input logic                     reset_i

   // AXI AW burst descriptor input.
   ,input  logic                    awvalid_i
   ,output logic                    awready_o
   ,input  logic [addr_width_p-1:0] awaddr_i
   ,input  logic [7:0]              awlen_i
   ,input  logic [2:0]              awsize_i
   ,input  logic [1:0]              awburst_i

   // AXI W channel input.
   ,input  logic                    wvalid_i
   ,output logic                    wready_o
   ,input  logic [15:0]             wdata_i
   ,input  logic                    wlast_i

   // AXI AR burst descriptor input.
   ,input  logic                    arvalid_i
   ,output logic                    arready_o
   ,input  logic [addr_width_p-1:0] araddr_i
   ,input  logic [7:0]              arlen_i
   ,input  logic [2:0]              arsize_i
   ,input  logic [1:0]              arburst_i

   // AXI R channel input.
   ,input  logic                    rvalid_i
   ,output logic                    rready_o
   ,input  logic [15:0]             rdata_i
   ,input  logic [1:0]              rresp_i
   ,input  logic                    rlast_i

   // AXI B channel input.
   ,input  logic                    bvalid_i
   ,output logic                    bready_o
   ,input  logic [1:0]              bresp_i

   // Direct bsg_link transmit interface.
   ,output logic                    link_tx_v_o
   ,output logic [flit_width_p-1:0] link_tx_data_o
   ,input  logic                    link_tx_ready_i
   );

  // --------------------------------------------------------------------------
  // axi_link_tx
  // --------------------------------------------------------------------------
  // Link framing:
  //   header[15:13] = opcode
  //   header[12:0]  = burst beat count
  //
  // Packet mapping:
  //   AW packet: header len = associated W beat count, followed by one flit
  //              carrying the 16-bit address
  //   W packet : header len = number of 16-bit W beats, followed by that many
  //              data flits
  //   AR packet: same descriptor format as AW
  //   R packet : header len = number of 16-bit R beats, followed by that many
  //              data flits. rresp must be OKAY; this keeps the transported
  //              payload fully 16 bits wide.
  //   B packet : header len = 1, followed by one flit with bresp in [1:0]
  //
  // AXI boundary:
  //   The crossbar-facing side is a true 16-bit AXI-style burst interface.
  //   TX accepts standard AWLEN/ARLEN/AWSIZE/ARSIZE/AWBURST/ARBURST plus
  //   WLAST/RLAST, and it never adds AXI IDs or reorder logic.
  //
  // Ordering model:
  //   Packet starts are recorded in an internal global order FIFO in the exact
  //   order they are accepted. The serializer always follows that FIFO, so
  //   cross-channel order is preserved without any permanent channel priority.
  //   If several packet starts compete in one cycle, TX accepts at most one
  //   start and resolves that one-cycle tie with a round-robin pointer.
  //
  // Long-packet behavior:
  //   AW/AR immediately provide the upcoming burst length. TX records that
  //   length in small per-channel FIFOs and can therefore emit a W/R header as
  //   soon as the first beat of that burst is accepted. Payload beats then
  //   stream as they arrive; the whole packet never needs to fit at once.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 16)
      $error("axi_link_tx requires flit_width_p=16, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_tx currently implements a 16-bit AW/AR address payload, got %0d", addr_width_p);
  end

  typedef enum logic [2:0] {
    OP_AR = 3'd0,
    OP_AW = 3'd1,
    OP_W  = 3'd2,
    OP_R  = 3'd3,
    OP_B  = 3'd4
  } pkt_opcode_e;

  typedef enum logic [1:0] {
    TX_IDLE    = 2'd0,
    TX_SEND_HDR = 2'd1,
    TX_SEND_PAY = 2'd2
  } tx_state_e;

  localparam int len_width_lp      = 9;
  localparam int order_width_lp    = 16;
  localparam int addr_payload_lp   = 1;
  localparam logic [2:0] axi_size_lp  = 3'b001;
  localparam logic [1:0] axi_burst_lp = 2'b01;
  localparam logic [1:0] axi_resp_okay_lp = 2'b00;
  localparam int num_ch_lp = 5;

  // --------------------------------------------------------------------------
  // Internal FIFOs
  // --------------------------------------------------------------------------

  logic        aw_desc_push_v, aw_desc_push_ready, aw_desc_fifo_v, aw_desc_fifo_yumi;
  logic [15:0] aw_desc_fifo_data;
  logic        ar_desc_push_v, ar_desc_push_ready, ar_desc_fifo_v, ar_desc_fifo_yumi;
  logic [15:0] ar_desc_fifo_data;

  logic                 w_len_push_v, w_len_push_ready, w_len_fifo_v, w_len_fifo_yumi;
  logic [len_width_lp-1:0] w_len_push_data, w_len_fifo_data;
  logic                 r_len_push_v, r_len_push_ready, r_len_fifo_v, r_len_fifo_yumi;
  logic [len_width_lp-1:0] r_len_push_data, r_len_fifo_data;

  logic        w_data_push_v, w_data_push_ready, w_data_fifo_v, w_data_fifo_yumi;
  logic [15:0] w_data_fifo_data;
  logic        r_data_push_v, r_data_push_ready, r_data_fifo_v, r_data_fifo_yumi;
  logic [15:0] r_data_fifo_data;

  logic      b_resp_push_v, b_resp_push_ready, b_resp_fifo_v, b_resp_fifo_yumi;
  logic [1:0] b_resp_fifo_data;

  logic                    pkt_order_push_v, pkt_order_push_ready, pkt_order_fifo_v, pkt_order_fifo_yumi;
  logic [order_width_lp-1:0] pkt_order_push_data, pkt_order_fifo_data;

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (aw_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) aw_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (aw_desc_push_v),
    .data_i (awaddr_i),
    .ready_o(aw_desc_push_ready),
    .v_o    (aw_desc_fifo_v),
    .data_o (aw_desc_fifo_data),
    .yumi_i (aw_desc_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (ar_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) ar_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (ar_desc_push_v),
    .data_i (araddr_i),
    .ready_o(ar_desc_push_ready),
    .v_o    (ar_desc_fifo_v),
    .data_o (ar_desc_fifo_data),
    .yumi_i (ar_desc_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (len_width_lp),
    .els_p              (w_len_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) w_len_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (w_len_push_v),
    .data_i (w_len_push_data),
    .ready_o(w_len_push_ready),
    .v_o    (w_len_fifo_v),
    .data_o (w_len_fifo_data),
    .yumi_i (w_len_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (len_width_lp),
    .els_p              (r_len_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) r_len_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (r_len_push_v),
    .data_i (r_len_push_data),
    .ready_o(r_len_push_ready),
    .v_o    (r_len_fifo_v),
    .data_o (r_len_fifo_data),
    .yumi_i (r_len_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (w_data_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) w_data_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (w_data_push_v),
    .data_i (wdata_i),
    .ready_o(w_data_push_ready),
    .v_o    (w_data_fifo_v),
    .data_o (w_data_fifo_data),
    .yumi_i (w_data_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (r_data_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) r_data_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (r_data_push_v),
    .data_i (rdata_i),
    .ready_o(r_data_push_ready),
    .v_o    (r_data_fifo_v),
    .data_o (r_data_fifo_data),
    .yumi_i (r_data_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (2),
    .els_p              (b_resp_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) b_resp_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (b_resp_push_v),
    .data_i (bresp_i),
    .ready_o(b_resp_push_ready),
    .v_o    (b_resp_fifo_v),
    .data_o (b_resp_fifo_data),
    .yumi_i (b_resp_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (order_width_lp),
    .els_p              (pkt_order_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) pkt_order_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (pkt_order_push_v),
    .data_i (pkt_order_push_data),
    .ready_o(pkt_order_push_ready),
    .v_o    (pkt_order_fifo_v),
    .data_o (pkt_order_fifo_data),
    .yumi_i (pkt_order_fifo_yumi)
  );

  // --------------------------------------------------------------------------
  // Start acceptance and in-packet tracking
  // --------------------------------------------------------------------------

  logic                  aw_req, ar_req, w_start_req, r_start_req, b_req;
  logic [num_ch_lp-1:0]  start_req, start_grant, start_accept;
  logic [2:0]            rr_start_r, rr_start_n;
  logic                  start_accept_any;
  logic                  aw_accept, ar_accept, w_accept, r_accept, b_accept;
  logic                  aw_start_accept, ar_start_accept, w_start_accept, r_start_accept, b_start_accept;

  logic                  w_in_packet_r, w_in_packet_n;
  logic [len_width_lp-1:0] w_rem_r, w_rem_n;
  logic                  r_in_packet_r, r_in_packet_n;
  logic [len_width_lp-1:0] r_rem_r, r_rem_n;

  logic [len_width_lp-1:0] aw_beats, ar_beats;
  logic [len_width_lp-1:0] w_start_beats, r_start_beats;
  logic                    aw_ctrl_ok, ar_ctrl_ok;

  integer scan_i;
  integer scan_idx;

  assign aw_beats = {1'b0, awlen_i} + len_width_lp'(1);
  assign ar_beats = {1'b0, arlen_i} + len_width_lp'(1);
  assign w_start_beats = w_len_fifo_data;
  assign r_start_beats = r_len_fifo_data;

  assign aw_ctrl_ok = (awsize_i == axi_size_lp) && (awburst_i == axi_burst_lp);
  assign ar_ctrl_ok = (arsize_i == axi_size_lp) && (arburst_i == axi_burst_lp);

  assign aw_req      = awvalid_i && aw_desc_push_ready && w_len_push_ready && aw_ctrl_ok;
  assign ar_req      = arvalid_i && ar_desc_push_ready && r_len_push_ready && ar_ctrl_ok;
  assign w_start_req = wvalid_i && !w_in_packet_r && w_data_push_ready && w_len_fifo_v;
  assign r_start_req = rvalid_i && !r_in_packet_r && r_data_push_ready && r_len_fifo_v;
  assign b_req       = bvalid_i && b_resp_push_ready;

  assign start_req[OP_AR] = ar_req;
  assign start_req[OP_AW] = aw_req;
  assign start_req[OP_W]  = w_start_req;
  assign start_req[OP_R]  = r_start_req;
  assign start_req[OP_B]  = b_req;

  always_comb begin
    start_grant = '0;
    rr_start_n  = rr_start_r;

    if (pkt_order_push_ready) begin
      for (scan_i = 0; scan_i < num_ch_lp; scan_i++) begin
        scan_idx = rr_start_r + scan_i;
        if (scan_idx >= num_ch_lp)
          scan_idx = scan_idx - num_ch_lp;

        if ((start_grant == '0) && start_req[scan_idx])
          start_grant[scan_idx] = 1'b1;
      end
    end

    if (start_grant[OP_AR]) rr_start_n = 3'd1;
    if (start_grant[OP_AW]) rr_start_n = 3'd2;
    if (start_grant[OP_W])  rr_start_n = 3'd3;
    if (start_grant[OP_R])  rr_start_n = 3'd4;
    if (start_grant[OP_B])  rr_start_n = 3'd0;
  end

  assign awready_o = pkt_order_push_ready && start_grant[OP_AW] && aw_desc_push_ready && w_len_push_ready && aw_ctrl_ok;
  assign arready_o = pkt_order_push_ready && start_grant[OP_AR] && ar_desc_push_ready && r_len_push_ready && ar_ctrl_ok;
  assign bready_o  = pkt_order_push_ready && start_grant[OP_B]  && b_resp_push_ready;

  assign wready_o  = w_data_push_ready
                  && (w_in_packet_r
                      ? 1'b1
                      : (pkt_order_push_ready && start_grant[OP_W] && w_len_fifo_v));

  assign rready_o  = r_data_push_ready
                  && (r_in_packet_r
                      ? 1'b1
                      : (pkt_order_push_ready && start_grant[OP_R] && r_len_fifo_v));

  assign aw_start_accept = awvalid_i && awready_o;
  assign ar_start_accept = arvalid_i && arready_o;
  assign b_start_accept  = bvalid_i && bready_o;
  assign w_start_accept  = wvalid_i && wready_o && !w_in_packet_r;
  assign r_start_accept  = rvalid_i && rready_o && !r_in_packet_r;

  assign aw_accept = aw_start_accept;
  assign ar_accept = ar_start_accept;
  assign b_accept  = b_start_accept;
  assign w_accept  = wvalid_i && wready_o;
  assign r_accept  = rvalid_i && rready_o;

  assign start_accept[OP_AR] = ar_start_accept;
  assign start_accept[OP_AW] = aw_start_accept;
  assign start_accept[OP_W]  = w_start_accept;
  assign start_accept[OP_R]  = r_start_accept;
  assign start_accept[OP_B]  = b_start_accept;
  assign start_accept_any    = |start_accept;

  assign aw_desc_push_v = aw_start_accept;
  assign ar_desc_push_v = ar_start_accept;
  assign w_len_push_v   = aw_start_accept;
  assign w_len_push_data = aw_beats;
  assign r_len_push_v   = ar_start_accept;
  assign r_len_push_data = ar_beats;
  assign w_data_push_v  = w_accept;
  assign r_data_push_v  = r_accept;
  assign b_resp_push_v  = b_accept;

  assign w_len_fifo_yumi = w_start_accept;
  assign r_len_fifo_yumi = r_start_accept;

  always_comb begin
    pkt_order_push_v    = 1'b0;
    pkt_order_push_data = '0;

    unique case (1'b1)
      start_accept[OP_AR]: begin
        pkt_order_push_v    = 1'b1;
        pkt_order_push_data = {OP_AR, 4'b0, ar_beats};
      end
      start_accept[OP_AW]: begin
        pkt_order_push_v    = 1'b1;
        pkt_order_push_data = {OP_AW, 4'b0, aw_beats};
      end
      start_accept[OP_W]: begin
        pkt_order_push_v    = 1'b1;
        pkt_order_push_data = {OP_W, 4'b0, w_start_beats};
      end
      start_accept[OP_R]: begin
        pkt_order_push_v    = 1'b1;
        pkt_order_push_data = {OP_R, 4'b0, r_start_beats};
      end
      start_accept[OP_B]: begin
        pkt_order_push_v    = 1'b1;
        pkt_order_push_data = {OP_B, 13'd1};
      end
      default: begin
        pkt_order_push_v    = 1'b0;
        pkt_order_push_data = '0;
      end
    endcase
  end

  always_comb begin
    w_in_packet_n = w_in_packet_r;
    w_rem_n       = w_rem_r;

    if (w_accept) begin
      if (!w_in_packet_r) begin
        if (w_start_beats == len_width_lp'(1)) begin
          w_in_packet_n = 1'b0;
          w_rem_n       = '0;
        end
        else begin
          w_in_packet_n = 1'b1;
          w_rem_n       = w_start_beats - len_width_lp'(1);
        end
      end
      else if (w_rem_r == len_width_lp'(1)) begin
        w_in_packet_n = 1'b0;
        w_rem_n       = '0;
      end
      else begin
        w_rem_n = w_rem_r - len_width_lp'(1);
      end
    end
  end

  always_comb begin
    r_in_packet_n = r_in_packet_r;
    r_rem_n       = r_rem_r;

    if (r_accept) begin
      if (!r_in_packet_r) begin
        if (r_start_beats == len_width_lp'(1)) begin
          r_in_packet_n = 1'b0;
          r_rem_n       = '0;
        end
        else begin
          r_in_packet_n = 1'b1;
          r_rem_n       = r_start_beats - len_width_lp'(1);
        end
      end
      else if (r_rem_r == len_width_lp'(1)) begin
        r_in_packet_n = 1'b0;
        r_rem_n       = '0;
      end
      else begin
        r_rem_n = r_rem_r - len_width_lp'(1);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      rr_start_r   <= 3'd0;
      w_in_packet_r <= 1'b0;
      w_rem_r      <= '0;
      r_in_packet_r <= 1'b0;
      r_rem_r      <= '0;
    end
    else begin
      if (start_accept_any)
        rr_start_r <= rr_start_n;

      w_in_packet_r <= w_in_packet_n;
      w_rem_r       <= w_rem_n;
      r_in_packet_r <= r_in_packet_n;
      r_rem_r       <= r_rem_n;
    end
  end

  // --------------------------------------------------------------------------
  // Link egress FIFO
  // --------------------------------------------------------------------------

  logic        link_flit_v;
  logic [15:0] link_flit_data;
  logic        link_fifo_push_ready;
  logic        link_fifo_pop_v;
  logic [15:0] link_fifo_pop_data;
  logic        link_fifo_pop_yumi;

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (link_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) link_egress_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (link_flit_v),
    .data_i (link_flit_data),
    .ready_o(link_fifo_push_ready),
    .v_o    (link_fifo_pop_v),
    .data_o (link_fifo_pop_data),
    .yumi_i (link_fifo_pop_yumi)
  );

  assign link_tx_v_o        = link_fifo_pop_v;
  assign link_tx_data_o     = link_fifo_pop_data;
  assign link_fifo_pop_yumi = link_fifo_pop_v && link_tx_ready_i;

  // --------------------------------------------------------------------------
  // Serializer
  // --------------------------------------------------------------------------

  tx_state_e tx_state_r, tx_state_n;
  logic [2:0]  cur_opcode_r, cur_opcode_n;
  logic [12:0] cur_beats_r, cur_beats_n;
  logic [12:0] payload_rem_r, payload_rem_n;

  logic send_aw_desc, send_ar_desc, send_w_data, send_r_data, send_b_resp;

  assign send_aw_desc = (tx_state_r == TX_SEND_PAY) && (cur_opcode_r == OP_AW) && aw_desc_fifo_v;
  assign send_ar_desc = (tx_state_r == TX_SEND_PAY) && (cur_opcode_r == OP_AR) && ar_desc_fifo_v;
  assign send_w_data  = (tx_state_r == TX_SEND_PAY) && (cur_opcode_r == OP_W)  && w_data_fifo_v;
  assign send_r_data  = (tx_state_r == TX_SEND_PAY) && (cur_opcode_r == OP_R)  && r_data_fifo_v;
  assign send_b_resp  = (tx_state_r == TX_SEND_PAY) && (cur_opcode_r == OP_B)  && b_resp_fifo_v;

  assign link_flit_v = (tx_state_r == TX_SEND_HDR)
                    || send_aw_desc
                    || send_ar_desc
                    || send_w_data
                    || send_r_data
                    || send_b_resp;

  always_comb begin
    link_flit_data = '0;

    unique case (tx_state_r)
      TX_SEND_HDR: link_flit_data = {cur_opcode_r, cur_beats_r};
      TX_SEND_PAY: begin
        unique case (cur_opcode_r)
          OP_AW: link_flit_data = aw_desc_fifo_data;
          OP_AR: link_flit_data = ar_desc_fifo_data;
          OP_W : link_flit_data = w_data_fifo_data;
          OP_R : link_flit_data = r_data_fifo_data;
          OP_B : link_flit_data = {14'b0, b_resp_fifo_data};
          default: link_flit_data = '0;
        endcase
      end
      default: link_flit_data = '0;
    endcase
  end

  always_comb begin
    tx_state_n   = tx_state_r;
    cur_opcode_n = cur_opcode_r;
    cur_beats_n  = cur_beats_r;
    payload_rem_n = payload_rem_r;

    pkt_order_fifo_yumi = 1'b0;
    aw_desc_fifo_yumi   = 1'b0;
    ar_desc_fifo_yumi   = 1'b0;
    w_data_fifo_yumi    = 1'b0;
    r_data_fifo_yumi    = 1'b0;
    b_resp_fifo_yumi    = 1'b0;

    case (tx_state_r)
      TX_IDLE: begin
        if (pkt_order_fifo_v) begin
          cur_opcode_n = pkt_order_fifo_data[15:13];
          cur_beats_n  = pkt_order_fifo_data[12:0];
          unique case (pkt_order_fifo_data[15:13])
            OP_AW, OP_AR: payload_rem_n = 13'(addr_payload_lp);
            OP_B        : payload_rem_n = 13'd1;
            default     : payload_rem_n = pkt_order_fifo_data[12:0];
          endcase
          tx_state_n  = TX_SEND_HDR;
        end
      end

      TX_SEND_HDR: begin
        if (link_flit_v && link_fifo_push_ready) begin
          pkt_order_fifo_yumi = 1'b1;
          tx_state_n          = TX_SEND_PAY;
        end
      end

      TX_SEND_PAY: begin
        if (link_flit_v && link_fifo_push_ready) begin
          unique case (cur_opcode_r)
            OP_AW: aw_desc_fifo_yumi = 1'b1;
            OP_AR: ar_desc_fifo_yumi = 1'b1;
            OP_W: w_data_fifo_yumi = 1'b1;
            OP_R: r_data_fifo_yumi = 1'b1;
            OP_B: b_resp_fifo_yumi = 1'b1;
            default: begin end
          endcase

          if (payload_rem_r == 13'd1) begin
            tx_state_n    = TX_IDLE;
            cur_opcode_n  = OP_AW;
            cur_beats_n   = '0;
            payload_rem_n = '0;
          end
          else begin
            payload_rem_n = payload_rem_r - 13'd1;
          end
        end
      end

      default: begin
        tx_state_n    = TX_IDLE;
        cur_opcode_n  = OP_AW;
        cur_beats_n   = '0;
        payload_rem_n = '0;
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      tx_state_r    <= TX_IDLE;
      cur_opcode_r  <= OP_AW;
      cur_beats_r   <= '0;
      payload_rem_r <= '0;
    end
    else begin
      tx_state_r    <= tx_state_n;
      cur_opcode_r  <= cur_opcode_n;
      cur_beats_r   <= cur_beats_n;
      payload_rem_r <= payload_rem_n;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if (aw_start_accept) begin
        assert (aw_ctrl_ok)
          else $error("axi_link_tx only supports AWSIZE=1 and AWBURST=INCR");
      end

      if (ar_start_accept) begin
        assert (ar_ctrl_ok)
          else $error("axi_link_tx only supports ARSIZE=1 and ARBURST=INCR");
      end

      if (w_accept) begin
        if (!w_in_packet_r)
          assert (wlast_i == (w_start_beats == len_width_lp'(1)))
            else $error("axi_link_tx WLAST on first beat does not match AW-derived burst length");
        else
          assert (wlast_i == (w_rem_r == len_width_lp'(1)))
            else $error("axi_link_tx WLAST asserted away from the final W beat");
      end

      if (r_accept) begin
        assert (rresp_i == axi_resp_okay_lp)
          else $error("axi_link_tx expects RRESP=OKAY because R packets transport full 16-bit data beats only");

        if (!r_in_packet_r)
          assert (rlast_i == (r_start_beats == len_width_lp'(1)))
            else $error("axi_link_tx RLAST on first beat does not match AR-derived burst length");
        else
          assert (rlast_i == (r_rem_r == len_width_lp'(1)))
            else $error("axi_link_tx RLAST asserted away from the final R beat");
      end

      if (awvalid_i)
        assert (aw_ctrl_ok)
          else $error("axi_link_tx only supports AWSIZE=1 and AWBURST=INCR");

      if (arvalid_i)
        assert (ar_ctrl_ok)
          else $error("axi_link_tx only supports ARSIZE=1 and ARBURST=INCR");

      if (tx_state_r == TX_SEND_PAY)
        assert (payload_rem_r != '0)
          else $error("axi_link_tx entered payload send state with zero remaining flits");
    end
  end
`endif

endmodule
