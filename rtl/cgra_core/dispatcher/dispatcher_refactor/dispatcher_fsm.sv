`include "dice_define.vh"

module dispatcher_fsm
    import dice_pkg::*,
           dice_frontend_pkg::*;
#(
    parameter int CHUNK_SIZE = 256,
    parameter int CHUNK_ADDR_WIDTH = 2
)(
    output logic [CHUNK_SIZE-1:0] current_chunk, // CHUNK_SIZE
    output logic [`DICE_GPR_NUM-1:0] gpr_bitmap, // Need metadata parameter for gpr_bitmap width
    output logic [`DICE_CR_NUM-1:0] const_bitmap, // Need metadata parameter for const_bitmap width
    output logic [`DICE_PR_NUM-1:0] pred_bitmap, // Need metadata parameter for pred_bitmap width
    output logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr, // CHUNK_ADDR_WIDTH
    output logic [1:0] latched_unrolling_factor,
    output logic start_new_cta,
    output logic dispatcher_busy,
    output logic dispatcher_done,
    output logic restart,

    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask, // DICE_NUM_MAX_THREADS_PER_CORE
    input logic [REG_NUM-1:0] input_register_bitmap, 
    input logic [1:0] unrolling_factor,
    input cta_size_e cta_size, // 0=256, 1=512, 3=1024
    input logic dispatch_valid_0,
    input logic dispatch_valid_1,
    input logic dispatch_valid_2,
    input logic dispatch_valid_3,
    input logic fetch_done,
    input logic thread_chunk_done,
    input logic dispatch_fifo_empty,
    input logic clk, rst
);
    // Intermediate logic
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] latched_active_mask;
    logic [REG_NUM-1:0] latched_input_regs;
    logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE+1)-1:0] dispatched_count;
    logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE+1)-1:0] cta_total_size;
    logic [1:0] latched_cta_size;
    logic [1:0] chunk_counter;
    logic last_chunk_done;
    logic latch_inputs,
          update_count,
          deassert_restart,
          incr_counter,
          rst_counter, 
          assert_restart, 
          last_chunk_fin; // Control signals

    // Calculate total CTA size
    always_comb begin
        case (latched_cta_size)
            2'b00: cta_total_size = 10'd256;
            2'b01: cta_total_size = 10'd512;
            2'b11: cta_total_size = 10'd1023;  // Fix: 1024 doesn't fit in 10 bits
            default: cta_total_size = 10'd256;
        endcase
    end

    // Calculate maximum chunks needed
    logic [1:0] max_chunks;
    always_comb begin
        case (latched_cta_size)
            2'b00: max_chunks = 2'b00;        // 1 chunk (0)
            2'b01: max_chunks = 2'b01;        // 2 chunks (0-1)
            2'b11: max_chunks = 2'b11;        // 4 chunks (0-3)
            default: max_chunks = 2'b00;
        endcase
    end

    // Chunk selection
    always_comb begin
        chunk_base_addr = chunk_counter;
        
        case (chunk_counter)
            2'b00: current_chunk = latched_active_mask[1*CHUNK_SIZE-1:0*CHUNK_SIZE];  // Chunk 0
            2'b01: current_chunk = latched_active_mask[2*CHUNK_SIZE-1:1*CHUNK_SIZE];  // Chunk 1
            2'b10: current_chunk = latched_active_mask[3*CHUNK_SIZE-1:2*CHUNK_SIZE];  // Chunk 2
            2'b11: current_chunk = latched_active_mask[4*CHUNK_SIZE-1:3*CHUNK_SIZE];  // Chunk 3
        endcase
    end

    // Extract register bitmaps from latched input
    assign gpr_bitmap   = latched_input_regs[`DICE_GPR_NUM-1:0];      // GPR (bits 0-31)
    assign const_bitmap = latched_input_regs[(`DICE_GPR_NUM+`DICE_CR_NUM)-1:`DICE_GPR_NUM];   // Constants (bits 32-63)
    assign pred_bitmap  = latched_input_regs[(`DICE_GPR_NUM+`DICE_CR_NUM+`DICE_PR_NUM)-1:`DICE_GPR_NUM+`DICE_CR_NUM];    // Predicates (bits 64-65)

    dispatcher_dataflow dispatcher_df_inst (
        .latched_active_mask(latched_active_mask),
        .latched_input_regs(latched_input_regs),
        .dispatched_count(dispatched_count),
        .latched_unrolling_factor(latched_unrolling_factor),
        .latched_cta_size(latched_cta_size),
        .chunk_counter(chunk_counter),
        .last_chunk_done(last_chunk_done),
        .restart(restart),

        .active_mask(active_mask),
        .input_register_bitmap(input_register_bitmap),
        .unrolling_factor(unrolling_factor),
        .cta_size(cta_size),
        .dispatch_valid_0(dispatch_valid_0),
        .dispatch_valid_1(dispatch_valid_1),
        .dispatch_valid_2(dispatch_valid_2),
        .dispatch_valid_3(dispatch_valid_3),
        .max_chunks(max_chunks),
        
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
        .chunk_counter(chunk_counter),
        .max_chunks(max_chunks),
        .clk(clk),
        .rst(rst)
    );

endmodule