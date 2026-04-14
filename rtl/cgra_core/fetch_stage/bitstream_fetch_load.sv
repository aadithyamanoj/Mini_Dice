// NO OPTION TO STOP IN PROGRESS LOAD

module bitstream_fetch_load
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Flush signal (cancels in-progress load)
    input logic flush_i,

    //from decoder
    input logic                       meta_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0] bitstream_addr_i,

    // Direct write interface to configuration memory DFFs
    output logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_o,
    output logic [AxiDataWidth-1:0]           cm_wr_data_o,
    output logic                              cm_wr_valid_o,

    //to valid checker
    output logic done_streaming_o,

    // AXI4 read master → crossbar slave port
    output slv_req_t  bs_req_o,
    input  slv_resp_t bs_resp_i,

    //to FDR EX buffer
    output logic cm_num_o
);

  localparam int CmAddrWidth = $clog2(DICE_BITSTREAM_SIZE);
  localparam int BeatCount   = (DICE_BITSTREAM_SIZE + AxiDataWidth - 1) / AxiDataWidth;
  localparam int BurstLen    = BeatCount - 1;

  typedef enum logic [1:0] {
    StateIdle,
    StateStreaming,  // Handles both Request and Response phases
    StateDone
  } bitstream_fetch_state_e;

  bitstream_fetch_state_e state_q, state_d;

  // registered states
  logic [DICE_ADDR_WIDTH-1:0] cm0_addr_q, cm1_addr_q, cm0_addr_d, cm1_addr_d;
  logic cm_select_q, cm_select_d;  // 0 = cm0, 1 = cm1

  logic [DICE_ADDR_WIDTH-1:0] addr_q, addr_d;
  logic cm0_valid_d, cm1_valid_d, cm0_valid_q, cm1_valid_q;
  logic [CmAddrWidth-1:0] cm_wr_addr_q, cm_wr_addr_d;

  // AR transaction has been accepted; R phase is now active
  logic ar_sent_q, ar_sent_d;

  // Byte address alias for done_streaming_o comparison
  logic [DICE_ADDR_WIDTH-1:0] bitstream_addr_dec;
  assign bitstream_addr_dec = bitstream_addr_i;

  // AXI handshake pulses
  logic ar_fire;
  logic r_fire;
  assign ar_fire = bs_req_o.ar_valid && bs_resp_i.ar_ready;
  assign r_fire  = bs_resp_i.r_valid && bs_req_o.r_ready;

  logic cm0_hit, cm1_hit;
  assign cm0_hit = cm0_valid_q && (cm0_addr_q == bitstream_addr_dec);
  assign cm1_hit = cm1_valid_q && (cm1_addr_q == bitstream_addr_dec);
  assign done_streaming_o = cm0_hit || cm1_hit;

  always_comb begin
    state_d       = state_q;
    cm_select_d   = cm_select_q;
    cm0_addr_d    = cm0_addr_q;
    cm1_addr_d    = cm1_addr_q;
    addr_d        = addr_q;
    cm0_valid_d   = cm0_valid_q;
    cm1_valid_d   = cm1_valid_q;
    ar_sent_d     = ar_sent_q;
    cm_wr_addr_d  = cm_wr_addr_q;
    cm_wr_addr_o  = cm_wr_addr_q;
    cm_wr_data_o  = bs_resp_i.r.data;
    cm_wr_valid_o = 1'b0;

    unique case (state_q)
      StateIdle: begin
        ar_sent_d   = 1'b0;
        if (meta_valid_i) begin
          if (!done_streaming_o) begin
            if (cm0_valid_q || cm1_valid_q) cm_select_d = ~cm_select_q;
            else cm_select_d = 1'b0;

            addr_d       = bitstream_addr_i;
            state_d      = StateStreaming;
            cm_wr_addr_d = '0;

            if (cm_select_d == 1'b0) begin
              cm0_addr_d  = bitstream_addr_dec;
              cm0_valid_d = 1'b0;
            end else begin
              cm1_addr_d  = bitstream_addr_dec;
              cm1_valid_d = 1'b0;
            end
          end
        end
      end

      StateStreaming: begin
        if (flush_i) begin
          state_d      = StateIdle;
          ar_sent_d    = 1'b0;
          cm_wr_addr_d = '0;
        end else if (!ar_sent_q) begin
          // AR phase: assert ar_valid until ar_ready
          if (ar_fire) begin
            ar_sent_d = 1'b1;
          end
        end else begin
          if (r_fire) begin
            cm_wr_valid_o = 1'b1;
            cm_wr_addr_o  = cm_wr_addr_q;
            cm_wr_addr_d  = cm_wr_addr_q + CmAddrWidth'(AxiDataWidth);

            if (bs_resp_i.r.last) begin
              state_d   = StateDone;
              ar_sent_d = 1'b0;
            end
          end
        end
      end

      StateDone: begin
        state_d = StateIdle;
        if (cm_select_q == 1'b1) begin
          cm1_valid_d = 1'b1;
        end else begin
          cm0_valid_d = 1'b1;
        end
      end

      default: state_d = StateIdle;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q       <= StateIdle;
      cm_select_q   <= 1'b0;
      cm0_addr_q    <= '0;
      cm1_addr_q    <= '0;
      addr_q        <= '0;
      cm0_valid_q   <= 1'b0;
      cm1_valid_q   <= 1'b0;
      cm_wr_addr_q  <= '0;
      ar_sent_q     <= 1'b0;
    end else begin
      state_q       <= state_d;
      cm0_addr_q    <= cm0_addr_d;
      cm1_addr_q    <= cm1_addr_d;
      cm_select_q   <= cm_select_d;
      addr_q        <= addr_d;
      cm0_valid_q   <= cm0_valid_d;
      cm1_valid_q   <= cm1_valid_d;
      cm_wr_addr_q  <= cm_wr_addr_d;
      ar_sent_q     <= ar_sent_d;
    end
  end

  // AR channel: driven fields
  assign bs_req_o.ar_valid  = (state_q == StateStreaming) && !ar_sent_q && !flush_i;
  assign bs_req_o.ar.addr   = addr_q;
  assign bs_req_o.ar.len    = 8'(BurstLen);
  assign bs_req_o.ar.size   = 3'b001;  // 2 bytes per beat
  assign bs_req_o.ar.burst  = 2'b01;   // INCR
  assign bs_req_o.ar.id     = '0;
  assign bs_req_o.ar.lock   = '0;
  assign bs_req_o.ar.cache  = '0;
  assign bs_req_o.ar.prot   = '0;
  assign bs_req_o.ar.qos    = '0;
  assign bs_req_o.ar.region = '0;
  assign bs_req_o.ar.user   = '0;

  // R channel: accept data in StateStreaming after AR has fired
  assign bs_req_o.r_ready   = (state_q == StateStreaming) && ar_sent_q;

  // Write channels tied off (read-only master)
  always_comb begin
    bs_req_o.aw       = '0;
    bs_req_o.aw_valid = 1'b0;
    bs_req_o.w        = '0;
    bs_req_o.w_valid  = 1'b0;
    bs_req_o.b_ready  = 1'b1;
  end

  assign cm_num_o = cm0_hit ? 1'b0 : (cm1_hit ? 1'b1 : cm_select_q);

endmodule
