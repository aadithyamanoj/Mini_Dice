module dispatcher_fsm
    import dice_pkg::*,
           dice_frontend_pkg::*,
           DE_pkg::*;  // CHUNK_SIZE, CHUNK_ADDR_WIDTH, NUM_SCOREBOARDS from DE_pkg
(
    output logic [CHUNK_SIZE-1:0] current_chunk,
    output logic [DICE_NUM_REGS-1:0] gpr_bitmap,
    output logic [DICE_NUM_CONST-1:0] const_bitmap,
    output logic [DICE_NUM_PRED-1:0] pred_bitmap,
    output logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr,
    output logic start_new_cta,
    output logic dispatcher_busy,
    output logic dispatcher_done,
    output logic restart,

    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,
    input logic [REG_NUM-1:0] input_register_bitmap,
    input logic dispatch_valid_0,
    input logic fetch_done,
    input logic thread_chunk_done,
    input logic dispatch_fifo_empty,
    input logic dispatch_pipeline_idle,
    input logic clk, rst
);
    // Intermediate logic
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] latched_active_mask;
    logic [REG_NUM-1:0] latched_input_regs;
    logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE+1)-1:0] dispatched_count;
    logic [CHUNK_ADDR_WIDTH-1:0] chunk_counter;
    logic last_chunk_done;
    logic latch_inputs,
          update_count,
          deassert_restart,
          incr_counter,
          rst_counter,
          assert_restart,
          last_chunk_fin; // Control signals

    // NUM_SCOREBOARDS=1 and CHUNK_SIZE=DICE_NUM_MAX_THREADS_PER_CORE=16 =>
    // max_chunks = (16/16) - 1 = 0 always. Only one chunk ever processed.
    localparam logic [CHUNK_ADDR_WIDTH-1:0] MAX_CHUNKS = '0;

    // Chunk selection — with one chunk, always select chunk 0
    always_comb begin
        chunk_base_addr = chunk_counter;
        current_chunk   = latched_active_mask[CHUNK_SIZE-1:0];
    end

    // Extract register bitmaps from latched input
    assign gpr_bitmap   = latched_input_regs[DICE_NUM_REGS-1:0];
    assign const_bitmap = latched_input_regs[(DICE_NUM_REGS+DICE_NUM_CONST)-1:DICE_NUM_REGS];
    assign pred_bitmap  = latched_input_regs[(DICE_NUM_REGS+DICE_NUM_CONST+DICE_NUM_PRED)-1:DICE_NUM_REGS+DICE_NUM_CONST];

    dispatcher_dataflow dispatcher_df_inst (
        .latched_active_mask(latched_active_mask),
        .latched_input_regs(latched_input_regs),
        .dispatched_count(dispatched_count),
        .chunk_counter(chunk_counter),
        .last_chunk_done(last_chunk_done),
        .restart(restart),

        .active_mask(active_mask),
        .input_register_bitmap(input_register_bitmap),
        .dispatch_valid_0(dispatch_valid_0),

        .latch_inputs(latch_inputs),
        .update_count(update_count),
        .deassert_restart(deassert_restart),
        .incr_counter(incr_counter),
        .rst_counter(rst_counter),
        .assert_restart(assert_restart),
        .last_chunk_fin(last_chunk_fin),
        .start_new_cta(start_new_cta),
        .clk(clk),
        .rst(rst)
    );

    dispatcher_control dispatcher_ctrl_inst (
        .latch_inputs(latch_inputs),
        .update_count(update_count),
        .deassert_restart(deassert_restart),
        .incr_counter(incr_counter),
        .rst_counter(rst_counter),
        .assert_restart(assert_restart),
        .last_chunk_fin(last_chunk_fin),
        .start_new_cta(start_new_cta),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done),

        .fetch_done(fetch_done),
        .thread_chunk_done(thread_chunk_done),
        .last_chunk_done(last_chunk_done),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .dispatch_pipeline_idle(dispatch_pipeline_idle),
        .dispatched_count_nonzero(|dispatched_count),
        .chunk_counter(chunk_counter),
        .max_chunks(MAX_CHUNKS),
        .clk(clk),
        .rst(rst)
    );

endmodule
