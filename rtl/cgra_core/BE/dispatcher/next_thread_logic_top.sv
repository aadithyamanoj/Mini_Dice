module next_thread_logic_top
    import dice_pkg::*,
           dice_frontend_pkg::*,
           DE_pkg::*;
(
    input  logic clk,
    input  logic rst,
    input  logic [CHUNK_SIZE-1:0]       active_mask_chunk,
    input  logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr,
    input  logic restart,
    input  logic fifo_pop,

    output logic [DICE_TID_WIDTH-1:0] next_tid_0,
    output logic valid_0,
    output logic fifo_data_valid,
    output logic fifo_empty,
    output logic fifo_full,
    output logic chunk_done
);

    logic [DICE_TID_WIDTH:0] fifo_data_0;

    assign next_tid_0 = fifo_data_0[DICE_TID_WIDTH-1:0];
    assign valid_0    = fifo_data_0[DICE_TID_WIDTH];

    logic [NUM_LANES-1:0]          update;
    logic [NUM_LANES-1:0]          update_next_active_thread_logic;
    logic [LANE_SIZE-1:0]          mask_lane0;
    logic [$clog2(CHUNK_SIZE)-1:0] lane_index [NUM_LANES];
    logic [NUM_LANES-1:0]          lane_valid;
    logic [NUM_LANES-1:0]          done;

    logic [2*DICE_TID_WIDTH-1:0] pre_next_tid_0;
    logic                        pre_valid_0;

    logic [2*DICE_TID_WIDTH-1:0] final_tid   [NUM_LANES];
    logic [NUM_LANES-1:0]        final_valid;

    assign chunk_done = done[0] && fifo_empty;

    // Active mask mapper
    active_mask_mapper mask_mapper (
        .active_mask_chunk(active_mask_chunk),
        .mask_lane0(mask_lane0)
    );

    // Single next_active_thread_logic instance (NUM_LANES=1)
    genvar i;
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_lanes
            next_active_thread_logic #(
                .UNROLLING_INDEX(i)
            ) lane (
                .clk(clk),
                .rst(rst),
                .unrolling_factor(2'b00),
                .update(update_next_active_thread_logic[i]),
                .active_mask_lane(mask_lane0),
                .restart(restart),
                .next_tid(lane_index[i]),
                .valid(lane_valid[i]),
                .done(done[i])
            );
        end
    endgenerate

    thread_lane_reroute u_thread_lane_reroute (
        .clk(clk),
        .rst(rst),
        .chunk_base_addr(chunk_base_addr),
        .update_next_active_thread_logic(update_next_active_thread_logic),
        .fifo_pop(update),
        .next_tid_0(lane_index[0]),
        .valid_0(lane_valid[0]),
        .fifo_data_0(final_tid[0]),
        .fifo_data_valid(final_valid)
    );

    assign pre_next_tid_0 = final_tid[0];
    assign pre_valid_0    = final_valid[0];

    thread_filter filter (
        .clk(clk),
        .rst(rst),
        .next_tid_0(pre_next_tid_0),
        .valid_0(pre_valid_0),
        .fifo_pop(fifo_pop),
        .update(update),
        .fifo_data_0(fifo_data_0),
        .fifo_data_valid(fifo_data_valid),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full)
    );

endmodule
