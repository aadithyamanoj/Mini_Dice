module dispatcher_dataflow
    import dice_pkg::*,
           dice_frontend_pkg::*,
           DE_pkg::*;  // CHUNK_ADDR_WIDTH from DE_pkg
(
    // Output Data
    output logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] latched_active_mask,
    output logic [REG_NUM-1:0] latched_input_regs,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE+1)-1:0] dispatched_count,
    output logic [CHUNK_ADDR_WIDTH-1:0] chunk_counter,
    output logic last_chunk_done,
    output logic restart,

    // Input Data
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,
    input logic [REG_NUM-1:0] input_register_bitmap,
    input logic dispatch_valid_0,

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
    // NUM_SCOREBOARDS=1, CHUNK_SIZE=16 => max_chunks=0 always.
    // chunk_counter stays at 0; incr_counter/rst_counter are effectively dead.

    always_ff @(posedge clk) begin
        if (rst) begin
            latched_input_regs <= '0;
            latched_active_mask <= '0;
            dispatched_count <= '0;
            chunk_counter <= '0;
            last_chunk_done <= 1'b0;
            restart <= 1'b0;
        end

        if (latch_inputs) begin
            latched_input_regs <= input_register_bitmap;
            latched_active_mask <= active_mask;
            dispatched_count <= '0;
            chunk_counter <= '0;
            restart <= 1'b1;
        end

        if (update_count) begin
            dispatched_count <= dispatched_count + dispatch_valid_0;
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
            chunk_counter <= '0;  // max_chunks is always 0
        end

        if (last_chunk_fin) begin
            last_chunk_done <= 1'b1;
        end

        if (start_new_cta) begin
            latched_input_regs <= input_register_bitmap;
            latched_active_mask <= active_mask;
            dispatched_count <= '0;
            chunk_counter <= '0;
            last_chunk_done <= 1'b0;
            restart <= 1'b1;
        end
    end
endmodule
