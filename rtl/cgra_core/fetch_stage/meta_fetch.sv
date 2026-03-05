// MAY NEED TO STALL THE READY SIGNAL FOR ~3 CYCLES TO PREVENT
// RACE CONDITION IN THE CTA STATUS TABLE UNRESOLVED CONTROL DIVERGENCE
// BIT WHICH DETERMINES IF THE NEXT EBLOCK IS A PREFETCHED ONE



// NEED TO CHANGE IT SO THAT THE FDR STAGE IS READY ONCE THE BRANCH HANDLER IS DONE TOO (MEANS THAT THE FIRE SIGNAL
// ISN'T WHAT CONTROLS THE READY SIGNAL)


module meta_fetch
  import dice_pkg::*;
  import dice_frontend_pkg::*;
#(
    // TAG_WIDTH kept for interface parameterization compatibility
    parameter int TAG_WIDTH = DICE_ADDR_WIDTH
) (
    input logic clk_i,
    input logic rst_i,

    // From CS/FDR barrier
    input logic                       schedule_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0] fdr_next_pc_i,
    output logic                      schedule_ready_o,

    // Request channel to cache
    VX_mem_bus_if.master meta_fetch_bus_if,

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

  // fdr_next_pc_i is already registered in fdr_top (schedule_data_q), so use directly
  localparam int BusDataBytes = DICE_MEM_DATA_WIDTH / 8;
  localparam int AddrShift = $clog2(BusDataBytes);
  localparam int BusAddrWidth = DICE_MEM_ADDR_WIDTH - $clog2(BusDataBytes);
  logic [BusAddrWidth-1:0] meta_cache_req_addr;
  assign meta_cache_req_addr = BusAddrWidth'(fdr_next_pc_i >> AddrShift);
  // 4-byte aligned addresses

  logic rsp_fire, req_fire;
  logic rsp_tag_match;

  // Check if response tag matches expected PC (lower bits of tag contain PC)
  assign rsp_tag_match = (meta_fetch_bus_if.rsp_data.tag.uuid[DICE_ADDR_WIDTH-1:0] == fdr_next_pc_i);
  assign rsp_fire = meta_fetch_bus_if.rsp_valid && meta_fetch_bus_if.rsp_ready && rsp_tag_match;
  assign req_fire = meta_fetch_bus_if.req_valid && meta_fetch_bus_if.req_ready;

  always_comb begin
    // Default assignments at top of always_comb
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
        else if (req_fire) state_d = StateWaitResp;
      end
      StateWaitResp: begin
        if (flush_i) state_d = StateReady;
        else if (rsp_fire) state_d = StateHoldData;
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
      state_q               <= StateReady;
      meta_valid_q          <= 1'b0;
      flushed_q             <= 1'b0;
      outgoing_meta_q       <= '0;
    end else begin
      state_q <= state_d;

      // Set flushed flag on flush, clear on new schedule acceptance
      if (flush_i) begin
        flushed_q    <= 1'b1;
        meta_valid_q <= 1'b0;  // Invalidate held data
      end

      if (state_q == StateReady && schedule_valid_i && schedule_ready_o) begin
        flushed_q             <= 1'b0;  // Clear flush flag on new schedule
      end
      if (rsp_fire) begin
        outgoing_meta_q <= pgraph_meta_t'(meta_fetch_bus_if.rsp_data.data);
        meta_valid_q    <= 1'b1;
      end
      if (fire_eblock_i) begin
        meta_valid_q <= 1'b0;
      end
    end
  end


  //============= UNUSED VORTEX CACHE FEATURES =================//
  assign meta_fetch_bus_if.req_data.flags  = '0;  //misc / not used
  assign meta_fetch_bus_if.req_data.rw     = 0;   //read/write bit
  assign meta_fetch_bus_if.req_data.byteen = '1;  //byte mask (for stores)
  assign meta_fetch_bus_if.req_data.data   = '0;  //write payload

  // Use pre-registered PC as tag for request/response matching
  // (fdr_next_pc_i is already registered in fdr_top via schedule_data_q)
  assign meta_fetch_bus_if.req_data.tag.uuid = TAG_WIDTH'(fdr_next_pc_i);

  assign meta_fetch_bus_if.req_data.addr   = meta_cache_req_addr;
  assign meta_fetch_bus_if.req_valid       = (state_q == StateReqVal);
  // Accept any response while waiting, but only rsp_fire (with tag match) triggers state transition
  assign meta_fetch_bus_if.rsp_ready       = (state_q == StateWaitResp);
  assign meta_valid_o                      = meta_valid_q && !flushed_q;
  assign outgoing_meta_o                   = outgoing_meta_q;
endmodule
