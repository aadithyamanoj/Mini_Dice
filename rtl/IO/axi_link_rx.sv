module axi_link_rx
  #(parameter int flit_width_p        = 32
   ,parameter int addr_width_p        = 16
   ,parameter int link_fifo_els_p     = 8
   ,parameter int aw_desc_fifo_els_p  = 2
   ,parameter int ar_desc_fifo_els_p  = 2
   ,parameter int w_len_fifo_els_p    = 4
   ,parameter int w_data_fifo_els_p   = 8
   ,parameter int r_len_fifo_els_p    = 4
   ,parameter int r_data_fifo_els_p   = 8
   ,parameter int b_resp_fifo_els_p   = 4
   )
  (input  logic                     clk_i
   ,input logic                     reset_i

   ,input  logic                    link_rx_v_i
   ,input  logic [flit_width_p-1:0] link_rx_data_i
   ,output logic                    link_rx_yumi_o

   ,output logic                    awvalid_o
   ,input  logic                    awready_i
   ,output logic [addr_width_p-1:0] awaddr_o
   ,output logic [7:0]              awlen_o
   ,output logic [2:0]              awsize_o
   ,output logic [1:0]              awburst_o

   ,output logic                    wvalid_o
   ,input  logic                    wready_i
   ,output logic [31:0]             wdata_o
   ,output logic                    wlast_o

   ,output logic                    arvalid_o
   ,input  logic                    arready_i
   ,output logic [addr_width_p-1:0] araddr_o
   ,output logic [7:0]              arlen_o
   ,output logic [2:0]              arsize_o
   ,output logic [1:0]              arburst_o

   ,output logic                    rvalid_o
   ,input  logic                    rready_i
   ,output logic [31:0]             rdata_o
   ,output logic [1:0]              rresp_o
   ,output logic                    rlast_o

   ,output logic                    bvalid_o
   ,input  logic                    bready_i
   ,output logic [1:0]              bresp_o
   );

  // --------------------------------------------------------------------------
  // Combined transport packets over a 32-bit flit link.
  //
  // Opcode mapping:
  //   3'b000 = WRITE_REQ
  //   3'b001 = READ_REQ
  //   3'b010 = READ_RESP
  //   3'b011 = WRITE_RESP
  //
  // Header flit layout (32 bits):
  //   [31:29] = opcode
  //   [28:16] = packet length (beats)
  //   [15:0]  = address (request packets only; 16'b0 for responses)
  //
  // RX reconstructs all five AXI channels from the simplified transport:
  //   WRITE_REQ  -> AW + W burst
  //   READ_REQ   -> AR burst
  //   READ_RESP  -> R burst
  //   WRITE_RESP -> B response
  //
  // Strict FIFO assumption:
  //   No AXI IDs or reorder logic exist here. Associations rely purely on
  //   strict FIFO order across combined packets.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32)
      $error("axi_link_rx requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_rx requires addr_width_p=16, got %0d", addr_width_p);
  end

  typedef enum logic [2:0] {
    OP_WRITE_REQ  = 3'b000,
    OP_READ_REQ   = 3'b001,
    OP_READ_RESP  = 3'b010,
    OP_WRITE_RESP = 3'b011
  } pkt_opcode_e;

  typedef enum logic [2:0] {
    RX_IDLE      = 3'd0,
    RX_WR_DATA   = 3'd1,
    RX_R_DATA    = 3'd2,
    RX_R_RESP    = 3'd3,
    RX_B_RESP    = 3'd4,
    RX_DROP      = 3'd5
  } rx_state_e;

  localparam int beat_count_width_lp = 13;
  localparam int drop_count_width_lp = 14;
  localparam int req_desc_width_lp   = addr_width_p + beat_count_width_lp;
  localparam int r_desc_width_lp     = beat_count_width_lp + 2;
  localparam logic [2:0] axi_size_lp  = 3'b010;
  localparam logic [1:0] axi_burst_lp = 2'b01;
  localparam int max_axi_beats_lp     = 256;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [beat_count_width_lp-1:0] beats;
  } req_desc_s;

  typedef struct packed {
    logic [beat_count_width_lp-1:0] beats;
    logic [1:0]                     resp;
  } r_desc_s;

  // --------------------------------------------------------------------------
  // Link ingress FIFO
  // --------------------------------------------------------------------------

  logic        link_fifo_ready_lo;
  logic        link_fifo_v_lo;
  logic [31:0] link_fifo_data_lo;
  logic        link_fifo_yumi_li;

  assign link_rx_yumi_o = link_rx_v_i && link_fifo_ready_lo;

  bsg_fifo_1r1w_small #(
    .width_p            (32),
    .els_p              (link_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) link_ingress_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (link_rx_yumi_o),
    .data_i (link_rx_data_i),
    .ready_o(link_fifo_ready_lo),
    .v_o    (link_fifo_v_lo),
    .data_o (link_fifo_data_lo),
    .yumi_i (link_fifo_yumi_li)
  );

  // --------------------------------------------------------------------------
  // Internal FIFOs
  // --------------------------------------------------------------------------
  // Request and response classes are buffered separately after parsing so the
  // link-facing parser can keep making progress even if one AXI channel is
  // backpressured. The descriptor FIFOs carry burst metadata, while the data
  // FIFOs carry only payload beats.

  logic                        wr_desc_push_v_li, wr_desc_push_ready_lo;
  logic [req_desc_width_lp-1:0] wr_desc_push_data_li;
  logic                        wr_desc_v_lo, wr_desc_yumi_li;
  logic [req_desc_width_lp-1:0] wr_desc_data_lo;

  logic                        rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [req_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                        rd_desc_v_lo, rd_desc_yumi_li;
  logic [req_desc_width_lp-1:0] rd_desc_data_lo;

  logic                        w_data_push_v_li, w_data_push_ready_lo;
  logic [31:0]                 w_data_push_data_li;
  logic                        w_data_v_lo, w_data_yumi_li;
  logic [31:0]                 w_data_lo;

  logic                       r_desc_push_v_li, r_desc_push_ready_lo;
  logic [r_desc_width_lp-1:0] r_desc_push_data_li;
  logic                       r_desc_v_lo, r_desc_yumi_li;
  logic [r_desc_width_lp-1:0] r_desc_data_lo;

  logic                        r_data_push_v_li, r_data_push_ready_lo;
  logic [31:0]                 r_data_push_data_li;
  logic                        r_data_v_lo, r_data_yumi_li;
  logic [31:0]                 r_data_lo;

  logic                      b_resp_push_v_li, b_resp_push_ready_lo;
  logic [1:0]                b_resp_push_data_li;
  logic                      b_resp_v_lo, b_resp_yumi_li;
  logic [1:0]                b_resp_lo;

  bsg_fifo_1r1w_small #(
    .width_p            (req_desc_width_lp),
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
    .width_p            (req_desc_width_lp),
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

  // --------------------------------------------------------------------------
  // Parser FSM
  // --------------------------------------------------------------------------
  // The parser consumes exactly one packet at a time from the ingress FIFO.
  // Long payloads are streamed into small FIFOs as flits arrive; there is no
  // need to store an entire WRITE_REQ or READ_RESP packet in registers.

  rx_state_e state_r, state_n;
  logic [beat_count_width_lp-1:0] cur_beats_r, cur_beats_n;
  logic [beat_count_width_lp-1:0] r_pkt_beats_r, r_pkt_beats_n;
  logic [drop_count_width_lp-1:0] payload_rem_r, payload_rem_n;

  logic [2:0]                     hdr_opcode;
  logic [beat_count_width_lp-1:0] hdr_len;
  logic [addr_width_p-1:0]        hdr_addr;
  logic                           hdr_len_valid;

  assign hdr_opcode    = link_fifo_data_lo[31:29];
  assign hdr_len       = link_fifo_data_lo[28:16];
  assign hdr_addr      = link_fifo_data_lo[15:0];
  assign hdr_len_valid = (hdr_len != '0) && (hdr_len <= beat_count_width_lp'(max_axi_beats_lp));

  always_comb begin
    state_n           = state_r;
    cur_beats_n       = cur_beats_r;
    r_pkt_beats_n     = r_pkt_beats_r;
    payload_rem_n     = payload_rem_r;

    link_fifo_yumi_li = 1'b0;

    wr_desc_push_v_li    = 1'b0;
    wr_desc_push_data_li = '0;
    rd_desc_push_v_li    = 1'b0;
    rd_desc_push_data_li = '0;
    w_data_push_v_li     = 1'b0;
    w_data_push_data_li  = link_fifo_data_lo;
    r_desc_push_v_li     = 1'b0;
    r_desc_push_data_li  = '0;
    r_data_push_v_li     = 1'b0;
    r_data_push_data_li  = link_fifo_data_lo;
    b_resp_push_v_li     = 1'b0;
    b_resp_push_data_li  = link_fifo_data_lo[1:0];

    unique case (state_r)
      RX_IDLE: begin
        if (link_fifo_v_lo) begin
          unique case (hdr_opcode)
            OP_WRITE_REQ: begin
              // Header carries {opcode,len,addr}. Publish the AW descriptor
              // immediately and stream `len` W payload beats next.
              if (hdr_len_valid && wr_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                wr_desc_push_v_li    = 1'b1;
                wr_desc_push_data_li = {hdr_addr, hdr_len};
                cur_beats_n          = hdr_len;
                payload_rem_n        = drop_count_width_lp'({1'b0, hdr_len});
                state_n              = RX_WR_DATA;
              end
              else if (!hdr_len_valid) begin
                link_fifo_yumi_li = 1'b1;
                state_n           = RX_DROP;
                payload_rem_n     = drop_count_width_lp'({1'b0, hdr_len});
              end
            end

            OP_READ_REQ: begin
              // READ_REQ has no payload; one header flit publishes AR directly.
              if (hdr_len_valid && rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = {hdr_addr, hdr_len};
                state_n              = RX_IDLE;
              end
              else if (!hdr_len_valid) begin
                link_fifo_yumi_li = 1'b1;
                state_n           = RX_DROP;
                payload_rem_n     = '0;
              end
            end

            OP_READ_RESP: begin
              // Next come `len` R data beats followed by one padded RRESP flit.
              link_fifo_yumi_li = 1'b1;
              cur_beats_n       = hdr_len;
              r_pkt_beats_n     = hdr_len;
              if (hdr_len_valid)
                state_n = RX_R_DATA;
              else begin
                state_n       = RX_DROP;
                payload_rem_n = drop_count_width_lp'({1'b0, hdr_len}) + drop_count_width_lp'(1);
              end
            end

            OP_WRITE_RESP: begin
              // WRITE_RESP must always carry exactly one padded BRESP flit.
              link_fifo_yumi_li = 1'b1;
              if (hdr_len == beat_count_width_lp'(1))
                state_n = RX_B_RESP;
              else begin
                state_n       = RX_DROP;
                payload_rem_n = (hdr_len == '0)
                                ? drop_count_width_lp'(1)
                                : drop_count_width_lp'({1'b0, hdr_len});
              end
            end

            default: begin
              link_fifo_yumi_li = 1'b1;
              state_n           = RX_DROP;
              payload_rem_n     = drop_count_width_lp'({1'b0, hdr_len});
            end
          endcase
        end
      end

      RX_WR_DATA: begin
        if (link_fifo_v_lo && w_data_push_ready_lo) begin
          // WRITE_REQ payload flits stream directly into the W data FIFO.
          link_fifo_yumi_li = 1'b1;
          w_data_push_v_li  = 1'b1;
          if (payload_rem_r == drop_count_width_lp'(1)) begin
            payload_rem_n = '0;
            state_n       = RX_IDLE;
          end
          else begin
            payload_rem_n = payload_rem_r - drop_count_width_lp'(1);
          end
        end
      end

      RX_R_DATA: begin
        if (link_fifo_v_lo && r_data_push_ready_lo) begin
          // READ_RESP data beats stream into the R data FIFO first.
          link_fifo_yumi_li = 1'b1;
          r_data_push_v_li  = 1'b1;
          if (cur_beats_r == beat_count_width_lp'(1)) begin
            cur_beats_n = '0;
            state_n     = RX_R_RESP;
          end
          else begin
            cur_beats_n = cur_beats_r - beat_count_width_lp'(1);
          end
        end
      end

      RX_R_RESP: begin
        if (link_fifo_v_lo && r_desc_push_ready_lo) begin
          // The final padded response flit supplies one shared RRESP code for
          // the whole reconstructed burst.
          link_fifo_yumi_li   = 1'b1;
          r_desc_push_v_li    = 1'b1;
          r_desc_push_data_li = {r_pkt_beats_r, link_fifo_data_lo[1:0]};
          state_n             = RX_IDLE;
        end
      end

      RX_B_RESP: begin
        if (link_fifo_v_lo && b_resp_push_ready_lo) begin
          // BRESP is transported in the low bits of one padded flit.
          link_fifo_yumi_li = 1'b1;
          b_resp_push_v_li  = 1'b1;
          state_n           = RX_IDLE;
        end
      end

      RX_DROP: begin
        // Malformed packets are dropped by consuming the remaining payload
        // flits, which keeps the parser aligned to the next header.
        if (payload_rem_r == '0) begin
          state_n = RX_IDLE;
        end
        else if (link_fifo_v_lo) begin
          link_fifo_yumi_li = 1'b1;
          if (payload_rem_r == drop_count_width_lp'(1)) begin
            payload_rem_n = '0;
            state_n       = RX_IDLE;
          end
          else begin
            payload_rem_n = payload_rem_r - drop_count_width_lp'(1);
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      state_r       <= RX_IDLE;
      cur_beats_r   <= '0;
      r_pkt_beats_r <= '0;
      payload_rem_r <= '0;
    end
    else begin
      state_r       <= state_n;
      cur_beats_r   <= cur_beats_n;
      r_pkt_beats_r <= r_pkt_beats_n;
      payload_rem_r <= payload_rem_n;
    end
  end

  // --------------------------------------------------------------------------
  // AXI AW/W reconstruction
  // --------------------------------------------------------------------------
  // AW and W are replayed from one combined descriptor FIFO plus one W data
  // FIFO. A write burst is not allowed to start sending W beats until its
  // matching AW descriptor has been issued, which preserves FIFO pairing.

  req_desc_s wr_desc_cast;
  assign wr_desc_cast = req_desc_s'(wr_desc_data_lo);

  logic write_active_r, write_active_n;
  logic [beat_count_width_lp-1:0] write_beats_left_r, write_beats_left_n;
  logic aw_handshake, w_handshake;

  assign awvalid_o = wr_desc_v_lo && !write_active_r;
  assign awaddr_o  = wr_desc_cast.addr;
  assign awlen_o   = wr_desc_cast.beats[7:0] - 8'd1;
  assign awsize_o  = axi_size_lp;
  assign awburst_o = axi_burst_lp;

  assign aw_handshake = awvalid_o && awready_i;

  assign wvalid_o = write_active_r && w_data_v_lo;
  assign wdata_o  = w_data_lo;
  assign wlast_o  = write_active_r && (write_beats_left_r == beat_count_width_lp'(1));
  assign w_handshake = wvalid_o && wready_i;

  assign wr_desc_yumi_li = w_handshake && (write_beats_left_r == beat_count_width_lp'(1));
  assign w_data_yumi_li  = w_handshake;

  always_comb begin
    // `write_active_r` marks that AW for the current combined write packet has
    // already been accepted and we are now draining its W payload beats.
    write_active_n     = write_active_r;
    write_beats_left_n = write_beats_left_r;

    if (aw_handshake) begin
      write_active_n     = 1'b1;
      write_beats_left_n = wr_desc_cast.beats;
    end

    if (w_handshake) begin
      if (write_beats_left_r == beat_count_width_lp'(1)) begin
        write_active_n     = 1'b0;
        write_beats_left_n = '0;
      end
      else begin
        write_beats_left_n = write_beats_left_r - beat_count_width_lp'(1);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      write_active_r     <= 1'b0;
      write_beats_left_r <= '0;
    end
    else begin
      write_active_r     <= write_active_n;
      write_beats_left_r <= write_beats_left_n;
    end
  end

  // --------------------------------------------------------------------------
  // AXI AR reconstruction
  // --------------------------------------------------------------------------
  // READ_REQ packets replay directly as AR bursts because they carry only one
  // address flit plus the burst length from the header.

  req_desc_s rd_desc_cast;
  assign rd_desc_cast = req_desc_s'(rd_desc_data_lo);

  assign arvalid_o = rd_desc_v_lo;
  assign araddr_o  = rd_desc_cast.addr;
  assign arlen_o   = rd_desc_cast.beats[7:0] - 8'd1;
  assign arsize_o  = axi_size_lp;
  assign arburst_o = axi_burst_lp;
  assign rd_desc_yumi_li = arvalid_o && arready_i;

  // --------------------------------------------------------------------------
  // AXI R reconstruction
  // --------------------------------------------------------------------------
  // READ_RESP replay uses one descriptor FIFO carrying `{beats,rresp}` and one
  // R data FIFO carrying the actual data beats. The descriptor is held once at
  // burst start, then the local counter generates RLAST on the final beat.

  r_desc_s r_desc_cast;
  assign r_desc_cast = r_desc_s'(r_desc_data_lo);

  logic r_active_r, r_active_n;
  logic [beat_count_width_lp-1:0] r_beats_left_r, r_beats_left_n;
  logic [1:0]                     r_resp_hold_r, r_resp_hold_n;
  logic r_start_burst;
  logic r_handshake;

  assign r_start_burst = !r_active_r && r_desc_v_lo && r_data_v_lo;
  assign rvalid_o      = (r_active_r || r_start_burst) && r_data_v_lo;
  assign rdata_o       = r_data_lo;
  assign rresp_o       = r_active_r ? r_resp_hold_r : r_desc_cast.resp;
  assign rlast_o       = r_active_r
                         ? (r_beats_left_r == beat_count_width_lp'(1))
                         : (r_desc_cast.beats == beat_count_width_lp'(1));
  assign r_handshake   = rvalid_o && rready_i;

  assign r_desc_yumi_li = r_start_burst;
  assign r_data_yumi_li = r_handshake;

  always_comb begin
    // Once an R burst starts, the descriptor state is held locally until the
    // final beat is accepted on the AXI R channel.
    r_active_n     = r_active_r;
    r_beats_left_n = r_beats_left_r;
    r_resp_hold_n  = r_resp_hold_r;

    if (r_start_burst) begin
      r_active_n     = 1'b1;
      r_beats_left_n = r_desc_cast.beats;
      r_resp_hold_n  = r_desc_cast.resp;
    end

    if (r_handshake) begin
      if ((r_active_r ? r_beats_left_r : r_desc_cast.beats) == beat_count_width_lp'(1)) begin
        r_active_n     = 1'b0;
        r_beats_left_n = '0;
      end
      else begin
        r_beats_left_n = (r_active_r ? r_beats_left_r : r_desc_cast.beats) - beat_count_width_lp'(1);
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      r_active_r     <= 1'b0;
      r_beats_left_r <= '0;
      r_resp_hold_r  <= '0;
    end
    else begin
      r_active_r     <= r_active_n;
      r_beats_left_r <= r_beats_left_n;
      r_resp_hold_r  <= r_resp_hold_n;
    end
  end

  // --------------------------------------------------------------------------
  // AXI B reconstruction
  // --------------------------------------------------------------------------
  // Each WRITE_RESP packet becomes exactly one AXI B beat.

  assign bvalid_o       = b_resp_v_lo;
  assign bresp_o        = b_resp_lo;
  assign b_resp_yumi_li = bvalid_o && bready_i;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if ((state_r == RX_WR_DATA) && (payload_rem_r == '0))
        $error("axi_link_rx parser inconsistent in RX_WR_DATA");

      if (awvalid_o && (wr_desc_cast.beats == '0))
        $error("axi_link_rx attempted zero-length AW burst");

      if (arvalid_o && (rd_desc_cast.beats == '0))
        $error("axi_link_rx attempted zero-length AR burst");

      if (w_handshake && (wlast_o != (write_beats_left_r == beat_count_width_lp'(1))))
        $error("axi_link_rx WLAST misaligned with stored write descriptor");

      if (r_handshake && (rlast_o != ((r_active_r ? r_beats_left_r : r_desc_cast.beats) == beat_count_width_lp'(1))))
        $error("axi_link_rx RLAST misaligned with stored READ_RESP length");
    end
  end
`endif

endmodule
