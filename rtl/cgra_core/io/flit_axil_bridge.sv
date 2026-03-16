module flit_axil_bridge
  // flit_axil_bridge converts a LEN-framed 16-bit flit protocol into a
  // 16-bit AXI4-Lite master interface and packetizes AXI responses back into
  // flits. The design is queue-based:
  // - RX parser turns flit packets into parsed requests
  // - read and write issue paths launch AXI transactions independently
  // - outstanding FIFOs preserve per-stream ordering
  // - completion logic aggregates one OP_R per AR packet and one OP_B per
  //   AW packet
  // - TX FSM drains response packets with normal valid/ready semantics
  #(parameter int flit_width_p          = 16
   // Width of each flit on the FPGA-facing transport.
   ,parameter int axil_addr_width_p     = 16

   // Width of downstream AXI-Lite addresses.
   ,parameter int axil_data_width_p     = 16

   // Width of downstream AXI-Lite read/write data.
   ,parameter int rd_req_fifo_els_p     = 16

   // Depth of the parsed read-request FIFO.
   ,parameter int wr_req_fifo_els_p     = 16

   // Depth of the parsed write-request FIFO.
   ,parameter int rd_out_fifo_els_p     = 16

   // Depth of the outstanding read FIFO.
   ,parameter int rd_data_fifo_els_p    = 16

   // Depth of the read-data FIFO that buffers returned RDATA words.
   ,parameter int wr_out_fifo_els_p     = 16

   // Depth of the outstanding write FIFO.
   ,parameter int tx_resp_fifo_els_p    = 16
   
   // Depth of the TX response descriptor FIFO.
   ,parameter int wr_starvation_limit_p = 16
   // Maximum number of times a read completion may win over a waiting write
   // completion before write is force-granted once.
   )
  (input  logic                           clk_i
   ,input logic                           rst_i

   // Flit RX from adapter (adapter phy_rx_* -> bridge)
   ,input  logic                          phy_rx_v_i
   ,input  logic [flit_width_p-1:0]       phy_rx_data_i
   ,output logic                          phy_rx_ready_o

   // Flit TX to adapter (bridge -> adapter phy_tx_*)
   ,output logic                          phy_tx_v_o
   ,output logic [flit_width_p-1:0]       phy_tx_data_o
   ,input  logic                          phy_tx_ready_i

   // AXI4-Lite master interface
   // Write address channel
   ,output logic [axil_addr_width_p-1:0]  m_axil_awaddr_o
   ,output logic [2:0]                    m_axil_awprot_o
   ,output logic                          m_axil_awvalid_o
   ,input  logic                          m_axil_awready_i

   // Write data channel
   ,output logic [axil_data_width_p-1:0]  m_axil_wdata_o
   ,output logic [(axil_data_width_p/8)-1:0] m_axil_wstrb_o
   ,output logic                          m_axil_wvalid_o
   ,input  logic                          m_axil_wready_i

   // Write response channel
   ,input  logic [1:0]                    m_axil_bresp_i
   ,input  logic                          m_axil_bvalid_i
   ,output logic                          m_axil_bready_o

   // Read address channel
   ,output logic [axil_addr_width_p-1:0]  m_axil_araddr_o
   ,output logic [2:0]                    m_axil_arprot_o
   ,output logic                          m_axil_arvalid_o
   ,input  logic                          m_axil_arready_i

   // Read data channel
   ,input  logic [axil_data_width_p-1:0]  m_axil_rdata_i
   ,input  logic [1:0]                    m_axil_rresp_i
   ,input  logic                          m_axil_rvalid_i
   ,output logic                          m_axil_rready_o
   );

  // Queue-based LEN-framed flit to AXI4-Lite bridge.
  //
  // AXI4-Lite has no IDs, so reads and writes are tracked independently and
  // matched in-order within each stream only. There is intentionally no
  // attempt to impose one mixed read/write completion order.
  //
  // Flit header format:
  // - [15:13] opcode
  // - [12:0]  LEN = number of payload flits after the header
  //
  // Request packets:
  // - AR: payload[0] = address, payload[1] = read_count
  // - AW: payload[0] = address, payload[1..] = one or more write-data flits
  //
  // Response packets:
  // - R: payload[0] = status flit, payload[1..] = returned read data flits
  // - B: payload[0] = status flit
  //
  // Same-address semantics are fixed in this implementation:
  // - every read issued for one AR packet uses the same stored address
  // - every write issued for one AW packet uses the same stored address
  // LEN is transport framing only and is never forwarded onto AXI-Lite.
  //
  // Because OP_R returns aggregate status before any data flits, the bridge
  // must know final read status before beginning TX of that packet. To keep the
  // current packet format correct without speculative status handling, the RX
  // parser rejects read counts that exceed either the outstanding-read tracking
  // depth or the read-data buffering depth.
  //
  // Same-address-only behavior is fixed:
  // - every read generated from one AR packet reuses one packet address
  // - every write generated from one AW packet reuses one packet address
  // This bridge does not do address auto-incrementing.

  initial begin
    if (flit_width_p != 16) begin
      $error("flit_axil_bridge requires flit_width_p=16");
    end
    if (axil_addr_width_p != 16) begin
      $error("flit_axil_bridge requires axil_addr_width_p=16");
    end
    if (axil_data_width_p != 16) begin
      $error("flit_axil_bridge requires axil_data_width_p=16");
    end
    if (rd_data_fifo_els_p < 1) begin
      $error("flit_axil_bridge requires rd_data_fifo_els_p >= 1");
    end
    if (wr_starvation_limit_p < 1) begin
      $error("flit_axil_bridge requires wr_starvation_limit_p >= 1");
    end
  end

  // Flit opcode field values. These are part of the external packet protocol.
  localparam logic [2:0] OP_AR = 3'd0;
  localparam logic [2:0] OP_AW = 3'd1;
  localparam logic [2:0] OP_R  = 3'd2;
  localparam logic [2:0] OP_B  = 3'd3;

  // Transport/protocol constants.
  localparam logic [12:0] AR_REQ_LEN_LP   = 13'd2;
  localparam logic [12:0] B_RESP_LEN_LP   = 13'd1;
  localparam logic [1:0]  BAD_REQ_RESP_LP = 2'b10;

  // AXI4-Lite sideband defaults.
  localparam logic [2:0] AXI_PROT_NORMAL_DATA_LP = 3'b000;
  localparam logic [(axil_data_width_p/8)-1:0] AXI_WSTRB_ALL_LP
    = {(axil_data_width_p/8){1'b1}};

  // The AR parser rejects counts larger than either:
  // - the number of reads we can track as outstanding
  // - the number of returned read words we can buffer before TX drains them
  localparam int max_rd_count_lp
    = (rd_out_fifo_els_p < rd_data_fifo_els_p)
      ? rd_out_fifo_els_p
      : rd_data_fifo_els_p;

  localparam int wr_starvation_cnt_width_lp
    = (wr_starvation_limit_p > 1) ? $clog2(wr_starvation_limit_p+1) : 1;

  typedef struct packed {
    // Address to issue on every AR beat for this request packet.
    logic [axil_addr_width_p-1:0] addr;
    // Number of same-address AXI reads to issue.
    logic [12:0]                  count;
  } rd_req_entry_s;

  typedef struct packed {
    // Address to issue on AW for this internal write beat.
    logic [axil_addr_width_p-1:0] addr;
    // One 16-bit write payload word.
    logic [axil_data_width_p-1:0] data;
    // Marks the final data flit belonging to the original AW packet.
    logic                         last;
  } wr_req_entry_s;

  typedef struct packed {
    // Marks the final issued AXI beat belonging to one original packet.
    logic last;
  } out_entry_s;

  typedef struct packed {
    // Response opcode to send on TX.
    logic [2:0]              opcode;
    // Payload length placed in the response header flit.
    logic [12:0]             len;
    // First payload flit containing response status in bits [1:0].
    logic [flit_width_p-1:0] status_flit;
    // Number of data flits following the status flit.
    logic [12:0]             data_count;
  } tx_resp_entry_s;

  // RX parser FSM states.
  typedef enum logic [1:0] {
    RX_IDLE,
    // Waiting for a header flit.
    RX_GET_ADDR,
    // Consuming the address payload flit.
    RX_GET_DATA,
    // Consuming remaining payload flits of a valid packet.
    RX_DROP
    // Draining remaining payload flits of a malformed/unsupported packet to
    // preserve stream framing.
  } rx_state_e;

  // Write issue FSM states.
  typedef enum logic [0:0] {
    AXI_IDLE,
    // No active internal write beat loaded.
    AXI_WRITE_ACTIVE
    // One internal write beat is driving AXI until both AW and W handshakes
    // have completed.
  } axi_state_e;

  // TX packetizer FSM states.
  typedef enum logic [1:0] {
    TX_IDLE,
    // Waiting for the next response packet descriptor.
    TX_SEND_HDR,
    // Sending the flit header.
    TX_SEND_STATUS,
    // Sending the status flit.
    TX_SEND_DATA
    // Sending response data flits.
  } tx_state_e;

  rx_state_e  rx_state_r,  rx_state_n;
  axi_state_e axi_state_r, axi_state_n;
  tx_state_e  tx_state_r,  tx_state_n;

  // RX parser state for the packet currently being consumed.
  logic [2:0]                   req_opcode_r, req_opcode_n;
  logic [12:0]                  req_payload_remaining_r, req_payload_remaining_n;
  logic [axil_addr_width_p-1:0] req_addr_r, req_addr_n;

  // Active read issue slot. One queued AR packet may expand into multiple
  // same-address AXI AR handshakes.
  logic                         rd_issue_active_r, rd_issue_active_n;
  logic [axil_addr_width_p-1:0] rd_issue_addr_r, rd_issue_addr_n;
  logic [12:0]                  rd_issue_remaining_r, rd_issue_remaining_n;

  // Active write issue slot. AW and W are tracked independently because AXI
  // permits them to handshake in any order.
  logic [axil_addr_width_p-1:0] wr_issue_addr_r, wr_issue_addr_n;
  logic [axil_data_width_p-1:0] wr_issue_data_r, wr_issue_data_n;
  logic                         wr_issue_last_r, wr_issue_last_n;
  logic                         aw_done_r, aw_done_n;
  logic                         w_done_r,  w_done_n;

  // Aggregation state for one AR packet's returning R beats.
  // The bridge accumulates:
  // - how many R beats belong to the current packet
  // - the first non-OKAY response code, if any
  logic        rd_resp_collect_active_r, rd_resp_collect_active_n;
  logic [12:0] rd_resp_collect_count_r,  rd_resp_collect_count_n;
  logic [1:0]  rd_resp_collect_status_r, rd_resp_collect_status_n;

  // Aggregation state for one AW packet's returning B beats.
  // Multiple underlying write completions produce one final aggregated OP_B.
  logic        wr_resp_collect_active_r, wr_resp_collect_active_n;
  logic [1:0]  wr_resp_collect_status_r, wr_resp_collect_status_n;

  // TX FSM active packet metadata. tx_active_r holds the packet currently being
  // serialized onto the TX flit interface.
  tx_resp_entry_s tx_active_r, tx_active_n;
  logic [12:0]    tx_data_remaining_r, tx_data_remaining_n;

  // Read-vs-write completion starvation counter. When reads keep winning over
  // an actually waiting write completion, this counter increments until one
  // conflict cycle force-grants the write side.
  logic [wr_starvation_cnt_width_lp-1:0] wr_starvation_cnt_r, wr_starvation_cnt_n;

  // Parsed read request FIFO.
  logic          rd_req_fifo_push_ready;
  logic          rd_req_fifo_pop_v;
  logic          rd_req_fifo_pop_yumi;
  rd_req_entry_s rd_req_fifo_pop_data;
  logic          rd_req_fifo_push_v;
  rd_req_entry_s rd_req_fifo_push_data;

  // Parsed write request FIFO.
  logic          wr_req_fifo_push_ready;
  logic          wr_req_fifo_pop_v;
  logic          wr_req_fifo_pop_yumi;
  wr_req_entry_s wr_req_fifo_pop_data;
  logic          wr_req_fifo_push_v;
  wr_req_entry_s wr_req_fifo_push_data;

  // Outstanding read FIFO. Each issued AR pushes one entry, with last marking
  // the final AR beat of one original AR packet.
  logic       rd_out_fifo_push_ready;
  logic       rd_out_fifo_pop_v;
  logic       rd_out_fifo_pop_yumi;
  out_entry_s rd_out_fifo_pop_data;
  logic       rd_out_fifo_push_v;
  out_entry_s rd_out_fifo_push_data;

  // Outstanding write FIFO. Each fully-issued AW/W pair pushes one entry.
  logic       wr_out_fifo_push_ready;
  logic       wr_out_fifo_pop_v;
  logic       wr_out_fifo_pop_yumi;
  out_entry_s wr_out_fifo_pop_data;
  logic       wr_out_fifo_push_v;
  out_entry_s wr_out_fifo_push_data;

  // Read data FIFO. RDATA words are stored in-order until the corresponding
  // aggregated OP_R packet reaches TX. In the current implementation, TX still
  // drains exactly data_count words for that response packet.
  logic                    rd_data_fifo_push_ready;
  logic                    rd_data_fifo_pop_v;
  logic                    rd_data_fifo_pop_yumi;
  logic [flit_width_p-1:0] rd_data_fifo_pop_data;
  logic                    rd_data_fifo_push_v;
  logic [flit_width_p-1:0] rd_data_fifo_push_data;

  // Generic TX response FIFO used for read responses, write responses, and
  // local parser-generated error responses.
  logic           tx_resp_fifo_push_ready;
  logic           tx_resp_fifo_pop_v;
  logic           tx_resp_fifo_pop_yumi;
  tx_resp_entry_s tx_resp_fifo_pop_data;
  logic           tx_resp_fifo_push_v;
  tx_resp_entry_s tx_resp_fifo_push_data;

  // Single-port TX response FIFO arbitration requests. Only one producer may
  // claim the actual FIFO push port in a cycle.
  logic           rx_local_resp_push_v;
  tx_resp_entry_s rx_local_resp_push_data;
  logic           rd_final_resp_push_v;
  tx_resp_entry_s rd_final_resp_push_data;
  logic           wr_final_resp_push_v;
  tx_resp_entry_s wr_final_resp_push_data;
  logic           rx_local_resp_can_push;
  logic           rd_final_resp_req;
  logic           wr_final_resp_req;

  // Handshake helpers.
  logic phy_rx_fire;
  logic rd_issue_fire;
  logic wr_aw_fire;
  logic wr_w_fire;
  logic wr_issue_complete;
  logic rd_resp_fire;
  logic wr_resp_fire;

  // Completion arbitration helpers.
  logic rd_resp_can_fire_base;
  logic wr_resp_can_fire_base;
  logic rd_resp_can_fire;
  logic wr_resp_can_fire;
  logic wr_force_priority;

  logic [12:0] rd_resp_final_count;
  logic [1:0]  rd_resp_final_status;
  logic [1:0]  wr_resp_final_status;

  // Parsed read request queue.
  bsg_fifo_1r1w_small #(
    .width_p            ($bits(rd_req_entry_s)),
    .els_p              (rd_req_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) rd_req_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (rd_req_fifo_push_v),
    .data_i (rd_req_fifo_push_data),
    .ready_o(rd_req_fifo_push_ready),
    .v_o    (rd_req_fifo_pop_v),
    .data_o (rd_req_fifo_pop_data),
    .yumi_i (rd_req_fifo_pop_yumi)
  );

  // Parsed write request queue.
  bsg_fifo_1r1w_small #(
    .width_p            ($bits(wr_req_entry_s)),
    .els_p              (wr_req_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) wr_req_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (wr_req_fifo_push_v),
    .data_i (wr_req_fifo_push_data),
    .ready_o(wr_req_fifo_push_ready),
    .v_o    (wr_req_fifo_pop_v),
    .data_o (wr_req_fifo_pop_data),
    .yumi_i (wr_req_fifo_pop_yumi)
  );

  // Outstanding read queue. One entry per issued AR beat.
  bsg_fifo_1r1w_small #(
    .width_p            ($bits(out_entry_s)),
    .els_p              (rd_out_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) rd_out_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (rd_out_fifo_push_v),
    .data_i (rd_out_fifo_push_data),
    .ready_o(rd_out_fifo_push_ready),
    .v_o    (rd_out_fifo_pop_v),
    .data_o (rd_out_fifo_pop_data),
    .yumi_i (rd_out_fifo_pop_yumi)
  );

  // Outstanding write queue. One entry per fully-issued AW/W pair.
  bsg_fifo_1r1w_small #(
    .width_p            ($bits(out_entry_s)),
    .els_p              (wr_out_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) wr_out_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (wr_out_fifo_push_v),
    .data_i (wr_out_fifo_push_data),
    .ready_o(wr_out_fifo_push_ready),
    .v_o    (wr_out_fifo_pop_v),
    .data_o (wr_out_fifo_pop_data),
    .yumi_i (wr_out_fifo_pop_yumi)
  );

  // Returned read-data queue.
  bsg_fifo_1r1w_small #(
    .width_p            (flit_width_p),
    .els_p              (rd_data_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) rd_data_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (rd_data_fifo_push_v),
    .data_i (rd_data_fifo_push_data),
    .ready_o(rd_data_fifo_push_ready),
    .v_o    (rd_data_fifo_pop_v),
    .data_o (rd_data_fifo_pop_data),
    .yumi_i (rd_data_fifo_pop_yumi)
  );

  // Generic response descriptor queue.
  bsg_fifo_1r1w_small #(
    .width_p            ($bits(tx_resp_entry_s)),
    .els_p              (tx_resp_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) tx_resp_fifo_i (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (tx_resp_fifo_push_v),
    .data_i (tx_resp_fifo_push_data),
    .ready_o(tx_resp_fifo_push_ready),
    .v_o    (tx_resp_fifo_pop_v),
    .data_o (tx_resp_fifo_pop_data),
    .yumi_i (tx_resp_fifo_pop_yumi)
  );

  assign phy_rx_fire       = phy_rx_v_i & phy_rx_ready_o;
  assign rd_issue_fire     = m_axil_arvalid_o & m_axil_arready_i;
  assign wr_aw_fire        = m_axil_awvalid_o & m_axil_awready_i;
  assign wr_w_fire         = m_axil_wvalid_o  & m_axil_wready_i;
  assign wr_issue_complete = (axi_state_r == AXI_WRITE_ACTIVE)
                           && (aw_done_r | wr_aw_fire)
                           && (w_done_r  | wr_w_fire);
  assign rd_resp_fire      = m_axil_rvalid_i & m_axil_rready_o;
  assign wr_resp_fire      = m_axil_bvalid_i & m_axil_bready_o;
  assign rd_final_resp_req = rd_resp_fire & rd_out_fifo_pop_data.last;
  assign wr_final_resp_req = wr_resp_fire & wr_out_fifo_pop_data.last;

  assign rd_resp_final_count
    = rd_resp_collect_active_r ? (rd_resp_collect_count_r + 13'd1) : 13'd1;

  assign rd_resp_final_status
    = (rd_resp_collect_active_r && (rd_resp_collect_status_r != 2'b00))
      ? rd_resp_collect_status_r
      : m_axil_rresp_i;

  assign wr_resp_final_status
    = (wr_resp_collect_active_r && (wr_resp_collect_status_r != 2'b00))
      ? wr_resp_collect_status_r
      : m_axil_bresp_i;

  // A read completion can proceed when there is an outstanding read entry,
  // room for one data word in rd_data_fifo, and on the final beat, room in the
  // generic response FIFO for the aggregated OP_R descriptor.
  assign rd_resp_can_fire_base = rd_out_fifo_pop_v
                              && rd_data_fifo_push_ready
                              && (!rd_out_fifo_pop_data.last || tx_resp_fifo_push_ready);

  // A write completion can proceed when there is an outstanding write entry
  // and, on the final beat of an AW packet, room in the generic response FIFO
  // to emit the one aggregated OP_B packet.
  assign wr_resp_can_fire_base = wr_out_fifo_pop_v
                              && (!wr_out_fifo_pop_data.last || tx_resp_fifo_push_ready);

  // Once the starvation counter reaches the limit, the next true same-cycle
  // R/B conflict forces the write completion to win.
  assign wr_force_priority = (wr_starvation_cnt_r >= wr_starvation_limit_p)
                          && m_axil_rvalid_i
                          && rd_resp_can_fire_base
                          && m_axil_bvalid_i
                          && wr_resp_can_fire_base;

  assign rd_resp_can_fire = rd_resp_can_fire_base && !wr_force_priority;

  assign wr_resp_can_fire = wr_resp_can_fire_base
                         && !(m_axil_rvalid_i && rd_resp_can_fire_base && !wr_force_priority);

  // Local parser-generated errors share the generic response FIFO with final
  // read and write responses.
  assign rx_local_resp_can_push = tx_resp_fifo_push_ready
                               && !rd_final_resp_req
                               && !wr_final_resp_req;

  // Main combinational block:
  // - computes next-state for all registers
  // - drives AXI/flit outputs
  // - controls FIFO push/pop handshakes
  always_comb begin
    rx_state_n               = rx_state_r;
    axi_state_n              = axi_state_r;
    tx_state_n               = tx_state_r;

    req_opcode_n             = req_opcode_r;
    req_payload_remaining_n  = req_payload_remaining_r;
    req_addr_n               = req_addr_r;

    rd_issue_active_n        = rd_issue_active_r;
    rd_issue_addr_n          = rd_issue_addr_r;
    rd_issue_remaining_n     = rd_issue_remaining_r;

    wr_issue_addr_n          = wr_issue_addr_r;
    wr_issue_data_n          = wr_issue_data_r;
    wr_issue_last_n          = wr_issue_last_r;
    aw_done_n                = aw_done_r;
    w_done_n                 = w_done_r;

    rd_resp_collect_active_n = rd_resp_collect_active_r;
    rd_resp_collect_count_n  = rd_resp_collect_count_r;
    rd_resp_collect_status_n = rd_resp_collect_status_r;

    wr_resp_collect_active_n = wr_resp_collect_active_r;
    wr_resp_collect_status_n = wr_resp_collect_status_r;

    tx_active_n              = tx_active_r;
    tx_data_remaining_n      = tx_data_remaining_r;

    wr_starvation_cnt_n      = wr_starvation_cnt_r;

    rd_req_fifo_push_v       = 1'b0;
    rd_req_fifo_push_data    = '0;
    rd_req_fifo_pop_yumi     = 1'b0;

    wr_req_fifo_push_v       = 1'b0;
    wr_req_fifo_push_data    = '0;
    wr_req_fifo_pop_yumi     = 1'b0;

    rd_out_fifo_push_v       = 1'b0;
    rd_out_fifo_push_data    = '{last: 1'b0};
    rd_out_fifo_pop_yumi     = 1'b0;

    wr_out_fifo_push_v       = 1'b0;
    wr_out_fifo_push_data    = '{last: 1'b0};
    wr_out_fifo_pop_yumi     = 1'b0;

    rd_data_fifo_push_v      = 1'b0;
    rd_data_fifo_push_data   = '0;
    rd_data_fifo_pop_yumi    = 1'b0;

    tx_resp_fifo_push_v      = 1'b0;
    tx_resp_fifo_push_data   = '0;
    tx_resp_fifo_pop_yumi    = 1'b0;

    rx_local_resp_push_v     = 1'b0;
    rx_local_resp_push_data  = '0;
    rd_final_resp_push_v     = 1'b0;
    rd_final_resp_push_data  = '0;
    wr_final_resp_push_v     = 1'b0;
    wr_final_resp_push_data  = '0;

    phy_rx_ready_o           = 1'b0;
    phy_tx_v_o               = 1'b0;
    phy_tx_data_o            = '0;

    m_axil_araddr_o          = rd_issue_addr_r;
    m_axil_arprot_o          = AXI_PROT_NORMAL_DATA_LP;
    m_axil_arvalid_o         = 1'b0;

    m_axil_awaddr_o          = wr_issue_addr_r;
    m_axil_awprot_o          = AXI_PROT_NORMAL_DATA_LP;
    m_axil_awvalid_o         = 1'b0;

    m_axil_wdata_o           = wr_issue_data_r;
    m_axil_wstrb_o           = AXI_WSTRB_ALL_LP;
    m_axil_wvalid_o          = 1'b0;

    m_axil_rready_o          = rd_resp_can_fire;
    m_axil_bready_o          = wr_resp_can_fire;

    // Starvation counter:
    // - reset on any successful write completion
    // - increment only when a read completion actually fires while a write
    //   completion was also actually waiting that cycle
    if (wr_resp_fire) begin
      wr_starvation_cnt_n = '0;
    end
    else if (rd_resp_fire && m_axil_bvalid_i && wr_resp_can_fire_base) begin
      if (wr_starvation_cnt_r < wr_starvation_limit_p) begin
        wr_starvation_cnt_n = wr_starvation_cnt_r + 1'b1;
      end
    end

    // ----------------------------------------------------------------------
    // RX parser
    // ----------------------------------------------------------------------
    // The parser accepts one LEN-framed packet at a time. Unsupported packets
    // are not allowed to desynchronize the stream; RX_DROP consumes the exact
    // remaining payload count from the accepted header.
    unique case (rx_state_r)
      RX_IDLE: begin
        phy_rx_ready_o = 1'b1;

        if (phy_rx_fire) begin
          req_opcode_n            = phy_rx_data_i[15:13];
          req_payload_remaining_n = phy_rx_data_i[12:0];
          req_addr_n              = '0;

          unique case (phy_rx_data_i[15:13])
            OP_AR: begin
              rx_state_n = (phy_rx_data_i[12:0] == AR_REQ_LEN_LP)
                         ? RX_GET_ADDR
                         : ((phy_rx_data_i[12:0] == 13'd0) ? RX_IDLE : RX_DROP);
            end

            OP_AW: begin
              rx_state_n = (phy_rx_data_i[12:0] >= 13'd2)
                         ? RX_GET_ADDR
                         : ((phy_rx_data_i[12:0] == 13'd0) ? RX_IDLE : RX_DROP);
            end

            default: begin
              rx_state_n = (phy_rx_data_i[12:0] == 13'd0) ? RX_IDLE : RX_DROP;
            end
          endcase
        end
      end

      RX_GET_ADDR: begin
        phy_rx_ready_o = 1'b1;

        if (phy_rx_fire) begin
          req_addr_n              = phy_rx_data_i[axil_addr_width_p-1:0];
          req_payload_remaining_n = req_payload_remaining_r - 13'd1;

          if (req_opcode_r == OP_AR) begin
            rx_state_n = (req_payload_remaining_r == 13'd2)
                       ? RX_GET_DATA
                       : ((req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP);
          end
          else if (req_opcode_r == OP_AW) begin
            rx_state_n = (req_payload_remaining_r >= 13'd2)
                       ? RX_GET_DATA
                       : ((req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP);
          end
          else begin
            rx_state_n = (req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP;
          end
        end
      end

      RX_GET_DATA: begin
        // AR payload[1] is the read count. Counts of 0 or counts larger than
        // either the outstanding-read FIFO depth or the read-data FIFO depth
        // are rejected locally.
        //
        // AW payload[1..] are data flits. Each one becomes one internal
        // wr_req entry using the same packet address, and the final one is
        // tagged with last so completion aggregation knows when to emit OP_B.
        if (req_opcode_r == OP_AR) begin
          if (req_payload_remaining_r == 13'd1) begin
            phy_rx_ready_o = ((phy_rx_data_i[12:0] == 13'd0)
                           || (phy_rx_data_i[12:0] > max_rd_count_lp))
                           ? rx_local_resp_can_push
                           : rd_req_fifo_push_ready;
          end
          else begin
            phy_rx_ready_o = 1'b1;
          end
        end
        else begin
          phy_rx_ready_o = wr_req_fifo_push_ready;
        end

        if (phy_rx_fire) begin
          req_payload_remaining_n = req_payload_remaining_r - 13'd1;

          if (req_opcode_r == OP_AR) begin
            if (req_payload_remaining_r == 13'd1) begin
              if ((phy_rx_data_i[12:0] != 13'd0)
               && (phy_rx_data_i[12:0] <= max_rd_count_lp)) begin
                rd_req_fifo_push_v    = 1'b1;
                rd_req_fifo_push_data = '{
                  addr : req_addr_r,
                  count: phy_rx_data_i[12:0]
                };
              end
              else begin
                rx_local_resp_push_v    = 1'b1;
                rx_local_resp_push_data = '{
                  opcode      : OP_R,
                  len         : B_RESP_LEN_LP,
                  status_flit : {14'b0, BAD_REQ_RESP_LP},
                  data_count  : 13'd0
                };
              end
              rx_state_n = RX_IDLE;
            end
            else begin
              rx_state_n = RX_DROP;
            end
          end
          else begin
            wr_req_fifo_push_v    = 1'b1;
            wr_req_fifo_push_data = '{
              addr: req_addr_r,
              data: phy_rx_data_i[axil_data_width_p-1:0],
              last: (req_payload_remaining_r == 13'd1)
            };

            rx_state_n = (req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_GET_DATA;
          end
        end
      end

      RX_DROP: begin
        // Drain the remaining payload of an invalid packet so the following
        // flit after LEN payload words is treated as the next header.
        if (req_payload_remaining_r == 13'd0) begin
          rx_state_n     = RX_IDLE;
          phy_rx_ready_o = 1'b0;
        end
        else begin
          phy_rx_ready_o = 1'b1;
          if (phy_rx_fire) begin
            req_payload_remaining_n = req_payload_remaining_r - 13'd1;
            if (req_payload_remaining_r == 13'd1) begin
              rx_state_n = RX_IDLE;
            end
          end
        end
      end

      default: begin
        rx_state_n = RX_IDLE;
      end
    endcase

    // ----------------------------------------------------------------------
    // Read issue path
    // ----------------------------------------------------------------------
    // One parsed AR packet expands into N same-address AXI AR beats. Each
    // issued beat pushes one outstanding-read marker, and the final beat of the
    // packet carries last=1.
    if (!rd_issue_active_r && rd_req_fifo_pop_v) begin
      rd_issue_active_n    = 1'b1;
      rd_issue_addr_n      = rd_req_fifo_pop_data.addr;
      rd_issue_remaining_n = rd_req_fifo_pop_data.count;
      rd_req_fifo_pop_yumi = 1'b1;
    end

    if (rd_issue_active_r && rd_out_fifo_push_ready) begin
      m_axil_araddr_o  = rd_issue_addr_r;
      m_axil_arvalid_o = 1'b1;
    end

    if (rd_issue_fire) begin
      rd_out_fifo_push_v    = 1'b1;
      rd_out_fifo_push_data = '{last: (rd_issue_remaining_r == 13'd1)};
      rd_issue_remaining_n  = rd_issue_remaining_r - 13'd1;

      if (rd_issue_remaining_r == 13'd1) begin
        rd_issue_active_n = 1'b0;
      end
    end

    // ----------------------------------------------------------------------
    // Write issue path
    // ----------------------------------------------------------------------
    // One wr_req entry corresponds to one AXI write beat. AW and W may
    // handshake in any order; only after both complete do we push to the
    // outstanding write FIFO.
    unique case (axi_state_r)
      AXI_IDLE: begin
        aw_done_n = 1'b0;
        w_done_n  = 1'b0;

        if (wr_req_fifo_pop_v && wr_out_fifo_push_ready) begin
          // Same-address mode is fixed: every internal write beat in one AW
          // packet reuses the packet address captured by the RX parser.
          wr_issue_addr_n = wr_req_fifo_pop_data.addr;
          wr_issue_data_n = wr_req_fifo_pop_data.data;
          wr_issue_last_n = wr_req_fifo_pop_data.last;
          axi_state_n     = AXI_WRITE_ACTIVE;
        end
      end

      AXI_WRITE_ACTIVE: begin
        m_axil_awvalid_o = ~aw_done_r;
        m_axil_wvalid_o  = ~w_done_r;

        if (wr_aw_fire) begin
          aw_done_n = 1'b1;
        end

        if (wr_w_fire) begin
          w_done_n = 1'b1;
        end

        if (wr_issue_complete) begin
          wr_req_fifo_pop_yumi  = 1'b1;
          wr_out_fifo_push_v    = 1'b1;
          wr_out_fifo_push_data = '{last: wr_issue_last_r};
          axi_state_n           = AXI_IDLE;
        end
      end

      default: begin
        axi_state_n = AXI_IDLE;
      end
    endcase

    // ----------------------------------------------------------------------
    // Completion handling
    // ----------------------------------------------------------------------
    // Read and write completions are handled independently and matched against
    // separate outstanding FIFOs. That preserves AXI-Lite ordering rules per
    // stream without inventing a mixed global order.
    if (rd_resp_fire) begin
      rd_out_fifo_pop_yumi   = 1'b1;
      rd_data_fifo_push_v    = 1'b1;
      rd_data_fifo_push_data = m_axil_rdata_i;

      if (!rd_resp_collect_active_r) begin
        rd_resp_collect_active_n = 1'b1;
        rd_resp_collect_count_n  = 13'd1;
        rd_resp_collect_status_n = m_axil_rresp_i;
      end
      else begin
        rd_resp_collect_count_n = rd_resp_collect_count_r + 13'd1;
        if ((rd_resp_collect_status_r == 2'b00) && (m_axil_rresp_i != 2'b00)) begin
          rd_resp_collect_status_n = m_axil_rresp_i;
        end
      end

      if (rd_out_fifo_pop_data.last) begin
        // Final R beat of the packet: emit one aggregated OP_R descriptor.
        rd_final_resp_push_v    = 1'b1;
        rd_final_resp_push_data = '{
          opcode      : OP_R,
          len         : 13'd1 + rd_resp_final_count,
          status_flit : {14'b0, rd_resp_final_status},
          data_count  : rd_resp_final_count
        };
        rd_resp_collect_active_n = 1'b0;
        rd_resp_collect_count_n  = '0;
        rd_resp_collect_status_n = '0;
      end
    end
    else if (wr_resp_fire) begin
      wr_out_fifo_pop_yumi = 1'b1;

      if (!wr_resp_collect_active_r) begin
        wr_resp_collect_active_n = 1'b1;
        wr_resp_collect_status_n = m_axil_bresp_i;
      end
      else if ((wr_resp_collect_status_r == 2'b00) && (m_axil_bresp_i != 2'b00)) begin
        wr_resp_collect_status_n = m_axil_bresp_i;
      end

      if (wr_out_fifo_pop_data.last) begin
        // Final B beat of the packet: emit one aggregated OP_B descriptor.
        wr_final_resp_push_v    = 1'b1;
        wr_final_resp_push_data = '{
          opcode      : OP_B,
          len         : B_RESP_LEN_LP,
          status_flit : {14'b0, wr_resp_final_status},
          data_count  : 13'd0
        };
        wr_resp_collect_active_n = 1'b0;
        wr_resp_collect_status_n = '0;
      end
    end

    // Single push port into the generic response FIFO.
    // Priority:
    // 1. final read response
    // 2. final write response
    // 3. parser-local error response
    if (rd_final_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = rd_final_resp_push_data;
    end
    else if (wr_final_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = wr_final_resp_push_data;
    end
    else if (rx_local_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = rx_local_resp_push_data;
    end

    // ----------------------------------------------------------------------
    // TX packetizer
    // ----------------------------------------------------------------------
    // TX always emits packets in flit order:
    // 1. header
    // 2. status
    // 3. optional data flits
    // The current TX path drains read data from rd_data_fifo based on the
    // queued response descriptor's data_count.
    unique case (tx_state_r)
      TX_IDLE: begin
        if (tx_resp_fifo_pop_v) begin
          tx_active_n         = tx_resp_fifo_pop_data;
          tx_data_remaining_n = tx_resp_fifo_pop_data.data_count;
          tx_state_n          = TX_SEND_HDR;
        end
      end

      TX_SEND_HDR: begin
        phy_tx_v_o    = 1'b1;
        phy_tx_data_o = {tx_active_r.opcode, tx_active_r.len};

        if (phy_tx_ready_i) begin
          tx_state_n = TX_SEND_STATUS;
        end
      end

      TX_SEND_STATUS: begin
        phy_tx_v_o    = 1'b1;
        phy_tx_data_o = tx_active_r.status_flit;

        if (phy_tx_ready_i) begin
          if (tx_active_r.data_count != 13'd0) begin
            tx_state_n = TX_SEND_DATA;
          end
          else begin
            tx_resp_fifo_pop_yumi = 1'b1;
            tx_state_n            = TX_IDLE;
          end
        end
      end

      TX_SEND_DATA: begin
        // For packets with data payloads, drive one data flit per accepted
        // handshake until tx_data_remaining reaches 1.
        phy_tx_v_o    = rd_data_fifo_pop_v;
        phy_tx_data_o = rd_data_fifo_pop_data;

        if (rd_data_fifo_pop_v && phy_tx_ready_i) begin
          rd_data_fifo_pop_yumi = 1'b1;
          tx_data_remaining_n   = tx_data_remaining_r - 13'd1;

          if (tx_data_remaining_r == 13'd1) begin
            tx_resp_fifo_pop_yumi = 1'b1;
            tx_state_n            = TX_IDLE;
          end
        end
      end

      default: begin
        tx_state_n = TX_IDLE;
      end
    endcase
  end

  // Sequential state/register update.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rx_state_r               <= RX_IDLE;
      axi_state_r              <= AXI_IDLE;
      tx_state_r               <= TX_IDLE;

      req_opcode_r             <= '0;
      req_payload_remaining_r  <= '0;
      req_addr_r               <= '0;

      rd_issue_active_r        <= 1'b0;
      rd_issue_addr_r          <= '0;
      rd_issue_remaining_r     <= '0;

      wr_issue_addr_r          <= '0;
      wr_issue_data_r          <= '0;
      wr_issue_last_r          <= 1'b0;
      aw_done_r                <= 1'b0;
      w_done_r                 <= 1'b0;

      rd_resp_collect_active_r <= 1'b0;
      rd_resp_collect_count_r  <= '0;
      rd_resp_collect_status_r <= '0;

      wr_resp_collect_active_r <= 1'b0;
      wr_resp_collect_status_r <= '0;

      tx_active_r              <= '0;
      tx_data_remaining_r      <= '0;

      wr_starvation_cnt_r      <= '0;
    end
    else begin
      rx_state_r               <= rx_state_n;
      axi_state_r              <= axi_state_n;
      tx_state_r               <= tx_state_n;

      req_opcode_r             <= req_opcode_n;
      req_payload_remaining_r  <= req_payload_remaining_n;
      req_addr_r               <= req_addr_n;

      rd_issue_active_r        <= rd_issue_active_n;
      rd_issue_addr_r          <= rd_issue_addr_n;
      rd_issue_remaining_r     <= rd_issue_remaining_n;

      wr_issue_addr_r          <= wr_issue_addr_n;
      wr_issue_data_r          <= wr_issue_data_n;
      wr_issue_last_r          <= wr_issue_last_n;
      aw_done_r                <= aw_done_n;
      w_done_r                 <= w_done_n;

      rd_resp_collect_active_r <= rd_resp_collect_active_n;
      rd_resp_collect_count_r  <= rd_resp_collect_count_n;
      rd_resp_collect_status_r <= rd_resp_collect_status_n;

      wr_resp_collect_active_r <= wr_resp_collect_active_n;
      wr_resp_collect_status_r <= wr_resp_collect_status_n;

      tx_active_r              <= tx_active_n;
      tx_data_remaining_r      <= tx_data_remaining_n;

      wr_starvation_cnt_r      <= wr_starvation_cnt_n;
    end
  end

endmodule
