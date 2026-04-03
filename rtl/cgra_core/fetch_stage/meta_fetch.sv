module meta_fetch
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // From CS/FDR barrier
    input logic                       schedule_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0] fdr_next_pc_i,
    output logic                      schedule_ready_o,

    // AXI4 read master → crossbar slave port
    output slv_req_t  meta_req_o,
    input  slv_resp_t meta_resp_i,

    // To decoder
    output pgraph_meta_t outgoing_meta_o,
    output logic         meta_valid_o,

    // From stage barrier
    input logic fire_eblock_i,

    // Flush signal (from valid_check misprediction)
    input logic flush_i
);



  // FSM states
  typedef enum logic [1:0] {
    StateReady    = 2'b00,  // fetcher is ready for a new pc
    StateReqVal   = 2'b01,
    StateWaitResp = 2'b10,  // waiting for response from cache
    StateHoldData = 2'b11   // waits for decoder to consume meta
  } meta_fetch_state_e;

  meta_fetch_state_e state_q, state_d;
  logic meta_valid_q;
  logic flushed_q;  // Track if flushed, cleared on new schedule
  pgraph_meta_t outgoing_meta_q;

  // 256-bit assembly buffer: 16 × 16-bit beats accumulated here
  // First received beat ends up in bits [255:240] after all 16 beats
  logic [MetaBits-1:0] meta_buf_q;

  // AXI handshake pulses
  logic ar_fire;
  logic r_fire;

  assign ar_fire = meta_req_o.ar_valid && meta_resp_i.ar_ready;
  assign r_fire  = meta_resp_i.r_valid && meta_req_o.r_ready;

  always_comb begin
    schedule_ready_o = 1'b0;
    state_d          = state_q;

    unique case (state_q)
      StateReady: begin
        schedule_ready_o = 1'b1;
        if (schedule_valid_i) begin
          state_d = StateReqVal;
        end
      end
      StateReqVal: begin
        if (flush_i) state_d = StateReady;
        else if (ar_fire) state_d = StateWaitResp;
      end
      StateWaitResp: begin
        if (flush_i) state_d = StateReady;
        else if (r_fire && meta_resp_i.r.last) state_d = StateHoldData;
      end
      StateHoldData: begin
        if (flush_i) state_d = StateReady;
        else if (fire_eblock_i) state_d = StateReady;
      end
      default: state_d = StateReady;
    endcase
  end


  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q         <= StateReady;
      meta_valid_q    <= 1'b0;
      flushed_q       <= 1'b0;
      outgoing_meta_q <= '0;
      meta_buf_q      <= '0;
    end else begin
      state_q <= state_d;

      if (flush_i) begin
        flushed_q    <= 1'b1;
        meta_valid_q <= 1'b0;
      end

      if (state_q == StateReady && schedule_valid_i && schedule_ready_o) begin
        flushed_q  <= 1'b0;
        meta_buf_q <= '0;
      end

      // Accumulate 16-bit beats: shift new word into MSB, pushing earlier words down
      if (r_fire) begin
        meta_buf_q <= {meta_resp_i.r.data, meta_buf_q[MetaBits-1:16]};
      end

      if (r_fire && meta_resp_i.r.last) begin
        outgoing_meta_q <= pgraph_meta_t'({meta_resp_i.r.data, meta_buf_q[MetaBits-1:16]});
        meta_valid_q    <= 1'b1;
      end

      if (fire_eblock_i) begin
        meta_valid_q <= 1'b0;
      end
    end
  end

  // AR channel: driven fields
  assign meta_req_o.ar_valid  = (state_q == StateReqVal) && !flush_i;
  assign meta_req_o.ar.addr   = fdr_next_pc_i;
  assign meta_req_o.ar.len    = (DICE_METADATA_WIDTH / 16) - 1;
  assign meta_req_o.ar.size   = 3'b001;  // 2 bytes per beat
  assign meta_req_o.ar.burst  = 2'b01;   // INCR
  assign meta_req_o.ar.id     = '0;
  assign meta_req_o.ar.lock   = '0;
  assign meta_req_o.ar.cache  = '0;
  assign meta_req_o.ar.prot   = '0;
  assign meta_req_o.ar.qos    = '0;
  assign meta_req_o.ar.region = '0;
  assign meta_req_o.ar.user   = '0;

  // R channel: accept data in StateWaitResp
  assign meta_req_o.r_ready   = (state_q == StateWaitResp);

  // Write channels tied off (read-only master)
  always_comb begin
    meta_req_o.aw       = '0;
    meta_req_o.aw_valid = 1'b0;
    meta_req_o.w        = '0;
    meta_req_o.w_valid  = 1'b0;
    meta_req_o.b_ready  = 1'b1;
  end

  assign meta_valid_o    = meta_valid_q && !flushed_q;
  assign outgoing_meta_o = outgoing_meta_q;

endmodule
