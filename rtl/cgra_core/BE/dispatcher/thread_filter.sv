module thread_filter
    import dice_pkg::*,
           DE_pkg::*;
(
    input logic clk,
    input logic rst,

    // Inputs from thread_lane_reroute: {compare_tid, real_tid}
    input logic [2*DICE_TID_WIDTH-1:0] next_tid_0,
    input logic valid_0,

    // FIFO pop interface
    input logic fifo_pop,                   // Single pop signal for all FIFOs

    // Outputs to next_thread_logic_top
    output logic [NUM_LANES-1:0] update,    // Update signals for each lane

    // FIFO outputs: {valid, real_tid}
    output logic [DICE_TID_WIDTH:0] fifo_data_0,
    output logic fifo_data_valid,
    output logic fifo_empty,                // 1 if ALL FIFOs are empty
    output logic fifo_full                  // 1 if ANY FIFO is full
);

    // FIFO control signals
    logic [NUM_LANES-1:0]       fifo_push;
    logic [DICE_TID_WIDTH:0]    fifo_push_data [NUM_LANES];
    logic [NUM_LANES-1:0]       fifo_full_individual;
    logic [NUM_LANES-1:0]       fifo_empty_individual;
    logic [NUM_LANES-1:0]       fifo_pop_individual;
    logic [DICE_TID_WIDTH:0]    fifo_data [NUM_LANES];
    logic [2:0]                 fifo_count [NUM_LANES];

    // Unpack real_tid (lower half) and compare_tid (upper half) from input
    logic [DICE_TID_WIDTH-1:0] next_tid         [NUM_LANES];
    logic [DICE_TID_WIDTH-1:0] next_tid_compare [NUM_LANES];

    assign next_tid[0]         = next_tid_0[DICE_TID_WIDTH-1:0];
    assign next_tid_compare[0] = next_tid_0[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];

    // Generate selective pop signals — only pop from non-empty FIFOs
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            fifo_pop_individual[i] = fifo_pop && !fifo_empty_individual[i];
        end
    end

    assign fifo_full  = |fifo_full_individual;   // ANY FIFO full
    assign fifo_empty = &fifo_empty_individual;  // ALL FIFOs empty

    // Dispatch logic: single lane, push when valid and FIFO has space
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            fifo_push[i]      = 1'b0;
            fifo_push_data[i] = {(DICE_TID_WIDTH+1){1'b0}};
            update[i]         = 1'b0;
        end

        if (valid_0 && !fifo_full_individual[0]) begin
            fifo_push[0]      = 1'b1;
            fifo_push_data[0] = {1'b1, next_tid[0]};
            update[0]         = 1'b1;
        end
    end

    // Generate NUM_LANES sync_fifo instances
    logic [NUM_LANES-1:0] sync_fifo_data_valid;
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_fifos
            sync_fifo #(
                .DATA_WIDTH(DICE_TID_WIDTH+1),  // {valid[MSB], tid[DICE_TID_WIDTH-1:0]}
                .DEPTH(4)
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                .push(fifo_push[i]),
                .push_data(fifo_push_data[i]),
                .pop(fifo_pop_individual[i]),
                .pop_data(fifo_data[i]),
                .pop_data_valid(sync_fifo_data_valid[i]),
                .empty(fifo_empty_individual[i]),
                .full(fifo_full_individual[i]),
                .count(fifo_count[i])
            );
        end
    endgenerate

    // Output assignments
    assign fifo_data_0    = fifo_data[0];
    assign fifo_data_valid = |sync_fifo_data_valid;

endmodule
