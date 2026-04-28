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
  // Header flit layouts (32 bits):
  //   WRITE_REQ / READ_REQ:
  //     [31:29] = opcode
  //     [28:16] = packet length (beats)
  //     [15:0]  = address
  //   READ_RESP header:
  //     [31:29] = opcode
  //     [28:27] = rresp
  //     [26:0]  = reserved
  //   READ_RESP data flit (one per AXI R beat, no length, no trailer):
  //     [31:29] = opcode (OP_READ_RESP, FSM disambiguates from header)
  //     [28]    = rlast
  //     [27:16] = reserved
  //     [15:0]  = rdata[15:0]
  //   WRITE_RESP:
  //     header  = {opcode, 13'd1, 16'b0}
  //     trailer = {30'b0, bresp}
  //
  // READ_RESP is now self-delimiting and streamed end-to-end: each AXI R beat
  // produced by the remote slave maps to exactly one link flit, and this
  // module forwards that flit straight to the local AXI R channel without
  // ever staging an entire burst. RRESP is carried once in the header and
  // replayed on every R beat (consistent with the existing single-RRESP-per-
  // burst assumption).
  //
  // Strict FIFO assumption preserved: no AXI IDs, all pairings are by order.
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
    RX_B_RESP    = 3'd3,
    RX_DROP      = 3'd4
  } rx_state_e;

  localparam int beat_count_width_lp = 13;
  localparam int drop_count_width_lp = 14;
  localparam int req_desc_width_lp   = addr_width_p + beat_count_width_lp;
  localparam logic [2:0] axi_size_lp   = 3'b001;
  localparam logic [1:0] axi_burst_lp  = 2'b01;
  localparam int max_axi_beats_lp    = 256;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [beat_count_width_lp-1:0] beats;
  } req_desc_s;

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
  // Only AW / AR / W-data / B-resp are buffered. R is no longer buffered:
  // the parser FSM drives the AXI R channel directly from the link FIFO in
  // RX_R_DATA, so r_data and r_desc FIFOs are gone. The r_*_fifo_els_p
  // parameters are retained for top-level instantiation compatibility.

  logic                      wr_desc_push_v_li, wr_desc_push_ready_lo;
  logic [req_desc_width_lp-1:0] wr_desc_push_data_li;
  logic                      wr_desc_v_lo, wr_desc_yumi_li;
  logic [req_desc_width_lp-1:0] wr_desc_data_lo;

  logic                      rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [req_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                      rd_desc_v_lo, rd_desc_yumi_li;
  logic [req_desc_width_lp-1:0] rd_desc_data_lo;

  logic                      w_data_push_v_li, w_data_push_ready_lo;
  logic [31:0]               w_data_push_data_li;
  logic                      w_data_v_lo, w_data_yumi_li;
  logic [31:0]               w_data_lo;

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
  // The parser handles four packet types with no full-burst staging:
  //   WRITE_REQ : header pushes AW, payload streams into w_data_fifo_i
  //   READ_REQ  : single header flit pushes AR
  //   READ_RESP : header latches RRESP; each subsequent flit drives the AXI
  //               R channel directly from the link FIFO in RX_R_DATA, exiting
  //               on the flit whose rlast bit is set
  //   WRITE_RESP: header + trailer flit pushes B
  // Malformed packets are flushed via RX_DROP, keeping the parser aligned.

  rx_state_e state_r, state_n;
  logic [drop_count_width_lp-1:0] payload_rem_r, payload_rem_n;
  logic [1:0]                     r_resp_hold_r, r_resp_hold_n;

  logic [2:0]                     hdr_opcode;
  logic [beat_count_width_lp-1:0] hdr_len;
  logic [addr_width_p-1:0]        hdr_addr;
  logic [1:0]                     hdr_rresp;
  logic                           hdr_len_valid;

  assign hdr_opcode    = link_fifo_data_lo[31:29];
  assign hdr_len       = link_fifo_data_lo[28:16];
  assign hdr_addr      = link_fifo_data_lo[15:0];
  assign hdr_rresp     = link_fifo_data_lo[28:27];
  assign hdr_len_valid = (hdr_len != '0) && (hdr_len <= beat_count_width_lp'(max_axi_beats_lp));

  // READ_RESP data flit decode
  logic        rd_flit_rlast;
  logic [15:0] rd_flit_data;
  assign rd_flit_rlast = link_fifo_data_lo[28];
  assign rd_flit_data  = link_fifo_data_lo[15:0];

  always_comb begin
    state_n           = state_r;
    payload_rem_n     = payload_rem_r;
    r_resp_hold_n     = r_resp_hold_r;

    link_fifo_yumi_li = 1'b0;

    wr_desc_push_v_li    = 1'b0;
    wr_desc_push_data_li = '0;
    rd_desc_push_v_li    = 1'b0;
    rd_desc_push_data_li = '0;
    w_data_push_v_li     = 1'b0;
    w_data_push_data_li  = link_fifo_data_lo;
    b_resp_push_v_li     = 1'b0;
    b_resp_push_data_li  = link_fifo_data_lo[1:0];

    // AXI R channel direct-drive defaults; only RX_R_DATA actually drives it.
    rvalid_o = 1'b0;
    rdata_o  = '0;
    rresp_o  = '0;
    rlast_o  = 1'b0;

    unique case (state_r)
      RX_IDLE: begin
        if (link_fifo_v_lo) begin
          unique case (hdr_opcode)
            OP_WRITE_REQ: begin
              if (hdr_len_valid && wr_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                wr_desc_push_v_li    = 1'b1;
                wr_desc_push_data_li = {hdr_addr, hdr_len};
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
              // Streaming READ_RESP: latch RRESP from the header and pass
              // every subsequent flit straight through to the AXI R channel.
              link_fifo_yumi_li = 1'b1;
              r_resp_hold_n     = hdr_rresp;
              state_n           = RX_R_DATA;
            end

            OP_WRITE_RESP: begin
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
        // Each link flit becomes one AXI R beat. The flit is consumed in the
        // same cycle the AXI master accepts it -- no R-side FIFO at all.
        rvalid_o = link_fifo_v_lo;
        rdata_o  = {16'b0, rd_flit_data};
        rresp_o  = r_resp_hold_r;
        rlast_o  = rd_flit_rlast;

        if (link_fifo_v_lo && rready_i) begin
          link_fifo_yumi_li = 1'b1;
          if (rd_flit_rlast)
            state_n = RX_IDLE;
        end
      end

      RX_B_RESP: begin
        if (link_fifo_v_lo && b_resp_push_ready_lo) begin
          link_fifo_yumi_li = 1'b1;
          b_resp_push_v_li  = 1'b1;
          state_n           = RX_IDLE;
        end
      end

      RX_DROP: begin
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
      payload_rem_r <= '0;
      r_resp_hold_r <= '0;
    end
    else begin
      state_r       <= state_n;
      payload_rem_r <= payload_rem_n;
      r_resp_hold_r <= r_resp_hold_n;
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

  req_desc_s rd_desc_cast;
  assign rd_desc_cast = req_desc_s'(rd_desc_data_lo);

  assign arvalid_o = rd_desc_v_lo;
  assign araddr_o  = rd_desc_cast.addr;
  assign arlen_o   = rd_desc_cast.beats[7:0] - 8'd1;
  assign arsize_o  = axi_size_lp;
  assign arburst_o = axi_burst_lp;
  assign rd_desc_yumi_li = arvalid_o && arready_i;

  // --------------------------------------------------------------------------
  // AXI B reconstruction
  // --------------------------------------------------------------------------

  assign bvalid_o     = b_resp_v_lo;
  assign bresp_o      = b_resp_lo;
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
    end
  end
`endif

endmodule
