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
   ,output logic [13:0]             aruser_o

   ,output logic                    rvalid_o
   ,input  logic                    rready_i
   ,output logic [31:0]             rdata_o
   ,output logic [1:0]              rresp_o
   ,output logic                    rlast_o
   );

  // --------------------------------------------------------------------------
  // Combined transport packets over a 32-bit flit link.
  //
  // Opcode mapping:
  //   2'b00 = WRITE_REQ
  //   2'b01 = FETCH_REQ
  //   2'b10 = READ_RESP
  //   2'b11 = LOAD_REQ
  //
  // Header flit layout (32 bits):
  //   WRITE_REQ : [31:30] opcode, [29:24] reserved, [23:16] AXI-style awlen,  [15:0] address
  //   FETCH_REQ : [31:30] opcode, [29:24] reserved, [23:16] AXI-style arlen,  [15:0] address
  //   LOAD_REQ  : [31:30] opcode, [29]    reserved, [28:16] aruser[12:0],     [15:0] address
  //               AR fires once (arlen=0) with aruser_o[12:0] =
  //               header[28:16] and aruser_o[13] = 1 (the meta flag is
  //               recovered from the opcode, not the wire bits).
  //   READ_RESP : [31:30] opcode, [29:24] reserved, [23:16] AXI-style rlen,   [15:0] reserved
  //
  // Length encoding follows AXI semantics: the wire `len` field carries
  // (beats - 1) in 8 bits, i.e. 0..255 representing 1..256 beats. AXI
  // burst length max is 256, so 8 bits suffice.
  //
  // RRESP is intentionally not carried by this link, mirroring the dropped
  // B channel. rresp_o is driven to RESP_OKAY (2'b00) for every beat;
  // per-read error reporting is therefore lost.
  //
  // RX reconstructs four AXI channels from the simplified transport:
  //   WRITE_REQ  -> AW + W burst
  //   FETCH_REQ  -> AR burst
  //   LOAD_REQ   -> AR single beat with aruser_o[13]=1
  //   READ_RESP  -> R burst
  //
  // The B (write-response) channel is intentionally not driven here; the
  // upstream wrapper synthesizes a fake B beat per accepted write so the
  // local AXI master sees write completion without the link round-trip.
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

  typedef enum logic [1:0] {
    OP_WRITE_REQ  = 2'b00,
    OP_FETCH_REQ  = 2'b01,
    OP_READ_RESP  = 2'b10,
    OP_LOAD_REQ   = 2'b11
  } pkt_opcode_e;

  typedef enum logic [2:0] {
    RX_IDLE      = 3'd0,
    RX_WR_DATA   = 3'd1,
    RX_R_DATA    = 3'd2,
    RX_DROP      = 3'd3
  } rx_state_e;

  localparam int beat_count_width_lp   = 9;   // beats counter range 1..256
  localparam int meta_aruser_width_lp  = 13;  // META aruser payload width
  localparam int drop_count_width_lp   = 9;
  localparam int req_desc_width_lp     = addr_width_p + beat_count_width_lp;
  localparam int rd_req_desc_width_lp  = addr_width_p + 1 + meta_aruser_width_lp;
  localparam int r_desc_width_lp       = beat_count_width_lp;
  localparam logic [2:0] axi_size_lp   = 3'b010;
  localparam logic [1:0] axi_burst_lp  = 2'b01;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [beat_count_width_lp-1:0] beats;
  } req_desc_s;

  // For FETCH_REQ, payload[8:0] is the AXI burst length as beats (1..256),
  // zero-extended to meta_aruser_width_lp. For LOAD_REQ, payload[12:0] is the
  // 13-bit aruser carried in the LOAD_REQ header.
  typedef struct packed {
    logic [addr_width_p-1:0]          addr;
    logic                             is_meta;
    logic [meta_aruser_width_lp-1:0]  payload;
  } rd_req_desc_s;

  typedef struct packed {
    logic [beat_count_width_lp-1:0] beats;
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

  logic                            rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [rd_req_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                            rd_desc_v_lo, rd_desc_yumi_li;
  logic [rd_req_desc_width_lp-1:0] rd_desc_data_lo;

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
    .width_p            (rd_req_desc_width_lp),
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

  // --------------------------------------------------------------------------
  // Parser FSM
  // --------------------------------------------------------------------------
  // The parser consumes exactly one packet at a time from the ingress FIFO.
  // Long payloads are streamed into small FIFOs as flits arrive; there is no
  // need to store an entire WRITE_REQ or READ_RESP packet in registers.

  rx_state_e state_r, state_n;
  logic [beat_count_width_lp-1:0] cur_beats_r, cur_beats_n;
  logic [drop_count_width_lp-1:0] payload_rem_r, payload_rem_n;

  logic [1:0]                       hdr_opcode;
  logic [7:0]                       hdr_len_axi;   // AXI-style len for non-META
  logic [beat_count_width_lp-1:0]   hdr_beats;     // beats count (= hdr_len_axi + 1)
  logic [meta_aruser_width_lp-1:0]  hdr_aruser;    // 13-bit META aruser payload
  logic [addr_width_p-1:0]          hdr_addr;

  assign hdr_opcode   = link_fifo_data_lo[31:30];
  assign hdr_len_axi  = link_fifo_data_lo[23:16];
  assign hdr_beats    = {1'b0, hdr_len_axi} + beat_count_width_lp'(1);
  assign hdr_aruser   = link_fifo_data_lo[28:16];
  assign hdr_addr     = link_fifo_data_lo[15:0];

  always_comb begin
    state_n           = state_r;
    cur_beats_n       = cur_beats_r;
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

    unique case (state_r)
      RX_IDLE: begin
        if (link_fifo_v_lo) begin
          unique case (hdr_opcode)
            OP_WRITE_REQ: begin
              // Header carries {opcode,axi_len,addr}. Publish the AW descriptor
              // immediately and stream `hdr_beats` W payload flits next.
              if (wr_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                wr_desc_push_v_li    = 1'b1;
                wr_desc_push_data_li = {hdr_addr, hdr_beats};
                cur_beats_n          = hdr_beats;
                payload_rem_n        = drop_count_width_lp'(hdr_beats);
                state_n              = RX_WR_DATA;
              end
            end

            OP_FETCH_REQ: begin
              // FETCH_REQ has no payload; one header flit publishes AR directly.
              // hdr_beats (9 bits) is zero-extended into the wider payload slot.
              if (rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = {hdr_addr, 1'b0, meta_aruser_width_lp'(hdr_beats)};
                state_n              = RX_IDLE;
              end
            end

            OP_LOAD_REQ: begin
              // LOAD_REQ has no payload; AR fires once and the header's
              // middle 13 bits are forwarded verbatim onto aruser_o.
              if (rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = {hdr_addr, 1'b1, hdr_aruser};
                state_n              = RX_IDLE;
              end
            end

            OP_READ_RESP: begin
              // Header carries only the response length; rresp_o is locally
              // driven to RESP_OKAY (the link no longer transports RRESP).
              if (r_desc_push_ready_lo) begin
                link_fifo_yumi_li   = 1'b1;
                r_desc_push_v_li    = 1'b1;
                r_desc_push_data_li = hdr_beats;
                cur_beats_n         = hdr_beats;
                state_n             = RX_R_DATA;
              end
            end

            default: begin
              // Unknown opcode. Drop just the header flit and resync on the
              // next header; we can't trust hdr_beats since the layout is
              // unknown.
              link_fifo_yumi_li = 1'b1;
              state_n           = RX_DROP;
              payload_rem_n     = '0;
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
          // READ_RESP data beats stream into the R data FIFO first; AXI R can
          // begin replaying before the full burst has arrived because the
          // descriptor was published from the header.
          link_fifo_yumi_li = 1'b1;
          r_data_push_v_li  = 1'b1;
          if (cur_beats_r == beat_count_width_lp'(1)) begin
            cur_beats_n = '0;
            state_n     = RX_IDLE;
          end
          else begin
            cur_beats_n = cur_beats_r - beat_count_width_lp'(1);
          end
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
      payload_rem_r <= '0;
    end
    else begin
      state_r       <= state_n;
      cur_beats_r   <= cur_beats_n;
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
  // FETCH_REQ packets replay directly as AR bursts because they carry only one
  // address flit plus the burst length from the header. LOAD_REQ packets
  // replay as a single-beat AR with aruser passthrough.

  rd_req_desc_s rd_desc_cast;
  assign rd_desc_cast = rd_req_desc_s'(rd_desc_data_lo);

  assign arvalid_o = rd_desc_v_lo;
  assign araddr_o  = rd_desc_cast.addr;
  assign arlen_o   = rd_desc_cast.is_meta ? 8'd0
                     : (rd_desc_cast.payload[7:0] - 8'd1);
  assign arsize_o  = axi_size_lp;
  assign arburst_o = axi_burst_lp;
  // aruser_o[13] is the recovered meta flag (derived from opcode);
  // aruser_o[12:0] is the metadata payload from the LOAD_REQ header,
  // or zero for a FETCH_REQ.
  assign aruser_o  = {rd_desc_cast.is_meta,
                      rd_desc_cast.is_meta ? rd_desc_cast.payload
                                           : meta_aruser_width_lp'(1'b0)};
  assign rd_desc_yumi_li = arvalid_o && arready_i;

  // --------------------------------------------------------------------------
  // AXI R reconstruction
  // --------------------------------------------------------------------------
  // READ_RESP replay uses one descriptor FIFO carrying just `beats` and one
  // R data FIFO carrying the actual data beats. The descriptor is held once at
  // burst start, then the local counter generates RLAST on the final beat.
  // rresp_o is locally driven to RESP_OKAY since the link does not transport
  // per-read response status.

  r_desc_s r_desc_cast;
  assign r_desc_cast = r_desc_s'(r_desc_data_lo);

  logic r_active_r, r_active_n;
  logic [beat_count_width_lp-1:0] r_beats_left_r, r_beats_left_n;
  logic r_start_burst;
  logic r_handshake;

  assign r_start_burst = !r_active_r && r_desc_v_lo && r_data_v_lo;
  assign rvalid_o      = (r_active_r || r_start_burst) && r_data_v_lo;
  assign rdata_o       = r_data_lo;
  assign rresp_o       = 2'b00;  // RESP_OKAY — link does not carry rresp
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

    if (r_start_burst) begin
      r_active_n     = 1'b1;
      r_beats_left_n = r_desc_cast.beats;
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
    end
    else begin
      r_active_r     <= r_active_n;
      r_beats_left_r <= r_beats_left_n;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if ((state_r == RX_WR_DATA) && (payload_rem_r == '0))
        $error("axi_link_rx parser inconsistent in RX_WR_DATA");

      if (awvalid_o && (wr_desc_cast.beats == '0))
        $error("axi_link_rx attempted zero-length AW burst");

      if (arvalid_o && !rd_desc_cast.is_meta && (rd_desc_cast.payload == '0))
        $error("axi_link_rx attempted zero-length AR burst");

      if (w_handshake && (wlast_o != (write_beats_left_r == beat_count_width_lp'(1))))
        $error("axi_link_rx WLAST misaligned with stored write descriptor");

      if (r_handshake && (rlast_o != ((r_active_r ? r_beats_left_r : r_desc_cast.beats) == beat_count_width_lp'(1))))
        $error("axi_link_rx RLAST misaligned with stored READ_RESP length");
    end
  end
`endif

endmodule
