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
   ,input  logic [1:0]              awid_i

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
   ,input  logic                    ar_is_burst_i
   ,input  logic [1:0]              arid_i
   ,input  logic [3:0]              ar_tid_i
   ,input  logic [2:0]              ar_eblock_i
   ,input  logic [4:0]              ar_regaddr_i

   ,input  logic                    rvalid_i
   ,output logic                    rready_o
   ,input  logic [31:0]             rdata_i
   ,input  logic [1:0]              rresp_i
   ,input  logic                    rlast_i
   ,input  logic [1:0]              rid_i
   ,input  logic                    tx_r_len_v_i
   ,input  logic [7:0]              tx_r_len_i
   ,output logic                    tx_r_len_yumi_o

   ,output logic                    link_tx_v_o
   ,output logic [flit_width_p-1:0] link_tx_data_o
   ,input  logic                    link_tx_ready_i
   );

  // --------------------------------------------------------------------------
  // Combined transport packets over a 32-bit flit link.
  //
  // The on-wire request encoding matches the FPGA-side packet parser
  // (mini_dice_zcu102/rtl/packet_parser.sv) bit-for-bit so the FPGA can
  // dispatch packets to its downstream queues without any translation.
  //
  // Opcode mapping:
  //   2'b00 = WRITE
  //   2'b01 = READ_RESP   (chip → FPGA only; chip-side definition)
  //   2'b10 = BURST_READ
  //   2'b11 = READ        (single-beat read with thread/eblock/regaddr meta)
  //
  // Header flit layouts (32 bits):
  //
  //   WRITE      : [31:30] opcode, [29:28] id, [27:16] reserved (zero),
  //                [15:0] address
  //                  Single-beat only — upstream must drive awlen_i=0 or AW
  //                  is rejected. id is the 2-bit memory-port routing tag
  //                  used by the FPGA dispatcher.
  //
  //   BURST_READ : [31:30] opcode, [29] reserved-zero, [28] id (1 bit),
  //                [27:24] reserved, [23:16] AXI-style len (beats-1),
  //                [15:0] address
  //                  id ∈ {0,1} → metadata vs bitstream burst-read FIFO on
  //                  the FPGA dispatcher. The upper bit of the [29:28]
  //                  window is forced to zero so a universal two-bit ID
  //                  extraction still sees id ∈ {0,1}.
  //
  //   READ       : [31:30] opcode, [29:28] id, [27:24] tid, [23:21] eblock,
  //                [20:16] regaddr, [15:0] address
  //                  Single-beat. id is the memory-port routing tag for the
  //                  data-cache port; tid/eblock/regaddr identify the
  //                  register-write destination on response.
  //
  //   READ_RESP  : [31:30] opcode, [29:28] id, [27] is_burst (1=burst,
  //                0=single), [26:24] reserved,
  //                [23:16] AXI-style len (beats-1), [15:0] reserved
  //                  Response opcode for chip→FPGA reads. id and is_burst
  //                  are echoed from the original request so the chip-side
  //                  RX adapter can replay them onto the crossbar's
  //                  response-ID line, retiring the chip-side AR-ID FIFO.
  //                  Chip-side TX always emits is_burst=0 because the chip
  //                  only responds to fpga_mst CSR reads (single-beat); the
  //                  FPGA-side TX must set is_burst per the original
  //                  request class so the chip-side RX can disambiguate.
  //
  // Length encoding follows AXI semantics: the wire `len` field carries
  // (beats - 1) in 8 bits. WRITE and READ are always single-beat and do
  // not use this field.
  //
  // RRESP is intentionally not carried by this link, mirroring the dropped
  // B channel. The receiving side reconstructs rresp_o = OKAY for every
  // beat; per-read error reporting is therefore lost.
  //
  // AXI semantics at the module boundary:
  //   requests  : AW, W, AR
  //   responses : R
  //   The B (write-response) channel is intentionally not carried by this
  //   link. The upstream wrapper synthesizes a fake B beat per accepted
  //   write so the AXI master sees write completion locally; per-write
  //   error reporting is therefore lost.
  //
  // Strict FIFO assumption:
  //   The link itself does not reorder. The ID field is a routing tag the
  //   FPGA dispatcher uses to demultiplex packets across its downstream
  //   FIFOs, *not* an AXI reorder ID.
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 32)
      $error("axi_link_tx requires flit_width_p=32, got %0d", flit_width_p);
    if (addr_width_p != 16)
      $error("axi_link_tx requires addr_width_p=16, got %0d", addr_width_p);
  end

  typedef enum logic [1:0] {
    OP_WRITE      = 2'b00,
    OP_READ_RESP  = 2'b01,
    OP_BURST_READ = 2'b10,
    OP_READ       = 2'b11
  } pkt_opcode_e;

  typedef enum logic [1:0] {
    PKT_WR_REQ  = 2'd0,
    PKT_RD_REQ  = 2'd1,
    PKT_RD_RESP = 2'd2
  } pkt_kind_e;

  typedef enum logic [1:0] {
    TX_IDLE    = 2'd0,
    TX_HEADER  = 2'd1,
    TX_DATA    = 2'd2
  } tx_state_e;

  localparam int beat_count_width_lp   = 9;   // beats counter range 1..256
  localparam int rd_meta_width_lp      = 14;  // {id[1:0], tid[3:0], eblock[2:0], regaddr[4:0]}
  localparam logic [2:0] axi_size_lp   = 3'b010;
  localparam logic [1:0] axi_burst_lp  = 2'b01;

  typedef struct packed {
    logic [addr_width_p-1:0]        addr;
    logic [1:0]                     id;
    logic [beat_count_width_lp-1:0] beats;
  } wr_desc_s;

  // Read-request descriptor. is_burst selects BURST_READ vs READ on emit;
  // the payload word holds everything else for either opcode, with bit
  // layout chosen so the serializer can unpack with simple slices:
  //   READ      : payload[13:12]=id, payload[11:8]=tid,
  //               payload[7:5]=eblock, payload[4:0]=regaddr
  //   BURST_READ: payload[8]=id (1 bit), payload[7:0]=AXI-style len
  typedef struct packed {
    logic [addr_width_p-1:0]      addr;
    logic                         is_burst;
    logic [rd_meta_width_lp-1:0]  payload;
  } rd_desc_s;

  // Response descriptor for chip→FPGA READ_RESP. Carries the echoed id
  // and the beat count so the serializer can emit the right wire length.
  typedef struct packed {
    logic [1:0]                     id;
    logic [beat_count_width_lp-1:0] beats;
  } r_desc_s;

  localparam int wr_desc_width_lp = $bits(wr_desc_s);
  localparam int rd_desc_width_lp = $bits(rd_desc_s);
  localparam int r_desc_width_lp  = $bits(r_desc_s);

  // --------------------------------------------------------------------------
  // Internal FIFOs
  // --------------------------------------------------------------------------
  // `wr_desc_fifo_i` stores one combined write-request descriptor per AW burst.
  // `w_len_fifo_i` is the matching beat-count queue that lets the W channel
  // consume beats later in the same strict FIFO order without IDs.
  // `pkt_order_fifo_i` records only packet start order across request/response
  // classes; the serializer follows it exactly to preserve end-to-end order.

  logic                        wr_desc_push_v_li, wr_desc_push_ready_lo;
  logic [wr_desc_width_lp-1:0] wr_desc_push_data_li;
  logic                        wr_desc_v_lo, wr_desc_yumi_li;
  logic [wr_desc_width_lp-1:0] wr_desc_data_lo;

  logic                        rd_desc_push_v_li, rd_desc_push_ready_lo;
  logic [rd_desc_width_lp-1:0] rd_desc_push_data_li;
  logic                        rd_desc_v_lo, rd_desc_yumi_li;
  logic [rd_desc_width_lp-1:0] rd_desc_data_lo;

  logic                           w_len_push_v_li, w_len_push_ready_lo;
  logic [beat_count_width_lp-1:0] w_len_push_data_li;
  logic                           w_len_v_lo, w_len_yumi_li;
  logic [beat_count_width_lp-1:0] w_len_data_lo;

  logic                     w_data_push_v_li, w_data_push_ready_lo;
  logic [31:0]              w_data_push_data_li;
  logic                     w_data_v_lo, w_data_yumi_li;
  logic [31:0]              w_data_lo;

  logic                       r_desc_push_v_li, r_desc_push_ready_lo;
  logic [r_desc_width_lp-1:0] r_desc_push_data_li;
  logic                       r_desc_v_lo, r_desc_yumi_li;
  logic [r_desc_width_lp-1:0] r_desc_data_lo;

  logic                     r_data_push_v_li, r_data_push_ready_lo;
  logic [31:0]              r_data_push_data_li;
  logic                     r_data_v_lo, r_data_yumi_li;
  logic [31:0]              r_data_lo;

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

  logic [2:0] start_req, start_grant;
  logic [1:0] rr_start_r, rr_start_n;
  logic aw_req, ar_req, r_start_req;

  logic [beat_count_width_lp-1:0] aw_beats, ar_beats;
  logic [beat_count_width_lp-1:0] tx_r_beats_li;
  logic aw_ctrl_ok, ar_ctrl_ok;

  assign aw_beats      = {1'b0, awlen_i}    + beat_count_width_lp'(1);
  assign ar_beats      = {1'b0, arlen_i}    + beat_count_width_lp'(1);
  assign tx_r_beats_li = {1'b0, tx_r_len_i} + beat_count_width_lp'(1);
  // Writes must be single beat (awlen_i=0) — the WRITE header has no wire
  // length field and the link transports exactly one W flit per accepted AW.
  assign aw_ctrl_ok = (awsize_i == axi_size_lp) && (awburst_i == axi_burst_lp) && (awlen_i == 8'd0);
  // Single READ packets must also be single-beat (the header carries no len).
  // Bursts are allowed only on BURST_READ; arlen up to 255 (256 beats).
  assign ar_ctrl_ok = (arsize_i == axi_size_lp) && (arburst_i == axi_burst_lp)
                      && (ar_beats != '0)
                      && (ar_is_burst_i || (arlen_i == 8'd0));

  logic r_capture_active_r, r_capture_active_n;
  logic [beat_count_width_lp-1:0] r_capture_beats_left_r, r_capture_beats_left_n;
  logic [beat_count_width_lp-1:0] r_accept_loaded_beats;
  logic r_first_accept;

  assign aw_req      = awvalid_i && wr_desc_push_ready_lo && w_len_push_ready_lo && pkt_order_push_ready_lo && aw_ctrl_ok;
  assign ar_req      = arvalid_i && rd_desc_push_ready_lo && pkt_order_push_ready_lo && ar_ctrl_ok;
  assign r_start_req = rvalid_i && !r_capture_active_r
                       && tx_r_len_v_i && r_data_push_ready_lo && r_desc_push_ready_lo
                       && pkt_order_push_ready_lo;

  assign start_req[pkt_kind_e'(PKT_WR_REQ)]  = aw_req;
  assign start_req[pkt_kind_e'(PKT_RD_REQ)]  = ar_req;
  assign start_req[pkt_kind_e'(PKT_RD_RESP)] = r_start_req;

  integer start_scan_i;
  integer start_scan_idx;
  always_comb begin
    start_grant = '0;
    for (start_scan_i = 0; start_scan_i < 3; start_scan_i++) begin
      start_scan_idx = rr_start_r + start_scan_i;
      if (start_scan_idx >= 3)
        start_scan_idx = start_scan_idx - 3;
      if ((start_grant == '0) && start_req[start_scan_idx])
        start_grant[start_scan_idx] = 1'b1;
    end
  end

  always_comb begin
    rr_start_n = rr_start_r;
    if (start_grant != '0) begin
      if (start_grant[0]) rr_start_n = 2'd1;
      if (start_grant[1]) rr_start_n = 2'd2;
      if (start_grant[2]) rr_start_n = 2'd0;
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
  // AW acceptance creates a pending WRITE descriptor immediately, while the
  // corresponding W burst can arrive later and is matched purely by FIFO order.
  // This is safe only under the module's strict in-order assumption.

  logic [beat_count_width_lp-1:0] w_accept_beats_left_r, w_accept_beats_left_n;
  logic [beat_count_width_lp-1:0] w_accept_loaded_beats;
  logic w_accept_active_r, w_accept_active_n;
  logic aw_accept, ar_accept, r_accept, w_accept;
  logic r_final_accept;

  assign aw_accept = start_grant[pkt_kind_e'(PKT_WR_REQ)];
  assign ar_accept = start_grant[pkt_kind_e'(PKT_RD_REQ)];

  assign awready_o = aw_accept;
  assign arready_o = ar_accept;

  assign wr_desc_push_v_li    = aw_accept;
  assign wr_desc_push_data_li = wr_desc_s'{addr: awaddr_i, id: awid_i, beats: aw_beats};
  assign w_len_push_v_li      = aw_accept;
  assign w_len_push_data_li   = aw_beats;
  assign pkt_order_push_v_li  = aw_accept || ar_accept || (r_accept && !r_capture_active_r);
  assign pkt_order_push_data_li = aw_accept ? pkt_kind_e'(PKT_WR_REQ)
                                  : ar_accept ? pkt_kind_e'(PKT_RD_REQ)
                                  : pkt_kind_e'(PKT_RD_RESP);

  // Read descriptor: pack the per-opcode payload into a single 14-bit field
  // so a single FIFO width covers both READ and BURST_READ. The serializer
  // routes the slices back into the correct header bit positions on emit.
  logic [rd_meta_width_lp-1:0] ar_payload_li;
  always_comb begin
    if (ar_is_burst_i) begin
      // BURST_READ payload: 6 reserved bits, 1-bit id, 8-bit AXI-style len.
      ar_payload_li        = '0;
      ar_payload_li[8]     = arid_i[0];
      ar_payload_li[7:0]   = arlen_i;
    end
    else begin
      // READ payload: 2-bit id, 4-bit tid, 3-bit eblock, 5-bit regaddr.
      ar_payload_li[13:12] = arid_i;
      ar_payload_li[11:8]  = ar_tid_i;
      ar_payload_li[7:5]   = ar_eblock_i;
      ar_payload_li[4:0]   = ar_regaddr_i;
    end
  end

  assign rd_desc_push_v_li    = ar_accept;
  assign rd_desc_push_data_li = rd_desc_s'{addr: araddr_i, is_burst: ar_is_burst_i, payload: ar_payload_li};

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

  // R beats stream straight into `r_data_fifo_i`. The matching {id,beats}
  // descriptor is published on the first beat using the stored AR length
  // and the ID forwarded from the slave-side R channel.

  assign r_data_push_v_li    = r_accept;
  assign r_data_push_data_li = rdata_i;
  assign r_final_accept      = r_accept && (r_accept_loaded_beats == beat_count_width_lp'(1));
  assign r_desc_push_v_li    = r_first_accept;
  assign r_desc_push_data_li = r_desc_s'{id: rid_i, beats: tx_r_beats_li};
  assign tx_r_len_yumi_o     = r_first_accept;

  always_comb begin
    r_capture_active_n     = r_capture_active_r;
    r_capture_beats_left_n = r_capture_beats_left_r;

    if (r_accept) begin
      if (!r_capture_active_r) begin
        if (r_accept_loaded_beats == beat_count_width_lp'(1)) begin
          r_capture_active_n     = 1'b0;
          r_capture_beats_left_n = '0;
        end
        else begin
          r_capture_active_n     = 1'b1;
          r_capture_beats_left_n = r_accept_loaded_beats - beat_count_width_lp'(1);
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
    end
    else begin
      r_capture_active_r     <= r_capture_active_n;
      r_capture_beats_left_r <= r_capture_beats_left_n;
    end
  end

  // --------------------------------------------------------------------------
  // Link serializer
  // --------------------------------------------------------------------------
  // The serializer is intentionally simple:
  //   TX_HEADER emits the 32-bit header flit per the layouts documented above
  //   TX_DATA   streams W or R payload beats from the corresponding FIFO
  //
  // Only one packet is active at a time, and packet start order is supplied by
  // `pkt_order_fifo_i`, so no cross-packet reordering is possible.

  tx_state_e state_r, state_n;
  logic [1:0]                      cur_kind_r, cur_kind_n;
  logic [addr_width_p-1:0]         cur_addr_r, cur_addr_n;
  // cur_meta_r holds either the WR id, the RD id+tid+eblock+regaddr payload,
  // or the response id+beats — interpretation depends on cur_kind_r.
  logic [rd_meta_width_lp-1:0]     cur_meta_r, cur_meta_n;
  logic [beat_count_width_lp-1:0]  cur_data_beats_left_r, cur_data_beats_left_n;
  logic                            cur_ar_is_burst_r, cur_ar_is_burst_n;
  logic [1:0]                      cur_id_r, cur_id_n;
  logic [7:0]                      cur_len_r, cur_len_n;

  wr_desc_s wr_desc_cast;
  rd_desc_s rd_desc_cast;
  r_desc_s  r_desc_cast;

  assign wr_desc_cast = wr_desc_s'(wr_desc_data_lo);
  assign rd_desc_cast = rd_desc_s'(rd_desc_data_lo);
  assign r_desc_cast  = r_desc_s'(r_desc_data_lo);

  logic start_wr_pkt, start_rd_pkt, start_r_pkt;
  logic link_handshake;

  assign start_wr_pkt = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_WR_REQ)) && wr_desc_v_lo;
  assign start_rd_pkt = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_RD_REQ)) && rd_desc_v_lo;
  assign start_r_pkt  = (state_r == TX_IDLE) && pkt_order_v_lo
                        && (pkt_order_lo == pkt_kind_e'(PKT_RD_RESP)) && r_desc_v_lo;

  assign pkt_order_yumi_li = start_wr_pkt || start_rd_pkt || start_r_pkt;
  assign wr_desc_yumi_li   = start_wr_pkt;
  assign rd_desc_yumi_li   = start_rd_pkt;
  assign r_desc_yumi_li    = start_r_pkt;

  assign w_data_yumi_li = (state_r == TX_DATA) && link_handshake
                          && (cur_kind_r == pkt_kind_e'(PKT_WR_REQ));
  assign r_data_yumi_li = (state_r == TX_DATA) && link_handshake
                          && (cur_kind_r == pkt_kind_e'(PKT_RD_RESP));

  always_comb begin
    state_n               = state_r;
    cur_kind_n            = cur_kind_r;
    cur_addr_n            = cur_addr_r;
    cur_meta_n            = cur_meta_r;
    cur_data_beats_left_n = cur_data_beats_left_r;
    cur_ar_is_burst_n     = cur_ar_is_burst_r;
    cur_id_n              = cur_id_r;
    cur_len_n             = cur_len_r;

    if (start_wr_pkt) begin
      // WRITE = header + 1 W data beat (single-beat only).
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_WR_REQ);
      cur_addr_n            = wr_desc_cast.addr;
      cur_id_n              = wr_desc_cast.id;
      cur_data_beats_left_n = wr_desc_cast.beats;
      cur_ar_is_burst_n     = 1'b0;
      cur_meta_n            = '0;
      cur_len_n             = '0;
    end
    else if (start_rd_pkt) begin
      // READ / BURST_READ = header only. The serializer unpacks the right
      // bit slices from cur_meta_r based on cur_ar_is_burst_r.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_RD_REQ);
      cur_addr_n            = rd_desc_cast.addr;
      cur_meta_n            = rd_desc_cast.payload;
      cur_data_beats_left_n = '0;
      cur_ar_is_burst_n     = rd_desc_cast.is_burst;
      cur_id_n              = '0;
      cur_len_n             = '0;
    end
    else if (start_r_pkt) begin
      // READ_RESP = header + R data beats.
      state_n               = TX_HEADER;
      cur_kind_n            = pkt_kind_e'(PKT_RD_RESP);
      cur_addr_n            = '0;
      cur_id_n              = r_desc_cast.id;
      cur_len_n             = r_desc_cast.beats[7:0] - 8'd1;
      cur_data_beats_left_n = r_desc_cast.beats;
      cur_ar_is_burst_n     = 1'b0;
      cur_meta_n            = '0;
    end
    else if (link_handshake) begin
      unique case (state_r)
        TX_HEADER: begin
          case (cur_kind_r)
            pkt_kind_e'(PKT_WR_REQ):  state_n = TX_DATA;
            pkt_kind_e'(PKT_RD_REQ):  state_n = TX_IDLE;
            pkt_kind_e'(PKT_RD_RESP): state_n = TX_DATA;
            default:                  state_n = TX_IDLE;
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
      cur_meta_r            <= '0;
      cur_data_beats_left_r <= '0;
      cur_ar_is_burst_r     <= 1'b0;
      cur_id_r              <= '0;
      cur_len_r             <= '0;
    end
    else begin
      state_r               <= state_n;
      cur_kind_r            <= cur_kind_n;
      cur_addr_r            <= cur_addr_n;
      cur_meta_r            <= cur_meta_n;
      cur_data_beats_left_r <= cur_data_beats_left_n;
      cur_ar_is_burst_r     <= cur_ar_is_burst_n;
      cur_id_r              <= cur_id_n;
      cur_len_r             <= cur_len_n;
    end
  end

  // Header bit packs per opcode — matching FPGA packet_parser layout.
  logic [31:0] hdr_write_li, hdr_burst_li, hdr_read_li, hdr_resp_li;
  assign hdr_write_li = {OP_WRITE, cur_id_r, 12'b0, cur_addr_r};
  assign hdr_burst_li = {OP_BURST_READ, 1'b0, cur_meta_r[8], 4'b0, cur_meta_r[7:0], cur_addr_r};
  assign hdr_read_li  = {OP_READ, cur_meta_r[13:12], cur_meta_r[11:8],
                         cur_meta_r[7:5], cur_meta_r[4:0], cur_addr_r};
  assign hdr_resp_li  = {OP_READ_RESP, cur_id_r, 4'b0, cur_len_r, 16'b0};

  always_comb begin
    link_tx_v_o    = 1'b0;
    link_tx_data_o = '0;

    unique case (state_r)
      TX_HEADER: begin
        link_tx_v_o = 1'b1;
        unique case (cur_kind_r)
          pkt_kind_e'(PKT_WR_REQ):  link_tx_data_o = hdr_write_li;
          pkt_kind_e'(PKT_RD_REQ):  link_tx_data_o = cur_ar_is_burst_r ? hdr_burst_li : hdr_read_li;
          pkt_kind_e'(PKT_RD_RESP): link_tx_data_o = hdr_resp_li;
          default:                  link_tx_data_o = '0;
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
