module thread_lane_reroute
    import dice_pkg::*,
           DE_pkg::*;
(
    input logic clk,                     // Clock signal
    input logic rst,                     // Active low reset signal
    input logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr, // Base address for the chunk

    output logic [NUM_LANES-1:0] update_next_active_thread_logic,

    input logic [NUM_LANES-1:0] fifo_pop,
    // Inputs from next_thread_logic_top
    input logic [$clog2(CHUNK_SIZE)-1:0] next_tid_0,
    input logic valid_0,

    output logic [2*DICE_TID_WIDTH-1:0] fifo_data_0, // FIFO data output

    output logic [NUM_LANES-1:0] fifo_data_valid      // FIFO valid signal
);

    logic [DICE_TID_WIDTH-1:0] fifo_full_tid;           // Full TID including chunk base address
    assign fifo_full_tid = {chunk_base_addr, next_tid_0};

    logic fifo_push;                                    // Push signal for FIFO
    logic [2*DICE_TID_WIDTH-1:0] fifo_push_data;       // Data to push into FIFO
    logic [NUM_LANES-1:0] full;

    logic [2*DICE_TID_WIDTH-1:0] fifo_data [NUM_LANES]; // Data read from each FIFO
    assign fifo_data_0 = fifo_data[0];

    // Update the lane tracker whenever we successfully push a new TID
    // (pre_fifo_pop collapses to fifo_push with a single lane)
    assign update_next_active_thread_logic[0] = fifo_push;

    // Single-lane selection: no rerouting needed
    always_comb begin
        fifo_push      = 1'b0;
        fifo_push_data = {2*DICE_TID_WIDTH{1'b0}};
        if (valid_0 && !full[0]) begin
            fifo_push_data = {fifo_full_tid, fifo_full_tid};
            fifo_push      = 1'b1;
        end
    end

    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_fifos
            sync_fifo_read_unreg #(
                .DATA_WIDTH(2*DICE_TID_WIDTH),  // 2*DICE_TID_WIDTH bits: {compare_tid, real_tid}
                .DEPTH(2)
            ) fifo_inst (
                .clk_i(clk),
                .rst(rst),

                // Write interface
                .push(fifo_push),
                .push_data(fifo_push_data),

                // Read interface
                .pop(fifo_pop[i]),
                .pop_data(fifo_data[i]),
                .pop_data_valid(fifo_data_valid[i]),

                // Status signals
                .empty(),
                .full(full[i]),
                .count()
            );
        end
    endgenerate

endmodule
