// =============================================================================
// flit_axi4_bridge.sv
//
// LEN-framed 16-bit flit ↔ full AXI4 burst master bridge.
//
// Differences from flit_axil_bridge (AXI-Lite version)
// -------------------------------------------------------
//   Writes:
//     Old: N separate AW+W single-beat transactions per AW packet; N B responses
//          aggregated into one OP_B.
//     New: one AW (AWLEN=N-1) + N W beats (WLAST on final) per AW packet;
//          one B response → one OP_B.
//
//   Reads:
//     Old: N separate AR transactions; N R responses aggregated into one OP_R.
//     New: one AR (ARLEN=N-1); N R beats returned (RLAST on final) → one OP_R.
//
//   New ports (vs AXI-Lite):
//     m_axi_awlen_o [7:0]  — AWLEN driven on AW channel
//     m_axi_wlast_o        — WLAST driven on W channel
//     m_axi_arlen_o [7:0]  — ARLEN driven on AR channel
//     m_axi_rlast_i        — RLAST sampled on R channel
// =============================================================================

module flit_axi4_bridge
  #(parameter int flit_width_p          = 16
   ,parameter int axil_addr_width_p     = 16
   ,parameter int axil_data_width_p     = 16
   ,parameter int rd_req_fifo_els_p     = 16
   ,parameter int wr_req_fifo_els_p     = 16
   ,parameter int rd_out_fifo_els_p     = 16
   ,parameter int rd_data_fifo_els_p    = 16
   ,parameter int wr_out_fifo_els_p     = 16
   ,parameter int tx_resp_fifo_els_p    = 16
   ,parameter int wr_starvation_limit_p = 16
   )
  (input  logic                              clk_i
   ,input  logic                             rst_i

   ,input  logic                             phy_rx_v_i
   ,input  logic [flit_width_p-1:0]          phy_rx_data_i
   ,output logic                             phy_rx_ready_o

   ,output logic                             phy_tx_v_o
   ,output logic [flit_width_p-1:0]          phy_tx_data_o
   ,input  logic                             phy_tx_ready_i

   // AXI4 write address channel
   ,output logic [axil_addr_width_p-1:0]     m_axi_awaddr_o
   ,output logic [7:0]                       m_axi_awlen_o    // NEW: burst length
   ,output logic [2:0]                       m_axi_awprot_o
   ,output logic                             m_axi_awvalid_o
   ,input  logic                             m_axi_awready_i

   // AXI4 write data channel
   ,output logic [axil_data_width_p-1:0]     m_axi_wdata_o
   ,output logic [(axil_data_width_p/8)-1:0] m_axi_wstrb_o
   ,output logic                             m_axi_wlast_o    // NEW: write last
   ,output logic                             m_axi_wvalid_o
   ,input  logic                             m_axi_wready_i

   // AXI4 write response channel
   ,input  logic [1:0]                       m_axi_bresp_i
   ,input  logic                             m_axi_bvalid_i
   ,output logic                             m_axi_bready_o

   // AXI4 read address channel
   ,output logic [axil_addr_width_p-1:0]     m_axi_araddr_o
   ,output logic [7:0]                       m_axi_arlen_o    // NEW: burst length
   ,output logic [2:0]                       m_axi_arprot_o
   ,output logic                             m_axi_arvalid_o
   ,input  logic                             m_axi_arready_i

   // AXI4 read data channel
   ,input  logic [axil_data_width_p-1:0]     m_axi_rdata_i
   ,input  logic [1:0]                       m_axi_rresp_i
   ,input  logic                             m_axi_rlast_i    // NEW: read last
   ,input  logic                             m_axi_rvalid_i
   ,output logic                             m_axi_rready_o
   );

  initial begin
    if (flit_width_p != 16)
      $error("flit_axi4_bridge requires flit_width_p=16");
    if (axil_addr_width_p != 16)
      $error("flit_axi4_bridge requires axil_addr_width_p=16");
    if (axil_data_width_p != 16)
      $error("flit_axi4_bridge requires axil_data_width_p=16");
    if (rd_data_fifo_els_p < 1)
      $error("flit_axi4_bridge requires rd_data_fifo_els_p >= 1");
    if (wr_starvation_limit_p < 1)
      $error("flit_axi4_bridge requires wr_starvation_limit_p >= 1");
  end

  localparam logic [2:0] OP_AR = 3'd0;
  localparam logic [2:0] OP_AW = 3'd1;
  localparam logic [2:0] OP_R  = 3'd2;
  localparam logic [2:0] OP_B  = 3'd3;

  localparam logic [12:0] AR_REQ_LEN_LP   = 13'd2;
  localparam logic [12:0] B_RESP_LEN_LP   = 13'd1;
  localparam logic [1:0]  BAD_REQ_RESP_LP = 2'b10;

  localparam logic [2:0] AXI_PROT_LP = 3'b000;
  localparam logic [(axil_data_width_p/8)-1:0] AXI_WSTRB_ALL_LP
    = {(axil_data_width_p/8){1'b1}};

  localparam int max_rd_count_lp
    = (rd_out_fifo_els_p < rd_data_fifo_els_p)
      ? rd_out_fifo_els_p
      : rd_data_fifo_els_p;

  localparam int wr_starvation_cnt_width_lp
    = (wr_starvation_limit_p > 1) ? $clog2(wr_starvation_limit_p+1) : 1;

  // --------------------------------------------------------------------------
  // Internal types
  // --------------------------------------------------------------------------

  typedef struct packed {
    logic [axil_addr_width_p-1:0] addr;
    logic [12:0]                  count;
  } rd_req_entry_s;

  typedef struct packed {
    logic [axil_addr_width_p-1:0] addr;
    logic [axil_data_width_p-1:0] data;
    logic [7:0]                   aw_len; // AWLEN = N-1; valid only when first=1
    logic                         first;  // first beat of this AW burst
    logic                         last;   // last beat of this AW burst
  } wr_req_entry_s;

  typedef struct packed {
    logic last;
  } out_entry_s;

  typedef struct packed {
    logic [2:0]              opcode;
    logic [12:0]             len;
    logic [flit_width_p-1:0] status_flit;
    logic [12:0]             data_count;
  } tx_resp_entry_s;

  // --------------------------------------------------------------------------
  // FSM state types
  // --------------------------------------------------------------------------

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_GET_ADDR,
    RX_GET_DATA,
    RX_DROP
  } rx_state_e;

  // AXI_NEXT_BEAT: 1-cycle bubble to load the next W data word from wr_req_fifo
  typedef enum logic [1:0] {
    AXI_IDLE,
    AXI_WRITE_ACTIVE,
    AXI_NEXT_BEAT
  } axi_state_e;

  typedef enum logic [1:0] {
    TX_IDLE,
    TX_SEND_HDR,
    TX_SEND_STATUS,
    TX_SEND_DATA
  } tx_state_e;

  // --------------------------------------------------------------------------
  // State registers
  // --------------------------------------------------------------------------

  rx_state_e  rx_state_r,  rx_state_n;
  axi_state_e axi_state_r, axi_state_n;
  tx_state_e  tx_state_r,  tx_state_n;

  logic [2:0]                   req_opcode_r,             req_opcode_n;
  logic [12:0]                  req_payload_remaining_r,  req_payload_remaining_n;
  logic [axil_addr_width_p-1:0] req_addr_r,               req_addr_n;
  logic                         is_first_data_r,          is_first_data_n;

  logic                         rd_issue_active_r, rd_issue_active_n;
  logic [axil_addr_width_p-1:0] rd_issue_addr_r,   rd_issue_addr_n;
  logic [12:0]                  rd_issue_count_r,  rd_issue_count_n; // full count (= ARLEN+1)

  logic [axil_addr_width_p-1:0] wr_issue_addr_r,  wr_issue_addr_n;
  logic [axil_data_width_p-1:0] wr_issue_data_r,  wr_issue_data_n;
  logic [7:0]                   wr_issue_awlen_r, wr_issue_awlen_n;
  logic                         wr_issue_last_r,  wr_issue_last_n;
  logic                         aw_done_r,        aw_done_n;

  logic        rd_resp_collect_active_r, rd_resp_collect_active_n;
  logic [12:0] rd_resp_collect_count_r,  rd_resp_collect_count_n;
  logic [1:0]  rd_resp_collect_status_r, rd_resp_collect_status_n;

  logic        wr_resp_collect_active_r, wr_resp_collect_active_n;
  logic [1:0]  wr_resp_collect_status_r, wr_resp_collect_status_n;

  tx_resp_entry_s tx_active_r,         tx_active_n;
  logic [12:0]    tx_data_remaining_r, tx_data_remaining_n;

  logic [wr_starvation_cnt_width_lp-1:0] wr_starvation_cnt_r, wr_starvation_cnt_n;

  // --------------------------------------------------------------------------
  // FIFO signals
  // --------------------------------------------------------------------------

  logic          rd_req_fifo_push_ready, rd_req_fifo_pop_v, rd_req_fifo_pop_yumi;
  rd_req_entry_s rd_req_fifo_pop_data;
  logic          rd_req_fifo_push_v;
  rd_req_entry_s rd_req_fifo_push_data;

  logic          wr_req_fifo_push_ready, wr_req_fifo_pop_v, wr_req_fifo_pop_yumi;
  wr_req_entry_s wr_req_fifo_pop_data;
  logic          wr_req_fifo_push_v;
  wr_req_entry_s wr_req_fifo_push_data;

  logic       rd_out_fifo_push_ready, rd_out_fifo_pop_v, rd_out_fifo_pop_yumi;
  out_entry_s rd_out_fifo_pop_data;
  logic       rd_out_fifo_push_v;
  out_entry_s rd_out_fifo_push_data;

  logic       wr_out_fifo_push_ready, wr_out_fifo_pop_v, wr_out_fifo_pop_yumi;
  out_entry_s wr_out_fifo_pop_data;
  logic       wr_out_fifo_push_v;
  out_entry_s wr_out_fifo_push_data;

  logic                    rd_data_fifo_push_ready, rd_data_fifo_pop_v, rd_data_fifo_pop_yumi;
  logic [flit_width_p-1:0] rd_data_fifo_pop_data;
  logic                    rd_data_fifo_push_v;
  logic [flit_width_p-1:0] rd_data_fifo_push_data;

  logic           tx_resp_fifo_push_ready, tx_resp_fifo_pop_v, tx_resp_fifo_pop_yumi;
  tx_resp_entry_s tx_resp_fifo_pop_data;
  logic           tx_resp_fifo_push_v;
  tx_resp_entry_s tx_resp_fifo_push_data;

  logic           rx_local_resp_push_v,   rx_local_resp_can_push;
  tx_resp_entry_s rx_local_resp_push_data;
  logic           rd_final_resp_push_v,   rd_final_resp_req;
  tx_resp_entry_s rd_final_resp_push_data;
  logic           wr_final_resp_push_v,   wr_final_resp_req;
  tx_resp_entry_s wr_final_resp_push_data;

  // --------------------------------------------------------------------------
  // Handshake helpers
  // --------------------------------------------------------------------------

  logic phy_rx_fire;
  logic rd_issue_fire;
  logic wr_aw_fire, wr_w_fire;
  logic rd_resp_fire, wr_resp_fire;
  logic rd_resp_can_fire_base, wr_resp_can_fire_base;
  logic rd_resp_can_fire,      wr_resp_can_fire;
  logic wr_force_priority;

  logic [12:0] rd_resp_final_count;
  logic [1:0]  rd_resp_final_status;
  logic [1:0]  wr_resp_final_status;

  // --------------------------------------------------------------------------
  // FIFOs
  // --------------------------------------------------------------------------

  bsg_fifo_1r1w_small #(.width_p($bits(rd_req_entry_s)), .els_p(rd_req_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) rd_req_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(rd_req_fifo_push_v), .data_i(rd_req_fifo_push_data), .ready_o(rd_req_fifo_push_ready),
    .v_o(rd_req_fifo_pop_v),  .data_o(rd_req_fifo_pop_data),  .yumi_i(rd_req_fifo_pop_yumi));

  bsg_fifo_1r1w_small #(.width_p($bits(wr_req_entry_s)), .els_p(wr_req_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) wr_req_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(wr_req_fifo_push_v), .data_i(wr_req_fifo_push_data), .ready_o(wr_req_fifo_push_ready),
    .v_o(wr_req_fifo_pop_v),  .data_o(wr_req_fifo_pop_data),  .yumi_i(wr_req_fifo_pop_yumi));

  bsg_fifo_1r1w_small #(.width_p($bits(out_entry_s)), .els_p(rd_out_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) rd_out_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(rd_out_fifo_push_v), .data_i(rd_out_fifo_push_data), .ready_o(rd_out_fifo_push_ready),
    .v_o(rd_out_fifo_pop_v),  .data_o(rd_out_fifo_pop_data),  .yumi_i(rd_out_fifo_pop_yumi));

  bsg_fifo_1r1w_small #(.width_p($bits(out_entry_s)), .els_p(wr_out_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) wr_out_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(wr_out_fifo_push_v), .data_i(wr_out_fifo_push_data), .ready_o(wr_out_fifo_push_ready),
    .v_o(wr_out_fifo_pop_v),  .data_o(wr_out_fifo_pop_data),  .yumi_i(wr_out_fifo_pop_yumi));

  bsg_fifo_1r1w_small #(.width_p(flit_width_p), .els_p(rd_data_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) rd_data_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(rd_data_fifo_push_v), .data_i(rd_data_fifo_push_data), .ready_o(rd_data_fifo_push_ready),
    .v_o(rd_data_fifo_pop_v),  .data_o(rd_data_fifo_pop_data),  .yumi_i(rd_data_fifo_pop_yumi));

  bsg_fifo_1r1w_small #(.width_p($bits(tx_resp_entry_s)), .els_p(tx_resp_fifo_els_p),
                         .harden_p(0), .ready_THEN_valid_p(0)) tx_resp_fifo_i (
    .clk_i(clk_i), .reset_i(rst_i),
    .v_i(tx_resp_fifo_push_v), .data_i(tx_resp_fifo_push_data), .ready_o(tx_resp_fifo_push_ready),
    .v_o(tx_resp_fifo_pop_v),  .data_o(tx_resp_fifo_pop_data),  .yumi_i(tx_resp_fifo_pop_yumi));

  // --------------------------------------------------------------------------
  // Combinational assignments
  // --------------------------------------------------------------------------

  assign phy_rx_fire   = phy_rx_v_i       & phy_rx_ready_o;
  assign rd_issue_fire = m_axi_arvalid_o  & m_axi_arready_i;
  assign wr_aw_fire    = m_axi_awvalid_o  & m_axi_awready_i;
  assign wr_w_fire     = m_axi_wvalid_o   & m_axi_wready_i;
  assign rd_resp_fire  = m_axi_rvalid_i   & m_axi_rready_o;
  assign wr_resp_fire  = m_axi_bvalid_i   & m_axi_bready_o;

  // rd_final_resp_req fires on the LAST R beat of a burst (RLAST), not every beat.
  assign rd_final_resp_req = rd_resp_fire & m_axi_rlast_i;
  // wr_final_resp_req fires on every B (one B per burst, wr_out_fifo.last always 1).
  assign wr_final_resp_req = wr_resp_fire & wr_out_fifo_pop_data.last;

  assign rd_resp_final_count
    = rd_resp_collect_active_r ? (rd_resp_collect_count_r + 13'd1) : 13'd1;

  assign rd_resp_final_status
    = (rd_resp_collect_active_r && (rd_resp_collect_status_r != 2'b00))
      ? rd_resp_collect_status_r : m_axi_rresp_i;

  assign wr_resp_final_status
    = (wr_resp_collect_active_r && (wr_resp_collect_status_r != 2'b00))
      ? wr_resp_collect_status_r : m_axi_bresp_i;

  // For reads: need tx_resp space only on the final beat (RLAST).
  assign rd_resp_can_fire_base = rd_out_fifo_pop_v
                              && rd_data_fifo_push_ready
                              && (!m_axi_rlast_i || tx_resp_fifo_push_ready);

  assign wr_resp_can_fire_base = wr_out_fifo_pop_v
                              && (!wr_out_fifo_pop_data.last || tx_resp_fifo_push_ready);

  assign wr_force_priority = (wr_starvation_cnt_r >= wr_starvation_limit_p)
                          && m_axi_rvalid_i && rd_resp_can_fire_base
                          && m_axi_bvalid_i && wr_resp_can_fire_base;

  assign rd_resp_can_fire = rd_resp_can_fire_base && !wr_force_priority;
  assign wr_resp_can_fire = wr_resp_can_fire_base
                         && !(m_axi_rvalid_i && rd_resp_can_fire_base && !wr_force_priority);

  assign rx_local_resp_can_push = tx_resp_fifo_push_ready
                               && !rd_final_resp_req && !wr_final_resp_req;

  // --------------------------------------------------------------------------
  // Main combinational block
  // --------------------------------------------------------------------------

  always_comb begin
    rx_state_n               = rx_state_r;
    axi_state_n              = axi_state_r;
    tx_state_n               = tx_state_r;

    req_opcode_n             = req_opcode_r;
    req_payload_remaining_n  = req_payload_remaining_r;
    req_addr_n               = req_addr_r;
    is_first_data_n          = is_first_data_r;

    rd_issue_active_n        = rd_issue_active_r;
    rd_issue_addr_n          = rd_issue_addr_r;
    rd_issue_count_n         = rd_issue_count_r;

    wr_issue_addr_n          = wr_issue_addr_r;
    wr_issue_data_n          = wr_issue_data_r;
    wr_issue_awlen_n         = wr_issue_awlen_r;
    wr_issue_last_n          = wr_issue_last_r;
    aw_done_n                = aw_done_r;

    rd_resp_collect_active_n = rd_resp_collect_active_r;
    rd_resp_collect_count_n  = rd_resp_collect_count_r;
    rd_resp_collect_status_n = rd_resp_collect_status_r;

    wr_resp_collect_active_n = wr_resp_collect_active_r;
    wr_resp_collect_status_n = wr_resp_collect_status_r;

    tx_active_n              = tx_active_r;
    tx_data_remaining_n      = tx_data_remaining_r;
    wr_starvation_cnt_n      = wr_starvation_cnt_r;

    rd_req_fifo_push_v    = 1'b0; rd_req_fifo_push_data = '0; rd_req_fifo_pop_yumi  = 1'b0;
    wr_req_fifo_push_v    = 1'b0; wr_req_fifo_push_data = '0; wr_req_fifo_pop_yumi  = 1'b0;
    rd_out_fifo_push_v    = 1'b0; rd_out_fifo_push_data = '{last: 1'b0}; rd_out_fifo_pop_yumi = 1'b0;
    wr_out_fifo_push_v    = 1'b0; wr_out_fifo_push_data = '{last: 1'b0}; wr_out_fifo_pop_yumi = 1'b0;
    rd_data_fifo_push_v   = 1'b0; rd_data_fifo_push_data = '0;           rd_data_fifo_pop_yumi = 1'b0;
    tx_resp_fifo_push_v   = 1'b0; tx_resp_fifo_push_data = '0;           tx_resp_fifo_pop_yumi = 1'b0;

    rx_local_resp_push_v    = 1'b0; rx_local_resp_push_data = '0;
    rd_final_resp_push_v    = 1'b0; rd_final_resp_push_data = '0;
    wr_final_resp_push_v    = 1'b0; wr_final_resp_push_data = '0;

    phy_rx_ready_o   = 1'b0;
    phy_tx_v_o       = 1'b0;
    phy_tx_data_o    = '0;

    m_axi_araddr_o   = rd_issue_addr_r;
    m_axi_arlen_o    = 8'(rd_issue_count_r - 1);
    m_axi_arprot_o   = AXI_PROT_LP;
    m_axi_arvalid_o  = 1'b0;

    m_axi_awaddr_o   = wr_issue_addr_r;
    m_axi_awlen_o    = wr_issue_awlen_r;
    m_axi_awprot_o   = AXI_PROT_LP;
    m_axi_awvalid_o  = 1'b0;

    m_axi_wdata_o    = wr_issue_data_r;
    m_axi_wstrb_o    = AXI_WSTRB_ALL_LP;
    m_axi_wlast_o    = wr_issue_last_r;
    m_axi_wvalid_o   = 1'b0;

    m_axi_rready_o   = rd_resp_can_fire;
    m_axi_bready_o   = wr_resp_can_fire;

    // Starvation counter
    if (wr_resp_fire)
      wr_starvation_cnt_n = '0;
    else if (rd_resp_fire && m_axi_bvalid_i && wr_resp_can_fire_base)
      if (wr_starvation_cnt_r < wr_starvation_limit_p)
        wr_starvation_cnt_n = wr_starvation_cnt_r + 1'b1;

    // ------------------------------------------------------------------------
    // RX parser
    // ------------------------------------------------------------------------
    unique case (rx_state_r)
      RX_IDLE: begin
        phy_rx_ready_o = 1'b1;
        if (phy_rx_fire) begin
          req_opcode_n            = phy_rx_data_i[15:13];
          req_payload_remaining_n = phy_rx_data_i[12:0];
          req_addr_n              = '0;
          unique case (phy_rx_data_i[15:13])
            OP_AR: rx_state_n = (phy_rx_data_i[12:0] == AR_REQ_LEN_LP) ? RX_GET_ADDR
                              : ((phy_rx_data_i[12:0] == 13'd0)        ? RX_IDLE : RX_DROP);
            OP_AW: rx_state_n = (phy_rx_data_i[12:0] >= 13'd2)         ? RX_GET_ADDR
                              : ((phy_rx_data_i[12:0] == 13'd0)        ? RX_IDLE : RX_DROP);
            default: rx_state_n = (phy_rx_data_i[12:0] == 13'd0)       ? RX_IDLE : RX_DROP;
          endcase
        end
      end

      RX_GET_ADDR: begin
        phy_rx_ready_o = 1'b1;
        if (phy_rx_fire) begin
          req_addr_n              = phy_rx_data_i[axil_addr_width_p-1:0];
          req_payload_remaining_n = req_payload_remaining_r - 13'd1;
          is_first_data_n         = 1'b1;  // next flit is the first data flit
          if (req_opcode_r == OP_AR)
            rx_state_n = (req_payload_remaining_r == 13'd2) ? RX_GET_DATA
                       : ((req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP);
          else if (req_opcode_r == OP_AW)
            rx_state_n = (req_payload_remaining_r >= 13'd2) ? RX_GET_DATA
                       : ((req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP);
          else
            rx_state_n = (req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_DROP;
        end
      end

      RX_GET_DATA: begin
        if (req_opcode_r == OP_AR) begin
          if (req_payload_remaining_r == 13'd1) begin
            phy_rx_ready_o = ((phy_rx_data_i[12:0] == 13'd0)
                           || (phy_rx_data_i[12:0] > max_rd_count_lp))
                           ? rx_local_resp_can_push : rd_req_fifo_push_ready;
          end else
            phy_rx_ready_o = 1'b1;
        end else
          phy_rx_ready_o = wr_req_fifo_push_ready;

        if (phy_rx_fire) begin
          req_payload_remaining_n = req_payload_remaining_r - 13'd1;

          if (req_opcode_r == OP_AR) begin
            if (req_payload_remaining_r == 13'd1) begin
              if ((phy_rx_data_i[12:0] != 13'd0) && (phy_rx_data_i[12:0] <= max_rd_count_lp)) begin
                rd_req_fifo_push_v    = 1'b1;
                rd_req_fifo_push_data = '{addr: req_addr_r, count: phy_rx_data_i[12:0]};
              end else begin
                rx_local_resp_push_v    = 1'b1;
                rx_local_resp_push_data = '{opcode: OP_R, len: B_RESP_LEN_LP,
                                            status_flit: {14'b0, BAD_REQ_RESP_LP}, data_count: 13'd0};
              end
              rx_state_n = RX_IDLE;
            end else
              rx_state_n = RX_DROP;
          end else begin
            // AW data flit.
            // aw_len is the burst length N-1 where N = req_payload_remaining_r on the first flit.
            // On the first data flit, req_payload_remaining_r holds the original N (before decrement).
            wr_req_fifo_push_v    = 1'b1;
            wr_req_fifo_push_data = '{
              addr  : req_addr_r,
              data  : phy_rx_data_i[axil_data_width_p-1:0],
              aw_len: 8'(req_payload_remaining_r - 1),  // valid when first=1 (= N-1)
              first : is_first_data_r,
              last  : (req_payload_remaining_r == 13'd1)
            };
            is_first_data_n = 1'b0;
            rx_state_n = (req_payload_remaining_r == 13'd1) ? RX_IDLE : RX_GET_DATA;
          end
        end
      end

      RX_DROP: begin
        if (req_payload_remaining_r == 13'd0) begin
          rx_state_n     = RX_IDLE;
          phy_rx_ready_o = 1'b0;
        end else begin
          phy_rx_ready_o = 1'b1;
          if (phy_rx_fire) begin
            req_payload_remaining_n = req_payload_remaining_r - 13'd1;
            if (req_payload_remaining_r == 13'd1) rx_state_n = RX_IDLE;
          end
        end
      end

      default: rx_state_n = RX_IDLE;
    endcase

    // ------------------------------------------------------------------------
    // Read issue path
    // Issue one AR with ARLEN = count-1 (burst read).
    // One rd_out_fifo entry per AR (always last=1 since one AR = one packet).
    // ------------------------------------------------------------------------
    if (!rd_issue_active_r && rd_req_fifo_pop_v) begin
      rd_issue_active_n = 1'b1;
      rd_issue_addr_n   = rd_req_fifo_pop_data.addr;
      rd_issue_count_n  = rd_req_fifo_pop_data.count;
      rd_req_fifo_pop_yumi = 1'b1;
    end

    if (rd_issue_active_r && rd_out_fifo_push_ready) begin
      m_axi_araddr_o  = rd_issue_addr_r;
      m_axi_arlen_o   = 8'(rd_issue_count_r - 1);
      m_axi_arvalid_o = 1'b1;
    end

    if (rd_issue_fire) begin
      rd_out_fifo_push_v    = 1'b1;
      rd_out_fifo_push_data = '{last: 1'b1};  // always last; one AR per packet
      rd_issue_active_n     = 1'b0;           // AR complete in one shot
    end

    // ------------------------------------------------------------------------
    // Write issue path
    //   AXI_IDLE        : load first entry from wr_req_fifo
    //   AXI_WRITE_ACTIVE: drive AW (until aw_done) + W beat from issue registers
    //   AXI_NEXT_BEAT   : 1-cycle load of next W entry from wr_req_fifo
    // One AW per burst (AWLEN = wr_issue_awlen_r), N W beats, one wr_out_fifo push.
    // ------------------------------------------------------------------------
    unique case (axi_state_r)
      AXI_IDLE: begin
        aw_done_n = 1'b0;
        if (wr_req_fifo_pop_v && wr_out_fifo_push_ready) begin
          wr_issue_addr_n  = wr_req_fifo_pop_data.addr;
          wr_issue_data_n  = wr_req_fifo_pop_data.data;
          wr_issue_awlen_n = wr_req_fifo_pop_data.aw_len;
          wr_issue_last_n  = wr_req_fifo_pop_data.last;
          wr_req_fifo_pop_yumi = 1'b1;
          axi_state_n = AXI_WRITE_ACTIVE;
        end
      end

      AXI_WRITE_ACTIVE: begin
        // Drive AW until it handshakes (aw_done stays set for rest of burst).
        m_axi_awvalid_o = ~aw_done_r;
        m_axi_awlen_o   = wr_issue_awlen_r;
        if (wr_aw_fire) aw_done_n = 1'b1;

        // Drive current W beat.
        m_axi_wvalid_o = 1'b1;
        m_axi_wlast_o  = wr_issue_last_r;

        if (wr_w_fire) begin
          if (wr_issue_last_r) begin
            // Final beat — burst complete; push one entry to wr_out_fifo.
            wr_out_fifo_push_v    = 1'b1;
            wr_out_fifo_push_data = '{last: 1'b1};
            axi_state_n = AXI_IDLE;
          end else begin
            // More beats — move to load-next state.
            axi_state_n = AXI_NEXT_BEAT;
          end
        end
      end

      // 1-cycle bubble: pop next W entry from wr_req_fifo into issue registers.
      AXI_NEXT_BEAT: begin
        // Keep AW alive if it hasn't fired yet.
        m_axi_awvalid_o = ~aw_done_r;
        m_axi_awlen_o   = wr_issue_awlen_r;
        if (wr_aw_fire) aw_done_n = 1'b1;

        if (wr_req_fifo_pop_v) begin
          wr_issue_data_n      = wr_req_fifo_pop_data.data;
          wr_issue_last_n      = wr_req_fifo_pop_data.last;
          wr_req_fifo_pop_yumi = 1'b1;
          axi_state_n          = AXI_WRITE_ACTIVE;
        end
        // If fifo is empty (backpressure), stall in AXI_NEXT_BEAT.
      end

      default: axi_state_n = AXI_IDLE;
    endcase

    // ------------------------------------------------------------------------
    // Completion handling
    // ------------------------------------------------------------------------

    // Read: collect data on every R beat; emit OP_R and pop rd_out_fifo on RLAST.
    if (rd_resp_fire) begin
      rd_data_fifo_push_v    = 1'b1;
      rd_data_fifo_push_data = m_axi_rdata_i;

      if (!rd_resp_collect_active_r) begin
        rd_resp_collect_active_n = 1'b1;
        rd_resp_collect_count_n  = 13'd1;
        rd_resp_collect_status_n = m_axi_rresp_i;
      end else begin
        rd_resp_collect_count_n = rd_resp_collect_count_r + 13'd1;
        if ((rd_resp_collect_status_r == 2'b00) && (m_axi_rresp_i != 2'b00))
          rd_resp_collect_status_n = m_axi_rresp_i;
      end

      if (m_axi_rlast_i) begin
        // Final beat of read burst — emit one aggregated OP_R descriptor.
        rd_out_fifo_pop_yumi    = 1'b1;
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
    end else if (wr_resp_fire) begin
      // Write: one B per burst — emit one OP_B.
      wr_out_fifo_pop_yumi = 1'b1;

      if (!wr_resp_collect_active_r) begin
        wr_resp_collect_active_n = 1'b1;
        wr_resp_collect_status_n = m_axi_bresp_i;
      end else if ((wr_resp_collect_status_r == 2'b00) && (m_axi_bresp_i != 2'b00))
        wr_resp_collect_status_n = m_axi_bresp_i;

      if (wr_out_fifo_pop_data.last) begin
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

    // Arbitrate single push port: read final > write final > parser error.
    if (rd_final_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = rd_final_resp_push_data;
    end else if (wr_final_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = wr_final_resp_push_data;
    end else if (rx_local_resp_push_v) begin
      tx_resp_fifo_push_v    = 1'b1;
      tx_resp_fifo_push_data = rx_local_resp_push_data;
    end

    // ------------------------------------------------------------------------
    // TX packetizer
    // ------------------------------------------------------------------------
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
        if (phy_tx_ready_i) tx_state_n = TX_SEND_STATUS;
      end
      TX_SEND_STATUS: begin
        phy_tx_v_o    = 1'b1;
        phy_tx_data_o = tx_active_r.status_flit;
        if (phy_tx_ready_i) begin
          if (tx_active_r.data_count != 13'd0)
            tx_state_n = TX_SEND_DATA;
          else begin
            tx_resp_fifo_pop_yumi = 1'b1;
            tx_state_n            = TX_IDLE;
          end
        end
      end
      TX_SEND_DATA: begin
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
      default: tx_state_n = TX_IDLE;
    endcase
  end

  // --------------------------------------------------------------------------
  // Sequential update
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      rx_state_r               <= RX_IDLE;
      axi_state_r              <= AXI_IDLE;
      tx_state_r               <= TX_IDLE;
      req_opcode_r             <= '0;
      req_payload_remaining_r  <= '0;
      req_addr_r               <= '0;
      is_first_data_r          <= 1'b0;
      rd_issue_active_r        <= 1'b0;
      rd_issue_addr_r          <= '0;
      rd_issue_count_r         <= '0;
      wr_issue_addr_r          <= '0;
      wr_issue_data_r          <= '0;
      wr_issue_awlen_r         <= '0;
      wr_issue_last_r          <= 1'b0;
      aw_done_r                <= 1'b0;
      rd_resp_collect_active_r <= 1'b0;
      rd_resp_collect_count_r  <= '0;
      rd_resp_collect_status_r <= '0;
      wr_resp_collect_active_r <= 1'b0;
      wr_resp_collect_status_r <= '0;
      tx_active_r              <= '0;
      tx_data_remaining_r      <= '0;
      wr_starvation_cnt_r      <= '0;
    end else begin
      rx_state_r               <= rx_state_n;
      axi_state_r              <= axi_state_n;
      tx_state_r               <= tx_state_n;
      req_opcode_r             <= req_opcode_n;
      req_payload_remaining_r  <= req_payload_remaining_n;
      req_addr_r               <= req_addr_n;
      is_first_data_r          <= is_first_data_n;
      rd_issue_active_r        <= rd_issue_active_n;
      rd_issue_addr_r          <= rd_issue_addr_n;
      rd_issue_count_r         <= rd_issue_count_n;
      wr_issue_addr_r          <= wr_issue_addr_n;
      wr_issue_data_r          <= wr_issue_data_n;
      wr_issue_awlen_r         <= wr_issue_awlen_n;
      wr_issue_last_r          <= wr_issue_last_n;
      aw_done_r                <= aw_done_n;
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

endmodule : flit_axi4_bridge
