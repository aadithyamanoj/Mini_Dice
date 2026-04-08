module axi_link_rx
  #(parameter int flit_width_p        = 16
   ,parameter int addr_width_p        = 16
   ,parameter int link_fifo_els_p     = 16
   ,parameter int aw_desc_fifo_els_p  = 4
   ,parameter int ar_desc_fifo_els_p  = 4
   ,parameter int w_len_fifo_els_p    = 8
   ,parameter int w_data_fifo_els_p   = 16
   ,parameter int r_len_fifo_els_p    = 8
   ,parameter int r_data_fifo_els_p   = 16
   ,parameter int b_resp_fifo_els_p   = 8
   )
  (input  logic                     clk_i
   ,input logic                     reset_i

   // Direct bsg_link receive interface.
   ,input  logic                    link_rx_v_i
   ,input  logic [flit_width_p-1:0] link_rx_data_i
   ,output logic                    link_rx_yumi_o

   // AXI AW burst descriptor output.
   ,output logic                    awvalid_o
   ,input  logic                    awready_i
   ,output logic [addr_width_p-1:0] awaddr_o
   ,output logic [7:0]              awlen_o
   ,output logic [2:0]              awsize_o
   ,output logic [1:0]              awburst_o

   // AXI W channel output.
   ,output logic                    wvalid_o
   ,input  logic                    wready_i
   ,output logic [15:0]             wdata_o
   ,output logic                    wlast_o

   // AXI AR burst descriptor output.
   ,output logic                    arvalid_o
   ,input  logic                    arready_i
   ,output logic [addr_width_p-1:0] araddr_o
   ,output logic [7:0]              arlen_o
   ,output logic [2:0]              arsize_o
   ,output logic [1:0]              arburst_o

   // AXI R channel output.
   ,output logic                    rvalid_o
   ,input  logic                    rready_i
   ,output logic [15:0]             rdata_o
   ,output logic [1:0]              rresp_o
   ,output logic                    rlast_o

   // AXI B channel output.
   ,output logic                    bvalid_o
   ,input  logic                    bready_i
   ,output logic [1:0]              bresp_o
   );

  // --------------------------------------------------------------------------
  // axi_link_rx
  // --------------------------------------------------------------------------
  // Link framing:
  //   Every packet starts with one 16-bit header flit.
  //     header[15:13] = opcode
  //     header[12:0]  = burst beat count
  //
  // Packet mapping:
  //   AW packet: header len = W beats for the burst, followed by exactly one
  //              descriptor flit carrying a 16-bit address:
  //                payload[0] = awaddr[15:0]
  //   W packet : header len = number of 16-bit W beats, followed by exactly
  //              that many 16-bit data flits
  //   AR packet: same descriptor format as AW
  //   R packet : header len = number of 16-bit R beats, followed by exactly
  //              that many 16-bit data flits; rresp is fixed to OKAY to
  //              preserve the full 16-bit data width on the crossbar boundary
  //   B packet : header len must be 1, followed by one response flit with
  //              bresp in payload[1:0] and upper bits reserved
  //
  // AXI boundary:
  //   The crossbar-facing side is a true 16-bit AXI-style burst interface.
  //   AWLEN/ARLEN are driven as beats-1, AWSIZE/ARSIZE are constant 1
  //   (2 bytes/beat), and AWBURST/ARBURST are constant INCR.
  //
  // Area-conscious structure:
  //   - one narrow ingress FIFO after bsg_link
  //   - one AW descriptor FIFO and one AR descriptor FIFO
  //   - W length FIFO + W data FIFO
  //   - R length FIFO + R data FIFO
  //   - one small B response FIFO
  //
  // Long-packet behavior:
  //   W/R lengths are published internally as soon as their headers are
  //   accepted, and data beats stream directly into their FIFOs as payload
  //   flits arrive. The full packet never needs to be buffered at once.
  //
  // Strict order:
  //   No AXI IDs or reorder logic are implemented. Correctness depends on
  //   strict FIFO ordering end-to-end.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 16)
      $error("axi_link_rx requires flit_width_p=16, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_rx currently implements a 16-bit AW/AR address payload, got %0d", addr_width_p);
  end

  typedef enum logic [2:0] {
    OP_AR = 3'd0,
    OP_AW = 3'd1,
    OP_W  = 3'd2,
    OP_R  = 3'd3,
    OP_B  = 3'd4
  } pkt_opcode_e;

  typedef enum logic [2:0] {
    RX_IDLE = 3'd0,
    RX_AW   = 3'd1,
    RX_W    = 3'd2,
    RX_AR   = 3'd3,
    RX_R    = 3'd4,
    RX_B    = 3'd5,
    RX_DROP = 3'd6
  } rx_state_e;

  localparam int len_width_lp       = 9;
  localparam int desc_width_lp      = 24;
  localparam int aw_ar_payload_lp   = 1;
  localparam logic [2:0] axi_size_lp  = 3'b001;
  localparam logic [1:0] axi_burst_lp = 2'b01;
  localparam logic [1:0] axi_resp_okay_lp = 2'b00;

  // --------------------------------------------------------------------------
  // Link ingress FIFO
  // --------------------------------------------------------------------------

  logic        link_fifo_push_ready;
  logic        link_fifo_pop_v;
  logic [15:0] link_fifo_pop_data;
  logic        link_fifo_pop_yumi;

  assign link_rx_yumi_o = link_rx_v_i && link_fifo_push_ready;

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (link_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) link_ingress_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (link_rx_yumi_o),
    .data_i (link_rx_data_i),
    .ready_o(link_fifo_push_ready),
    .v_o    (link_fifo_pop_v),
    .data_o (link_fifo_pop_data),
    .yumi_i (link_fifo_pop_yumi)
  );

  // --------------------------------------------------------------------------
  // Small internal FIFOs
  // --------------------------------------------------------------------------

  logic                   aw_desc_push_v, aw_desc_push_ready, aw_desc_fifo_v, aw_desc_fifo_yumi;
  logic [desc_width_lp-1:0] aw_desc_push_data, aw_desc_fifo_data;
  logic                   ar_desc_push_v, ar_desc_push_ready, ar_desc_fifo_v, ar_desc_fifo_yumi;
  logic [desc_width_lp-1:0] ar_desc_push_data, ar_desc_fifo_data;

  logic                 w_len_push_v, w_len_push_ready, w_len_fifo_v, w_len_fifo_yumi;
  logic [len_width_lp-1:0] w_len_push_data, w_len_fifo_data;
  logic                 r_len_push_v, r_len_push_ready, r_len_fifo_v, r_len_fifo_yumi;
  logic [len_width_lp-1:0] r_len_push_data, r_len_fifo_data;

  logic        w_data_push_v, w_data_push_ready, w_data_fifo_v, w_data_fifo_yumi;
  logic [15:0] w_data_push_data, w_data_fifo_data;
  logic        r_data_push_v, r_data_push_ready, r_data_fifo_v, r_data_fifo_yumi;
  logic [15:0] r_data_push_data, r_data_fifo_data;

  logic      b_resp_push_v, b_resp_push_ready, b_resp_fifo_v, b_resp_fifo_yumi;
  logic [1:0] b_resp_push_data, b_resp_fifo_data;

  bsg_fifo_1r1w_small #(
    .width_p            (desc_width_lp),
    .els_p              (aw_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) aw_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (aw_desc_push_v),
    .data_i (aw_desc_push_data),
    .ready_o(aw_desc_push_ready),
    .v_o    (aw_desc_fifo_v),
    .data_o (aw_desc_fifo_data),
    .yumi_i (aw_desc_fifo_yumi)
  );

  bsg_fifo_1r1w_small #(
    .width_p            (desc_width_lp),
    .els_p              (ar_desc_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) ar_desc_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (ar_desc_push_v),
    .data_i (ar_desc_push_data),
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
    .data_i (w_data_push_data),
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
    .data_i (r_data_push_data),
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
    .data_i (b_resp_push_data),
    .ready_o(b_resp_push_ready),
    .v_o    (b_resp_fifo_v),
    .data_o (b_resp_fifo_data),
    .yumi_i (b_resp_fifo_yumi)
  );

  // --------------------------------------------------------------------------
  // Header decode and parser state
  // --------------------------------------------------------------------------

  rx_state_e   rx_state_r, rx_state_n;
  pkt_opcode_e pkt_opcode_r, pkt_opcode_n;
  logic [12:0] pkt_beats_r, pkt_beats_n;
  logic [12:0] drop_rem_r, drop_rem_n;
  logic [2:0]  hdr_opcode;
  logic [12:0] hdr_beats;
  logic        hdr_opcode_known;
  logic        hdr_beats_valid;
  logic        hdr_malformed;
  logic [12:0] malformed_drop_len;

  assign hdr_opcode = link_fifo_pop_data[15:13];
  assign hdr_beats  = link_fifo_pop_data[12:0];

  always_comb begin
    hdr_opcode_known = 1'b1;
    hdr_beats_valid  = 1'b1;

    unique case (hdr_opcode)
      OP_AR: hdr_beats_valid = (hdr_beats != 13'd0) && (hdr_beats <= 13'd256);
      OP_AW: hdr_beats_valid = (hdr_beats != 13'd0) && (hdr_beats <= 13'd256);
      OP_W : hdr_beats_valid = (hdr_beats != 13'd0) && (hdr_beats <= 13'd256);
      OP_R : hdr_beats_valid = (hdr_beats != 13'd0) && (hdr_beats <= 13'd256);
      OP_B : hdr_beats_valid = (hdr_beats == 13'd1);
      default: begin
        hdr_opcode_known = 1'b0;
        hdr_beats_valid  = 1'b0;
      end
    endcase

    hdr_malformed = !hdr_opcode_known || !hdr_beats_valid;

    unique case (hdr_opcode)
      OP_AW, OP_AR: malformed_drop_len = 13'(aw_ar_payload_lp);
      OP_B        : malformed_drop_len = 13'd1;
      default     : malformed_drop_len = hdr_beats;
    endcase
  end

  // --------------------------------------------------------------------------
  // AXI output side
  // --------------------------------------------------------------------------

  logic                 w_active_r, w_active_n;
  logic [len_width_lp-1:0] w_rem_r, w_rem_n;
  logic                 r_active_r, r_active_n;
  logic [len_width_lp-1:0] r_rem_r, r_rem_n;
  logic [len_width_lp-1:0] w_cur_beats, r_cur_beats;
  logic                 w_have_pkt, r_have_pkt;
  logic                 w_handshake, r_handshake;

  assign awvalid_o      = aw_desc_fifo_v;
  assign awaddr_o       = aw_desc_fifo_data[15:0];
  assign awlen_o        = aw_desc_fifo_data[23:16];
  assign awsize_o       = axi_size_lp;
  assign awburst_o      = axi_burst_lp;
  assign aw_desc_fifo_yumi = aw_desc_fifo_v && awready_i;

  assign arvalid_o      = ar_desc_fifo_v;
  assign araddr_o       = ar_desc_fifo_data[15:0];
  assign arlen_o        = ar_desc_fifo_data[23:16];
  assign arsize_o       = axi_size_lp;
  assign arburst_o      = axi_burst_lp;
  assign ar_desc_fifo_yumi = ar_desc_fifo_v && arready_i;

  assign w_have_pkt     = w_active_r || w_len_fifo_v;
  assign w_cur_beats    = w_active_r ? w_rem_r : w_len_fifo_data;
  assign wvalid_o       = w_have_pkt && w_data_fifo_v;
  assign wdata_o        = w_data_fifo_data;
  assign wlast_o        = (w_cur_beats == len_width_lp'(1));
  assign w_handshake    = wvalid_o && wready_i;
  assign w_data_fifo_yumi = w_handshake;
  assign w_len_fifo_yumi  = w_handshake && !w_active_r;

  assign r_have_pkt     = r_active_r || r_len_fifo_v;
  assign r_cur_beats    = r_active_r ? r_rem_r : r_len_fifo_data;
  assign rvalid_o       = r_have_pkt && r_data_fifo_v;
  assign rdata_o        = r_data_fifo_data;
  assign rresp_o        = axi_resp_okay_lp;
  assign rlast_o        = (r_cur_beats == len_width_lp'(1));
  assign r_handshake    = rvalid_o && rready_i;
  assign r_data_fifo_yumi = r_handshake;
  assign r_len_fifo_yumi  = r_handshake && !r_active_r;

  assign bvalid_o       = b_resp_fifo_v;
  assign bresp_o        = b_resp_fifo_data;
  assign b_resp_fifo_yumi = b_resp_fifo_v && bready_i;

  always_comb begin
    w_active_n = w_active_r;
    w_rem_n    = w_rem_r;

    if (w_handshake) begin
      if (!w_active_r) begin
        if (w_len_fifo_data == len_width_lp'(1)) begin
          w_active_n = 1'b0;
          w_rem_n    = '0;
        end
        else begin
          w_active_n = 1'b1;
          w_rem_n    = w_len_fifo_data - len_width_lp'(1);
        end
      end
      else if (w_rem_r == len_width_lp'(1)) begin
        w_active_n = 1'b0;
        w_rem_n    = '0;
      end
      else begin
        w_rem_n = w_rem_r - len_width_lp'(1);
      end
    end
  end

  always_comb begin
    r_active_n = r_active_r;
    r_rem_n    = r_rem_r;

    if (r_handshake) begin
      if (!r_active_r) begin
        if (r_len_fifo_data == len_width_lp'(1)) begin
          r_active_n = 1'b0;
          r_rem_n    = '0;
        end
        else begin
          r_active_n = 1'b1;
          r_rem_n    = r_len_fifo_data - len_width_lp'(1);
        end
      end
      else if (r_rem_r == len_width_lp'(1)) begin
        r_active_n = 1'b0;
        r_rem_n    = '0;
      end
      else begin
        r_rem_n = r_rem_r - len_width_lp'(1);
      end
    end
  end

  // --------------------------------------------------------------------------
  // Parser
  // --------------------------------------------------------------------------

  always_comb begin
    rx_state_n      = rx_state_r;
    pkt_opcode_n    = pkt_opcode_r;
    pkt_beats_n     = pkt_beats_r;
    drop_rem_n      = drop_rem_r;
    link_fifo_pop_yumi = 1'b0;

    aw_desc_push_v    = 1'b0;
    aw_desc_push_data = '0;
    ar_desc_push_v    = 1'b0;
    ar_desc_push_data = '0;
    w_len_push_v      = 1'b0;
    w_len_push_data   = '0;
    r_len_push_v      = 1'b0;
    r_len_push_data   = '0;
    w_data_push_v     = 1'b0;
    w_data_push_data  = link_fifo_pop_data;
    r_data_push_v     = 1'b0;
    r_data_push_data  = link_fifo_pop_data;
    b_resp_push_v     = 1'b0;
    b_resp_push_data  = link_fifo_pop_data[1:0];

    case (rx_state_r)
      RX_IDLE: begin
        if (link_fifo_pop_v) begin
          if (hdr_malformed) begin
            link_fifo_pop_yumi = 1'b1;
            if (malformed_drop_len == '0) begin
              rx_state_n = RX_IDLE;
            end
            else begin
              rx_state_n = RX_DROP;
              drop_rem_n = malformed_drop_len;
            end
          end
          else begin
            unique case (pkt_opcode_e'(hdr_opcode))
              OP_AW: begin
                link_fifo_pop_yumi = 1'b1;
                rx_state_n         = RX_AW;
                pkt_opcode_n       = OP_AW;
                pkt_beats_n        = hdr_beats;
              end
              OP_AR: begin
                link_fifo_pop_yumi = 1'b1;
                rx_state_n         = RX_AR;
                pkt_opcode_n       = OP_AR;
                pkt_beats_n        = hdr_beats;
              end
              OP_W: begin
                if (w_len_push_ready) begin
                  link_fifo_pop_yumi = 1'b1;
                  w_len_push_v       = 1'b1;
                  w_len_push_data    = hdr_beats[len_width_lp-1:0];
                  rx_state_n         = RX_W;
                  pkt_opcode_n       = OP_W;
                  pkt_beats_n        = hdr_beats;
                end
              end
              OP_R: begin
                if (r_len_push_ready) begin
                  link_fifo_pop_yumi = 1'b1;
                  r_len_push_v       = 1'b1;
                  r_len_push_data    = hdr_beats[len_width_lp-1:0];
                  rx_state_n         = RX_R;
                  pkt_opcode_n       = OP_R;
                  pkt_beats_n        = hdr_beats;
                end
              end
              OP_B: begin
                link_fifo_pop_yumi = 1'b1;
                rx_state_n         = RX_B;
                pkt_opcode_n       = OP_B;
                pkt_beats_n        = 13'd1;
              end
              default: begin
                link_fifo_pop_yumi = 1'b1;
                rx_state_n         = RX_DROP;
                drop_rem_n         = malformed_drop_len;
              end
            endcase
          end
        end
      end

      RX_AW: begin
        if (link_fifo_pop_v && aw_desc_push_ready) begin
          link_fifo_pop_yumi = 1'b1;
          aw_desc_push_v     = 1'b1;
          aw_desc_push_data  = {pkt_beats_r[7:0] - 8'd1, link_fifo_pop_data};
          rx_state_n         = RX_IDLE;
        end
      end

      RX_AR: begin
        if (link_fifo_pop_v && ar_desc_push_ready) begin
          link_fifo_pop_yumi = 1'b1;
          ar_desc_push_v     = 1'b1;
          ar_desc_push_data  = {pkt_beats_r[7:0] - 8'd1, link_fifo_pop_data};
          rx_state_n         = RX_IDLE;
        end
      end

      RX_W: begin
        if (pkt_beats_r == '0) begin
          rx_state_n = RX_IDLE;
        end
        else if (link_fifo_pop_v && w_data_push_ready) begin
          link_fifo_pop_yumi = 1'b1;
          w_data_push_v      = 1'b1;
          if (pkt_beats_r == 13'd1) begin
            rx_state_n  = RX_IDLE;
            pkt_beats_n = '0;
          end
          else begin
            pkt_beats_n = pkt_beats_r - 13'd1;
          end
        end
      end

      RX_R: begin
        if (pkt_beats_r == '0) begin
          rx_state_n = RX_IDLE;
        end
        else if (link_fifo_pop_v && r_data_push_ready) begin
          link_fifo_pop_yumi = 1'b1;
          r_data_push_v      = 1'b1;
          if (pkt_beats_r == 13'd1) begin
            rx_state_n  = RX_IDLE;
            pkt_beats_n = '0;
          end
          else begin
            pkt_beats_n = pkt_beats_r - 13'd1;
          end
        end
      end

      RX_B: begin
        if (link_fifo_pop_v && b_resp_push_ready) begin
          link_fifo_pop_yumi = 1'b1;
          b_resp_push_v      = 1'b1;
          rx_state_n         = RX_IDLE;
        end
      end

      RX_DROP: begin
        if (drop_rem_r == '0) begin
          rx_state_n = RX_IDLE;
        end
        else if (link_fifo_pop_v) begin
          link_fifo_pop_yumi = 1'b1;
          if (drop_rem_r == 13'd1) begin
            rx_state_n = RX_IDLE;
            drop_rem_n = '0;
          end
          else begin
            drop_rem_n = drop_rem_r - 13'd1;
          end
        end
      end

      default: begin
        rx_state_n      = RX_IDLE;
        pkt_opcode_n    = OP_AW;
        pkt_beats_n     = '0;
        drop_rem_n      = '0;
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      rx_state_r      <= RX_IDLE;
      pkt_opcode_r    <= OP_AW;
      pkt_beats_r     <= '0;
      drop_rem_r      <= '0;
      w_active_r      <= 1'b0;
      w_rem_r         <= '0;
      r_active_r      <= 1'b0;
      r_rem_r         <= '0;
    end
    else begin
      rx_state_r      <= rx_state_n;
      pkt_opcode_r    <= pkt_opcode_n;
      pkt_beats_r     <= pkt_beats_n;
      drop_rem_r      <= drop_rem_n;
      w_active_r      <= w_active_n;
      w_rem_r         <= w_rem_n;
      r_active_r      <= r_active_n;
      r_rem_r         <= r_rem_n;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if (rx_state_r == RX_W)
        assert (pkt_beats_r != '0)
          else $error("axi_link_rx entered RX_W with zero remaining beats");

      if (rx_state_r == RX_R)
        assert (pkt_beats_r != '0)
          else $error("axi_link_rx entered RX_R with zero remaining beats");

      if (rx_state_r == RX_DROP)
        assert (drop_rem_r != '0)
          else $error("axi_link_rx entered RX_DROP with zero remaining flits");

      if ((rx_state_r == RX_IDLE) && link_fifo_pop_v && hdr_malformed)
        assert (!(aw_desc_push_v || ar_desc_push_v || w_len_push_v || r_len_push_v
               || w_data_push_v || r_data_push_v || b_resp_push_v))
          else $error("axi_link_rx malformed packet header produced AXI traffic");

      if (w_handshake)
        assert (wlast_o == (w_cur_beats == len_width_lp'(1)))
          else $error("axi_link_rx asserted WLAST away from the final W beat");

      if (r_handshake)
        assert (rlast_o == (r_cur_beats == len_width_lp'(1)))
          else $error("axi_link_rx asserted RLAST away from the final R beat");

      if ((rx_state_r == RX_IDLE) && link_fifo_pop_v && (hdr_opcode == OP_B) && !hdr_malformed)
        assert (hdr_beats == 13'd1)
          else $error("axi_link_rx expects B packets to have exactly one response beat");
    end
  end
`endif

endmodule
