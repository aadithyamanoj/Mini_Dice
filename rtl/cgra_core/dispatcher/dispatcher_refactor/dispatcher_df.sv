module dispatcher_dataflow
    import dice_pkg::*, 
           dice_frontend_pkg::*;
(
    // Output Data
    output logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] latched_active_mask,
    output logic [REG_NUM-1:0] latched_input_regs,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE+1)-1:0] dispatched_count,
    output logic [1:0] latched_unrolling_factor,
    output logic [1:0] latched_cta_size,
    output logic [1:0] chunk_counter,
    output logic last_chunk_done,
    output logic restart,
    
    // Input Data
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,
    input logic [REG_NUM-1:0] input_register_bitmap,
    input logic [1:0] unrolling_factor,
    input cta_size_e cta_size,                 // 0=256, 1=512, 3=1024
    input logic dispatch_valid_0, dispatch_valid_1,
                dispatch_valid_2, dispatch_valid_3,
    input logic [1:0] max_chunks,

    // Control Signals
    input logic latch_inputs,
    input logic update_count,
    input logic deassert_restart,
    input logic incr_counter,
    input logic rst_counter, 
    input logic assert_restart, 
    input logic last_chunk_fin,
    input logic start_new_cta,
    input logic clk, rst
);

    always_ff @(posedge clk) begin
        if (rst) begin
            latched_unrolling_factor <= 2'b0;
            latched_input_regs <= '0;
            latched_active_mask <= '0;
            latched_cta_size <= 2'b0;
            dispatched_count <= '0;
            chunk_counter <= '0;
            last_chunk_done <= 1'b0;
            restart <= 1'b0;
        end

        if (latch_inputs) begin
            latched_unrolling_factor <= unrolling_factor;
            latched_input_regs <= input_register_bitmap;
            latched_active_mask <= active_mask;
            latched_cta_size <= cta_size;
            dispatched_count <= '0;
            chunk_counter <= '0;
            restart <= 1'b1;
        end

        if (update_count) begin
            dispatched_count <= dispatched_count + (dispatch_valid_0 + dispatch_valid_1 + 
                                          dispatch_valid_2 + dispatch_valid_3);
        end

        if (deassert_restart) begin
            restart <= 1'b0;
        end

        if (incr_counter) begin
            chunk_counter <= chunk_counter + 2'b01;
        end

        if (assert_restart) begin
            restart <= 1'b1;
        end

        if (rst_counter) begin
            chunk_counter <= max_chunks;
        end

        if (last_chunk_fin) begin
            last_chunk_done <= 1'b1;
        end

        if (start_new_cta) begin
            latched_unrolling_factor <= unrolling_factor;
            latched_input_regs <= input_register_bitmap;
            latched_active_mask <= active_mask;
            latched_cta_size <= cta_size;
            dispatched_count <= '0;
            chunk_counter <= '0;
            last_chunk_done <= 1'b0;
            restart <= 1'b1;
        end
    end
endmodule