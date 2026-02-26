module next_active_thread_logic #(
    parameter int UNROLLING_INDEX = 0       // Index for unrolling lane (0-3)
)(
    input logic clk,
    input logic rst,
    input logic update,                     // Update signal to advance start position
    input logic [1:0] unrolling_factor,     // 0=1, 1=2, 2=4
    input logic [63:0] active_mask_lane,    // 64-bit active mask for this lane
    input logic restart,
    
    output logic [7:0] next_tid,            // Next active thread index (8 bits) - active_mask_index
    output logic valid,                      // Valid output signal - registered
    output logic done                     // Done signal to indicate completion of processing of this lane
);

    // Internal start position register with feedback
    logic [5:0] start_pos;
    
    // Priority encoder signals
    logic [5:0] encoded_pos;                // Encoded position from priority encoder
    logic [5:0] encoded_pos_rev;                // Encoded position from priority encoder in reverse order(get last active thread)
    logic pe_valid;                         // Valid from priority encoder
    logic rev_valid;                         // Valid from priority encoder reverse
    
    // Reverse mapper signals
    logic [7:0] active_mask_index;          // Index within 256-bit chunk
    logic rm_valid;                         // Valid from reverse mapper

    logic fifo_empty;                     // FIFO empty signal (not used in this module)
    logic fifo_full; // Reverse active mask for reverse priority encoding
    logic fifo_push;

    logic calculate_done;
    
    // Register start position with internal feedback
    always_ff @(posedge clk) begin
        if (rst) begin
            start_pos <= 6'b0;              // Reset to beginning of lane
        end else begin
            if(restart) begin
                start_pos <= 6'b0;          // Reset start position on restart
            end else if (!calculate_done && fifo_push) begin
                start_pos <= encoded_pos + 1'b1;  // Advance to next position when updated
            end
        end
    end

    //logic [6:0] active_count;
    //always_comb begin
    //    // Count active threads in the lane
    //    active_count = 7'b0;
    //    for(int i = 0; i < 64; i++) begin
    //        if(active_mask_lane[i]) begin
    //            active_count = active_count + 7'b1;
    //        end
    //    end
    //end

    logic [6:0] sent_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            sent_count <= 7'b0;              // Reset sent count
        end else if (restart) begin
            sent_count <= 7'b0;              // Reset sent count on restart
        end else if (fifo_push) begin
            sent_count <= sent_count + 7'b1;      // Update sent count based on active threads
        end
    end


    logic [5:0] last_active_thread;
    always_comb begin
        last_active_thread = 6'b111111-encoded_pos_rev;
    end

    logic calculate_done_reg;

    assign calculate_done = !rev_valid || (fifo_push && (encoded_pos == last_active_thread)) || calculate_done_reg;


    always_ff @(posedge clk) begin
        if (rst) begin
            calculate_done_reg <= 1'b0;      // Reset done register
        end else if (restart) begin
            calculate_done_reg <= 1'b0;      // Reset done register on restart
        end else begin
            calculate_done_reg <= calculate_done; // Update done register based on calculation
        end
    end

    assign done = calculate_done && fifo_empty; // Done when all active threads are sent to next stage

    priority_encoder_64bit pe64 (
        .data_in(active_mask_lane),
        .start_pos(start_pos),
        .encoded_out(encoded_pos),
        .valid(pe_valid)
    );

    // Reverse priority encoder instance
    logic [63:0] active_mask_lane_reverse;
    always_comb begin
        for (int i = 0; i < 64; i++) begin
            active_mask_lane_reverse[i] = active_mask_lane[63 - i]; // Reverse the active mask
        end
    end

    priority_encoder_64bit pe64_reverse (
        .data_in(active_mask_lane_reverse),
        .start_pos(6'b0),
        .encoded_out(encoded_pos_rev),
        .valid(rev_valid)
    );
    
    // Reverse mapper instance
    reverse_mapper #(
        .UNROLLING_INDEX(UNROLLING_INDEX)
    ) rm (
        .encoded_pos(encoded_pos),
        .unrolling_factor(unrolling_factor),
        .valid_in(pe_valid),
        .active_mask_index(active_mask_index),
        .valid_out(rm_valid)
    );



    assign fifo_push = !calculate_done_reg && rm_valid && ~fifo_full; // Push to FIFO when reverse mapper is

    sync_fifo_read_unreg #(
        .DATA_WIDTH(8),
        .DEPTH(2)
    ) next_tid_fifo (
        .clk(clk),
        .rst(rst),
        .push(fifo_push),
        .push_data(active_mask_index),
        .pop(update), // Always pop the data
        .pop_data(next_tid),
        .pop_data_valid(valid),
        .empty(fifo_empty), // Not used
        .full(fifo_full),  // Not used
        .count() // Not used
    );

endmodule