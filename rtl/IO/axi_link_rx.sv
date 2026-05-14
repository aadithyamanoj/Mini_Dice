module axi_link_rx
  #(parameter int flit_width_p        = 32
   ,parameter int addr_width_p        = 16
   ,parameter int link_fifo_els_p     = 8
   ,parameter int aw_desc_fifo_els_p  = 2
   ,parameter int ar_desc_fifo_els_p  = 2
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
   ,output logic [2:0]              awsize_o
   ,output logic [1:0]              awburst_o

   ,output logic                    wvalid_o
   ,input  logic                    wready_i
   ,output logic [31:0]             wdata_o

   ,output logic                    arvalid_o
   ,input  logic                    arready_i
   ,output logic [addr_width_p-1:0] araddr_o
   ,output logic [7:0]              arlen_o
   ,output logic [2:0]              arsize_o
   ,output logic [1:0]              arburst_o
   ,output logic [13:0]             aruser_o
   ,output logic [2:0]              arid_o

   ,output logic                    rvalid_o
   ,input  logic                    rready_i
   ,output logic [31:0]             rdata_o
   ,output logic [1:0]              rresp_o
   ,output logic                    rlast_o
   ,output logic [2:0]              rid_o
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
  //   WRITE_REQ : [31:30] opcode, [29:16] reserved,                                              [15:0] address
  //   FETCH_REQ : [31:30] opcode, [29:27] reserved, [26:24] arid[2:0], [23:16] AXI-style arlen,  [15:0] address
  //   LOAD_REQ  : two-flit packet:
  //               flit 0: [31:30] opcode, [29:27] reserved, [26:24] arid[2:0], [23:16] reserved, [15:0] address
  //               flit 1: [31:13] reserved, [12:0] aruser[12:0]
  //   READ_RESP : [31:30] opcode, [29:27] reserved, [26:24] rid[2:0],  [23:16] AXI-style rlen,   [15:0] reserved
  //
  // The link carries a 3-bit port ID with every read request and read
  // response. AR/R reconstruction drives arid_o / rid_o from the wire so
  // upstream demux can route responses to the correct master port without
  // needing a local id-tracking FIFO.
  //
  // WRITE_REQ is single-beat only: header + exactly one 32-bit W payload flit.
  // LOAD_REQ is single-beat by definition (arlen=0 reconstructed locally).
  //
  // FETCH_REQ / READ_RESP length encoding still follows AXI semantics: the
  // wire `len` field carries (beats - 1) in 8 bits.
  //
  // RRESP is intentionally not carried; rresp_o is driven RESP_OKAY for every
  // beat. The B (write-response) channel is also not driven here.
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
    RX_DROP      = 3'd3,
    RX_LOAD_EXT  = 3'd4   // waiting for LOAD_REQ aruser-extension flit
  } rx_state_e;

  localparam int portid_width_lp       = 3;
  localparam int beat_count_width_lp   = 9;   // reads only
  localparam int meta_aruser_width_lp  = 13;
  localparam int drop_count_width_lp   = 9;
  localparam int rd_req_desc_width_lp  = addr_width_p + 1 + portid_width_lp + meta_aruser_width_lp;
  localparam int r_desc_width_lp       = portid_width_lp + beat_count_width_lp;
  localparam logic [2:0] axi_size_lp   = 3'b010;
  localparam logic [1:0] axi_burst_lp  = 2'b01;

  typedef struct packed {
    logic [addr_width_p-1:0]          addr;
    logic                             is_meta;
    logic [portid_width_lp-1:0]       arid;
    logic [meta_aruser_width_lp-1:0]  payload;
  } rd_req_desc_s;

  typedef struct packed {
    logic [portid_width_lp-1:0]      rid;
    logic [beat_count_width_lp-1:0]  beats;
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

  logic                            wr_desc_push_v_li, wr_desc_push_ready_lo;
  logic [addr_width_p-1:0]         wr_desc_push_data_li;
  logic                            wr_desc_v_lo, wr_desc_yumi_li;
  logic [addr_width_p-1:0]         wr_desc_data_lo;

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
    .width_p            (addr_width_p),
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

  rx_state_e state_r, state_n;
  logic [beat_count_width_lp-1:0] cur_beats_r, cur_beats_n;
  logic [drop_count_width_lp-1:0] payload_rem_r, payload_rem_n;

  // Temp registers spanning LOAD_REQ flit 0 → flit 1.
  logic [addr_width_p-1:0]    load_addr_r, load_addr_n;
  logic [portid_width_lp-1:0] load_arid_r, load_arid_n;

  logic [1:0]                       hdr_opcode;
  logic [7:0]                       hdr_len_axi;
  logic [beat_count_width_lp-1:0]   hdr_beats;
  logic [portid_width_lp-1:0]       hdr_portid;
  logic [meta_aruser_width_lp-1:0]  ext_aruser;
  logic [addr_width_p-1:0]          hdr_addr;

  assign hdr_opcode   = link_fifo_data_lo[31:30];
  assign hdr_portid   = link_fifo_data_lo[26:24];
  assign hdr_len_axi  = link_fifo_data_lo[23:16];
  assign hdr_beats    = {1'b0, hdr_len_axi} + beat_count_width_lp'(1);
  assign hdr_addr     = link_fifo_data_lo[15:0];
  assign ext_aruser   = link_fifo_data_lo[meta_aruser_width_lp-1:0];

  always_comb begin
    state_n           = state_r;
    cur_beats_n       = cur_beats_r;
    payload_rem_n     = payload_rem_r;
    load_addr_n       = load_addr_r;
    load_arid_n       = load_arid_r;

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
              // Single-beat: header carries only addr. One W payload flit
              // follows; publish the AW descriptor immediately.
              if (wr_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                wr_desc_push_v_li    = 1'b1;
                wr_desc_push_data_li = hdr_addr;
                state_n              = RX_WR_DATA;
              end
            end

            OP_FETCH_REQ: begin
              // FETCH_REQ is a single header flit. Publish AR with the wire
              // ARID and the burst length zero-extended into the payload slot.
              if (rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = {hdr_addr, 1'b0, hdr_portid,
                                        meta_aruser_width_lp'(hdr_beats)};
                state_n              = RX_IDLE;
              end
            end

            OP_LOAD_REQ: begin
              // LOAD_REQ is two flits: header + aruser extension. Consume
              // the header here, latch addr/arid, then wait for the
              // extension flit in RX_LOAD_EXT to publish the rd_desc.
              link_fifo_yumi_li = 1'b1;
              load_addr_n       = hdr_addr;
              load_arid_n       = hdr_portid;
              state_n           = RX_LOAD_EXT;
            end

            OP_READ_RESP: begin
              // Header carries response length and the matching RID. rresp_o
              // is locally driven to RESP_OKAY (the link no longer transports
              // rresp).
              if (r_desc_push_ready_lo) begin
                link_fifo_yumi_li   = 1'b1;
                r_desc_push_v_li    = 1'b1;
                r_desc_push_data_li = {hdr_portid, hdr_beats};
                cur_beats_n         = hdr_beats;
                state_n             = RX_R_DATA;
              end
            end

            default: begin
              // Unknown opcode. Drop just the header flit and resync on the
              // next header.
              link_fifo_yumi_li = 1'b1;
              state_n           = RX_DROP;
              payload_rem_n     = '0;
            end
          endcase
        end
      end

      RX_WR_DATA: begin
        // Single-beat: consume exactly one W payload flit and return to IDLE.
        if (link_fifo_v_lo && w_data_push_ready_lo) begin
          link_fifo_yumi_li = 1'b1;
          w_data_push_v_li  = 1'b1;
          state_n           = RX_IDLE;
        end
      end

      RX_LOAD_EXT: begin
        // Consume the aruser-extension flit and publish the LOAD AR descriptor
        // with the captured addr/arid plus the wire-carried aruser payload.
        if (link_fifo_v_lo && rd_desc_push_ready_lo) begin
          link_fifo_yumi_li    = 1'b1;
          rd_desc_push_v_li    = 1'b1;
          rd_desc_push_data_li = {load_addr_r, 1'b1, load_arid_r, ext_aruser};
          state_n              = RX_IDLE;
        end
      end

      RX_R_DATA: begin
        if (link_fifo_v_lo && r_data_push_ready_lo) begin
          // READ_RESP data beats stream into the R data FIFO; AXI R can begin
          // replaying before the full burst has arrived because the
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
        // Malformed packets are dropped by consuming any remaining payload
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
      load_addr_r   <= '0;
      load_arid_r   <= '0;
    end
    else begin
      state_r       <= state_n;
      cur_beats_r   <= cur_beats_n;
      payload_rem_r <= payload_rem_n;
      load_addr_r   <= load_addr_n;
      load_arid_r   <= load_arid_n;
    end
  end

  // --------------------------------------------------------------------------
  // AXI AW/W reconstruction
  // --------------------------------------------------------------------------
  // Single-beat: AW fires when a wr_desc is queued; once accepted, the
  // matching W beat is offered as soon as the payload flit is in the W data
  // FIFO. wr_desc and w_data are consumed together on the W handshake.

  logic write_active_r, write_active_n;
  logic aw_handshake, w_handshake;

  assign awvalid_o = wr_desc_v_lo && !write_active_r;
  assign awaddr_o  = wr_desc_data_lo;
  assign awsize_o  = axi_size_lp;
  assign awburst_o = axi_burst_lp;
  assign aw_handshake = awvalid_o && awready_i;

  assign wvalid_o = write_active_r && w_data_v_lo;
  assign wdata_o  = w_data_lo;
  assign w_handshake = wvalid_o && wready_i;

  assign wr_desc_yumi_li = w_handshake;
  assign w_data_yumi_li  = w_handshake;

  always_comb begin
    write_active_n = write_active_r;
    if (aw_handshake) write_active_n = 1'b1;
    if (w_handshake)  write_active_n = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) write_active_r <= 1'b0;
    else         write_active_r <= write_active_n;
  end

  // --------------------------------------------------------------------------
  // AXI AR reconstruction
  // --------------------------------------------------------------------------
  // FETCH_REQ replays directly as an AR burst (length from the header).
  // LOAD_REQ replays as a single-beat AR with aruser passthrough. The
  // wire-carried ARID is driven onto arid_o so the upstream slave port can
  // preserve it for response routing.

  rd_req_desc_s rd_desc_cast;
  assign rd_desc_cast = rd_req_desc_s'(rd_desc_data_lo);

  assign arvalid_o = rd_desc_v_lo;
  assign araddr_o  = rd_desc_cast.addr;
  assign arlen_o   = rd_desc_cast.is_meta ? 8'd0
                     : (rd_desc_cast.payload[7:0] - 8'd1);
  assign arsize_o  = axi_size_lp;
  assign arburst_o = axi_burst_lp;
  // aruser_o[13] is the recovered meta flag (derived from opcode);
  // aruser_o[12:0] is the metadata payload from the LOAD_REQ extension flit,
  // or zero for a FETCH_REQ.
  assign aruser_o  = {rd_desc_cast.is_meta,
                      rd_desc_cast.is_meta ? rd_desc_cast.payload
                                           : meta_aruser_width_lp'(1'b0)};
  assign arid_o    = rd_desc_cast.arid;
  assign rd_desc_yumi_li = arvalid_o && arready_i;

  // --------------------------------------------------------------------------
  // AXI R reconstruction
  // --------------------------------------------------------------------------

  r_desc_s r_desc_cast;
  assign r_desc_cast = r_desc_s'(r_desc_data_lo);

  logic r_active_r, r_active_n;
  logic [beat_count_width_lp-1:0] r_beats_left_r, r_beats_left_n;
  logic r_start_burst;
  logic r_handshake;

  assign r_start_burst = !r_active_r && r_desc_v_lo && r_data_v_lo;
  assign rvalid_o      = (r_active_r || r_start_burst) && r_data_v_lo;
  assign rdata_o       = r_data_lo;
  assign rresp_o       = 2'b00;
  assign rlast_o       = r_active_r
                         ? (r_beats_left_r == beat_count_width_lp'(1))
                         : (r_desc_cast.beats == beat_count_width_lp'(1));
  assign rid_o         = r_desc_cast.rid;
  assign r_handshake   = rvalid_o && rready_i;

  assign r_desc_yumi_li = r_handshake && rlast_o;
  assign r_data_yumi_li = r_handshake;

  always_comb begin
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
      if (arvalid_o && !rd_desc_cast.is_meta && (rd_desc_cast.payload == '0))
        $error("axi_link_rx attempted zero-length AR burst");

      if (r_handshake && (rlast_o != ((r_active_r ? r_beats_left_r : r_desc_cast.beats) == beat_count_width_lp'(1))))
        $error("axi_link_rx RLAST misaligned with stored READ_RESP length");
    end
  end
`endif

endmodule
