module next_thread_logic_top(
    input logic clk,
    input logic rst,
    input logic [1:0] unrolling_factor,     // 0=1, 1=2, 2=4
    input logic [255:0] active_mask_chunk,  // 256-bit active mask chunk
    input logic [1:0] chunk_base_addr,      // Base address of current chunk (00=0, 01=256, 10=512, 11=768)
    
    input logic restart,                   // Restart signal to reset lane 0
    // FIFO control signals
    input logic fifo_pop,                   // Single FIFO pop signal to control all FIFOs
    
    // FIFO outputs (final outputs from thread filter) - simplified
    output logic [9:0] next_tid_0,        // {tid} from FIFO 0
    output logic [9:0] next_tid_1,        // {tid} from FIFO 1
    output logic [9:0] next_tid_2,        // {tid} from FIFO 2
    output logic [9:0] next_tid_3,        // {tid} from FIFO 3
    output logic valid_0,        // {valid} from FIFO 0
    output logic valid_1,        // {valid} from FIFO 1
    output logic valid_2,        // {valid} from FIFO 2
    output logic valid_3,        // {valid} from FIFO 3
    output logic fifo_data_valid, // Valid bit from FIFO 0
    output logic fifo_empty,                // 1 if ALL FIFOs are empty
    output logic fifo_full,                  // 1 if ANY FIFO is full
    output logic chunk_done
);

    logic [10:0] fifo_data_0; 
    logic [10:0] fifo_data_1; 
    logic [10:0] fifo_data_2; 
    logic [10:0] fifo_data_3; 

    assign next_tid_0 = fifo_data_0[9:0]; // Extract TID from FIFO data
    assign next_tid_1 = fifo_data_1[9:0];
    assign next_tid_2 = fifo_data_2[9:0];
    assign next_tid_3 = fifo_data_3[9:0];
    
    assign valid_0 = fifo_data_0[10]; // Extract valid bit from FIFO data
    assign valid_1 = fifo_data_1[10] && unrolling_factor >= 2'b01;
    assign valid_2 = fifo_data_2[10] && unrolling_factor >= 2'b10;
    assign valid_3 = fifo_data_3[10] && unrolling_factor >= 2'b10;

    // Internal signals for next thread logic
    logic [3:0] update;                     // Update signals for each lane
    logic [3:0] update_next_active_thread_logic; // Update signals for next active thread logic
    logic [63:0] mask_lane0, mask_lane1, mask_lane2, mask_lane3;
    logic [7:0] lane_index [4];             // Index from each lane (0-255)
    logic [3:0] lane_valid;                   // Valid from each lane
    logic [3:0] done;
    
    // Intermediate signals (outputs from next thread logic, inputs to thread filter)
    logic [19:0] pre_next_tid_0, pre_next_tid_1, pre_next_tid_2, pre_next_tid_3;
    logic pre_valid_0, pre_valid_1, pre_valid_2, pre_valid_3;
    
    // Final output signals (combinational)
    logic [19:0] final_tid [4];
    logic [3:0] final_valid ;

    assign chunk_done = done[0] && done[1] && done[2] && done[3] && fifo_empty;
    
    // Active mask mapper instance
    active_mask_mapper mask_mapper (
        .active_mask_chunk(active_mask_chunk),
        .unrolling_factor(unrolling_factor),
        .mask_lane0(mask_lane0),
        .mask_lane1(mask_lane1),
        .mask_lane2(mask_lane2),
        .mask_lane3(mask_lane3)
    );
    
    // Generate 4 next_active_thread_logic instances
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_lanes
            next_active_thread_logic #(
                .UNROLLING_INDEX(i)
            ) lane (
                .clk(clk),
                .rst(rst),
                .unrolling_factor(unrolling_factor),
                .update(update_next_active_thread_logic[i]),
                .active_mask_lane(i == 0 ? mask_lane0 : 
                                 i == 1 ? mask_lane1 :
                                 i == 2 ? mask_lane2 : mask_lane3),
                .restart(restart),
                .next_tid(lane_index[i]),
                .valid(lane_valid[i]),
                .done(done[i])
            );
        end
    endgenerate

    thread_lane_reroute u_thread_lane_reroute(
        .clk(clk),
        .rst(rst),
        .unrolling_factor(unrolling_factor),
        .chunk_base_addr(chunk_base_addr),
        .update_next_active_thread_logic(update_next_active_thread_logic),
        .fifo_pop(update),
        
        // Inputs from next_thread_logic_top
        .next_tid_0(lane_index[0]),
        .valid_0(lane_valid[0]),
        .next_tid_1(lane_index[1]),
        .valid_1(lane_valid[1]),
        .next_tid_2(lane_index[2]),
        .valid_2(lane_valid[2]),
        .next_tid_3(lane_index[3]),
        .valid_3(lane_valid[3]),

        // Outputs to FIFO
        .fifo_data_0(final_tid[0]),
        .fifo_data_1(final_tid[1]),
        .fifo_data_2(final_tid[2]),
        .fifo_data_3(final_tid[3]),

        // FIFO valid signal
        .fifo_data_valid(final_valid)
    );
    
    // Assign intermediate signals
    assign pre_next_tid_0 = final_tid[0];
    assign pre_valid_0 = final_valid[0];
    assign pre_next_tid_1 = final_tid[1];
    assign pre_valid_1 = final_valid[1];
    assign pre_next_tid_2 = final_tid[2];
    assign pre_valid_2 = final_valid[2];
    assign pre_next_tid_3 = final_tid[3];
    assign pre_valid_3 = final_valid[3];

    // Thread Filter instance
    thread_filter filter (
        .clk(clk),
        .rst(rst),
        .unrolling_factor(unrolling_factor),
        .next_tid_0(pre_next_tid_0),
        .valid_0(pre_valid_0),
        .next_tid_1(pre_next_tid_1),
        .valid_1(pre_valid_1),
        .next_tid_2(pre_next_tid_2),
        .valid_2(pre_valid_2),
        .next_tid_3(pre_next_tid_3),
        .valid_3(pre_valid_3),
        .fifo_pop(fifo_pop),                // Use the input fifo_pop signals
        .update(update),                    // Connect update feedback
        .fifo_data_0(fifo_data_0),
        .fifo_data_1(fifo_data_1),
        .fifo_data_2(fifo_data_2),
        .fifo_data_3(fifo_data_3),
        .fifo_data_valid(fifo_data_valid), // Valid bit from FIFO 0
        .fifo_empty(fifo_empty),            // Combined empty signal
        .fifo_full(fifo_full)               // Combined full signal
    );

endmodule