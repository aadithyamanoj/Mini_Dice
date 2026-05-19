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
   ,output logic [1:0]              awid_o

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
   ,output logic                    ar_is_burst_o
   ,output logic [1:0]              arid_o
   ,output logic [3:0]              ar_tid_o
   ,output logic [2:0]              ar_eblock_o
   ,output logic [4:0]              ar_regaddr_o

   ,output logic                    rvalid_o
   ,input  logic                    rready_i
   ,output logic [31:0]             rdata_o
   ,output logic [1:0]              rresp_o
   ,output logic                    rlast_o
   ,output logic [1:0]              rid_o
   ,output logic                    r_is_burst_o
   );

  // --------------------------------------------------------------------------
  // Combined transport packets over a 32-bit flit link.
  //
  // The on-wire request encoding matches the FPGA-side packet parser
  // (mini_dice_zcu102/rtl/packet_parser.sv). See axi_link_tx.sv for the
  // authoritative description of the wire layout. The same opcode numbering
  // and header bit positions are used here; this module is the inverse of
  // the TX serializer.
  //
  // Opcode mapping:
  //   2'b00 = WRITE
  //   2'b01 = READ_RESP   (FPGA → chip; chip-side definition)
  //   2'b10 = BURST_READ
  //   2'b11 = READ        (single-beat with thread/eblock/regaddr meta)
  //
  // RX reconstructs four AXI channels from the simplified transport:
  //   WRITE      -> AW (awlen=0) + 1 W beat (single-beat only). awid_o
  //                 forwarded from the wire header.
  //   BURST_READ -> AR burst with arid_o = {1'b0, header_id[28]} and
  //                 ar_is_burst_o = 1.
  //   READ       -> AR single-beat with arid_o, ar_tid_o, ar_eblock_o,
  //                 ar_regaddr_o all forwarded from the wire header, and
  //                 ar_is_burst_o = 0.
  //   READ_RESP  -> R burst; rid_o and r_is_burst_o are replayed from the
  //                 header so the chip-side wrapper can stamp them onto
  //                 the crossbar's response-ID line, retiring the chip-side
  //                 AR-ID FIFO. r_is_burst_o distinguishes which class of
  //                 outstanding read the response corresponds to (burst
  //                 read vs single read), since both share the READ_RESP
  //                 opcode on the wire.
  //
  // The B (write-response) channel is intentionally not driven here; the
  // upstream wrapper synthesizes a fake B beat per accepted write so the
  // local AXI master sees write completion without the link round-trip.
  //
  // The link itself does not reorder. The ID field is a routing tag the
  // FPGA dispatcher uses to demultiplex packets across its downstream
  // FIFOs, *not* an AXI reorder ID.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32)
      $error("axi_link_rx requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_rx requires addr_width_p=16, got %0d", addr_width_p);
  end

  typedef enum logic [1:0] {
    OP_WRITE      = 2'b00,
    OP_READ_RESP  = 2'b01,
    OP_BURST_READ = 2'b10,
    OP_READ       = 2'b11
  } pkt_opcode_e;

  typedef enum logic [2:0] {
    RX_IDLE      = 3'd0,
    RX_WR_DATA   = 3'd1,
    RX_R_DATA    = 3'd2,
    RX_DROP      = 3'd3
  } rx_state_e;

  localparam int beat_count_width_lp   = 9;   // beats counter range 1..256
  localparam int rd_meta_width_lp      = 14;  // {id[1:0], tid[3:0], eblock[2:0], regaddr[4:0]}
  localparam int drop_count_width_lp   = 9;
  localparam logic [2:0] axi_size_lp   = 3'b010;
  localparam logic [1:0] axi_burst_lp  = 2'b01;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [1:0]                     id;
    logic [beat_count_width_lp-1:0] beats;
  } wr_desc_s;

  // Read-request descriptor. Mirrors the TX-side struct: is_burst selects
  // BURST_READ vs READ on emit; the payload word holds the per-opcode
  // metadata with the same bit layout as the TX descriptor.
  //   READ      : payload[13:12]=id, payload[11:8]=tid,
  //               payload[7:5]=eblock, payload[4:0]=regaddr
  //   BURST_READ: payload[8]=id, payload[7:0]=AXI-style len
  typedef struct packed {
    logic [addr_width_p-1:0]      addr;
    logic                         is_burst;
    logic [rd_meta_width_lp-1:0]  payload;
  } rd_desc_s;

  // Response descriptor: id stamped onto AXI R, is_burst flag echoed back
  // to the wrapper for slave-index recovery, plus beats for RLAST.
  typedef struct packed {
    logic                           is_burst;
    logic [1:0]                     id;
    logic [beat_count_width_lp-1:0] beats;
  } r_desc_s;

  localparam int wr_desc_width_lp = $bits(wr_desc_s);
  localparam int rd_desc_width_lp = $bits(rd_desc_s);
  localparam int r_desc_width_lp  = $bits(r_desc_s);

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
  logic [wr_desc_width_lp-1:0] wr_desc_push_data_li;
  logic                        wr_desc_v_lo, wr_desc_yumi_li;
  logic [wr_desc_width_lp-1:0] wr_desc_data_lo;

  logic                        rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [rd_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                        rd_desc_v_lo, rd_desc_yumi_li;
  logic [rd_desc_width_lp-1:0] rd_desc_data_lo;

  logic                        w_data_push_v_li, w_data_push_ready_lo;
  logic [31:0]                 w_data_push_data_li;
  logic                        w_data_v_lo, w_data_yumi_li;
  logic [31:0]                 w_data_lo;

  logic                        r_desc_push_v_li, r_desc_push_ready_lo;
  logic [r_desc_width_lp-1:0]  r_desc_push_data_li;
  logic                        r_desc_v_lo, r_desc_yumi_li;
  logic [r_desc_width_lp-1:0]  r_desc_data_lo;

  logic                        r_data_push_v_li, r_data_push_ready_lo;
  logic [31:0]                 r_data_push_data_li;
  logic                        r_data_v_lo, r_data_yumi_li;
  logic [31:0]                 r_data_lo;

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
  // need to store an entire WRITE or READ_RESP packet in registers.

  rx_state_e state_r, state_n;
  logic [beat_count_width_lp-1:0] cur_beats_r, cur_beats_n;
  logic [drop_count_width_lp-1:0] payload_rem_r, payload_rem_n;
  logic [rd_meta_width_lp-1:0]    burst_payload, read_payload;

  // Header bit-slice extractions, kept declarative so the layout is
  // immediately checkable against axi_link_tx.sv.
  logic [1:0]                     hdr_opcode;
  logic [1:0]                     hdr_id_wide;     // [29:28] universal ID window
  logic                           hdr_id_burst;    // [28] BURST_READ 1-bit ID
  logic                           hdr_resp_is_burst; // [27] READ_RESP class flag
  logic [3:0]                     hdr_tid;         // READ tid [27:24]
  logic [2:0]                     hdr_eblock;      // READ eblock [23:21]
  logic [4:0]                     hdr_regaddr;     // READ regaddr [20:16]
  logic [7:0]                     hdr_len_axi;     // BURST_READ / READ_RESP len [23:16]
  logic [beat_count_width_lp-1:0] hdr_beats;
  logic [addr_width_p-1:0]        hdr_addr;

  assign hdr_opcode        = link_fifo_data_lo[31:30];
  assign hdr_id_wide       = link_fifo_data_lo[29:28];
  assign hdr_id_burst      = link_fifo_data_lo[28];
  assign hdr_resp_is_burst = link_fifo_data_lo[27];
  assign hdr_tid           = link_fifo_data_lo[27:24];
  assign hdr_eblock        = link_fifo_data_lo[23:21];
  assign hdr_regaddr       = link_fifo_data_lo[20:16];
  assign hdr_len_axi       = link_fifo_data_lo[23:16];
  assign hdr_beats         = {1'b0, hdr_len_axi} + beat_count_width_lp'(1);
  assign hdr_addr          = link_fifo_data_lo[15:0];

  // Pre-packed rd_desc payload variants — only one is selected per header
  // by the parser FSM. Same bit layout as axi_link_tx.sv.
  always_comb begin
    burst_payload      = '0;
    burst_payload[8]   = hdr_id_burst;
    burst_payload[7:0] = hdr_len_axi;
  end
  always_comb begin
    read_payload         = '0;
    read_payload[13:12]  = hdr_id_wide;
    read_payload[11:8]   = hdr_tid;
    read_payload[7:5]    = hdr_eblock;
    read_payload[4:0]    = hdr_regaddr;
  end

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
            OP_WRITE: begin
              // Header carries id and addr; len is implicit (single beat).
              if (wr_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                wr_desc_push_v_li    = 1'b1;
                wr_desc_push_data_li = wr_desc_s'{addr: hdr_addr, id: hdr_id_wide, beats: beat_count_width_lp'(1)};
                cur_beats_n          = beat_count_width_lp'(1);
                payload_rem_n        = drop_count_width_lp'(1);
                state_n              = RX_WR_DATA;
              end
            end

            OP_BURST_READ: begin
              // Header-only packet. Pack the 1-bit ID and the 8-bit len into
              // the rd_desc payload word's low slot; high slots are zero.
              if (rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = rd_desc_s'{addr: hdr_addr, is_burst: 1'b1, payload: burst_payload};
                state_n              = RX_IDLE;
              end
            end

            OP_READ: begin
              // Header-only packet. Unpack id/tid/eblock/regaddr into the
              // rd_desc payload word's high slots so the AXI side can drive
              // the matching flat output ports directly.
              if (rd_desc_push_ready_lo) begin
                link_fifo_yumi_li    = 1'b1;
                rd_desc_push_v_li    = 1'b1;
                rd_desc_push_data_li = rd_desc_s'{addr: hdr_addr, is_burst: 1'b0, payload: read_payload};
                state_n              = RX_IDLE;
              end
            end

            OP_READ_RESP: begin
              // Header carries id, is_burst class flag, and length; rresp_o
              // is locally driven to OKAY (the link no longer transports
              // RRESP).
              if (r_desc_push_ready_lo) begin
                link_fifo_yumi_li   = 1'b1;
                r_desc_push_v_li    = 1'b1;
                r_desc_push_data_li = r_desc_s'{is_burst: hdr_resp_is_burst,
                                                 id:       hdr_id_wide,
                                                 beats:    hdr_beats};
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

  wr_desc_s wr_desc_cast;
  assign wr_desc_cast = wr_desc_s'(wr_desc_data_lo);

  logic write_active_r, write_active_n;
  logic [beat_count_width_lp-1:0] write_beats_left_r, write_beats_left_n;
  logic aw_handshake, w_handshake;

  assign awvalid_o = wr_desc_v_lo && !write_active_r;
  assign awaddr_o  = wr_desc_cast.addr;
  assign awlen_o   = wr_desc_cast.beats[7:0] - 8'd1;
  assign awsize_o  = axi_size_lp;
  assign awburst_o = axi_burst_lp;
  assign awid_o    = wr_desc_cast.id;

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
  // BURST_READ packets replay as AR bursts; READ packets replay as a
  // single-beat AR with the unpacked tid/eblock/regaddr metadata.

  rd_desc_s rd_desc_cast;
  assign rd_desc_cast = rd_desc_s'(rd_desc_data_lo);

  assign arvalid_o     = rd_desc_v_lo;
  assign araddr_o      = rd_desc_cast.addr;
  assign arlen_o       = rd_desc_cast.is_burst ? rd_desc_cast.payload[7:0]
                                                : 8'd0;
  assign arsize_o      = axi_size_lp;
  assign arburst_o     = axi_burst_lp;
  assign ar_is_burst_o = rd_desc_cast.is_burst;
  assign arid_o        = rd_desc_cast.is_burst
                           ? {1'b0, rd_desc_cast.payload[8]}
                           : rd_desc_cast.payload[13:12];
  assign ar_tid_o      = rd_desc_cast.is_burst ? '0 : rd_desc_cast.payload[11:8];
  assign ar_eblock_o   = rd_desc_cast.is_burst ? '0 : rd_desc_cast.payload[7:5];
  assign ar_regaddr_o  = rd_desc_cast.is_burst ? '0 : rd_desc_cast.payload[4:0];

  assign rd_desc_yumi_li = arvalid_o && arready_i;

  // --------------------------------------------------------------------------
  // AXI R reconstruction
  // --------------------------------------------------------------------------

  r_desc_s r_desc_cast;
  assign r_desc_cast = r_desc_s'(r_desc_data_lo);

  logic r_active_r, r_active_n;
  logic [beat_count_width_lp-1:0] r_beats_left_r, r_beats_left_n;
  logic [1:0]                     r_id_r, r_id_n;
  logic                           r_is_burst_r, r_is_burst_n;
  logic r_start_burst;
  logic r_handshake;

  assign r_start_burst = !r_active_r && r_desc_v_lo && r_data_v_lo;
  assign rvalid_o      = (r_active_r || r_start_burst) && r_data_v_lo;
  assign rdata_o       = r_data_lo;
  assign rresp_o       = 2'b00;  // RESP_OKAY — link does not carry rresp
  assign rlast_o       = r_active_r
                         ? (r_beats_left_r == beat_count_width_lp'(1))
                         : (r_desc_cast.beats == beat_count_width_lp'(1));
  assign rid_o         = r_active_r ? r_id_r       : r_desc_cast.id;
  assign r_is_burst_o  = r_active_r ? r_is_burst_r : r_desc_cast.is_burst;
  assign r_handshake   = rvalid_o && rready_i;

  assign r_desc_yumi_li = r_start_burst;
  assign r_data_yumi_li = r_handshake;

  always_comb begin
    r_active_n     = r_active_r;
    r_beats_left_n = r_beats_left_r;
    r_id_n         = r_id_r;
    r_is_burst_n   = r_is_burst_r;

    if (r_start_burst) begin
      r_active_n     = 1'b1;
      r_beats_left_n = r_desc_cast.beats;
      r_id_n         = r_desc_cast.id;
      r_is_burst_n   = r_desc_cast.is_burst;
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
      r_id_r         <= '0;
      r_is_burst_r   <= 1'b0;
    end
    else begin
      r_active_r     <= r_active_n;
      r_beats_left_r <= r_beats_left_n;
      r_id_r         <= r_id_n;
      r_is_burst_r   <= r_is_burst_n;
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if ((state_r == RX_WR_DATA) && (payload_rem_r == '0))
        $error("axi_link_rx parser inconsistent in RX_WR_DATA");

      if (awvalid_o && (wr_desc_cast.beats == '0))
        $error("axi_link_rx attempted zero-length AW burst");

      if (w_handshake && (wlast_o != (write_beats_left_r == beat_count_width_lp'(1))))
        $error("axi_link_rx WLAST misaligned with stored write descriptor");

      if (r_handshake && (rlast_o != ((r_active_r ? r_beats_left_r : r_desc_cast.beats) == beat_count_width_lp'(1))))
        $error("axi_link_rx RLAST misaligned with stored READ_RESP length");
    end
  end
`endif

endmodule
