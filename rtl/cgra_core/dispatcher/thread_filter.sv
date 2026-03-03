module thread_filter
    import dice_pkg::*,
           DE_pkg::*;
(
    input logic clk,
    input logic rst,
    input logic [1:0] unrolling_factor,     // 0=1, 1=2, 2=4

    // Inputs from thread_lane_reroute: {compare_tid, real_tid}
    input logic [2*DICE_TID_WIDTH-1:0] next_tid_0,
    input logic valid_0,
    input logic [2*DICE_TID_WIDTH-1:0] next_tid_1,
    input logic valid_1,
    input logic [2*DICE_TID_WIDTH-1:0] next_tid_2,
    input logic valid_2,
    input logic [2*DICE_TID_WIDTH-1:0] next_tid_3,
    input logic valid_3,

    // FIFO pop interface
    input logic fifo_pop,                   // Single pop signal for all FIFOs

    // Outputs to next_thread_logic_top
    output logic [NUM_LANES-1:0] update,    // Update signals for each lane

    // FIFO outputs: {valid, real_tid}
    output logic [DICE_TID_WIDTH:0] fifo_data_0,
    output logic [DICE_TID_WIDTH:0] fifo_data_1,
    output logic [DICE_TID_WIDTH:0] fifo_data_2,
    output logic [DICE_TID_WIDTH:0] fifo_data_3,
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

    // Unpack real_tid (lower half) and compare_tid (upper half) from inputs
    logic [DICE_TID_WIDTH-1:0] next_tid         [NUM_LANES];
    logic [DICE_TID_WIDTH-1:0] next_tid_compare [NUM_LANES];
    logic [NUM_LANES-1:0]      valid;

    // Waveform observation signals
    logic [DICE_TID_WIDTH-1:0] obs_next_tid_0, obs_next_tid_1, obs_next_tid_2, obs_next_tid_3;
    logic [DICE_TID_WIDTH-1:0] obs_next_tid_compare_0, obs_next_tid_compare_1, obs_next_tid_compare_2, obs_next_tid_compare_3;

    assign next_tid[0] = next_tid_0[DICE_TID_WIDTH-1:0];
    assign next_tid[1] = next_tid_1[DICE_TID_WIDTH-1:0];
    assign next_tid[2] = next_tid_2[DICE_TID_WIDTH-1:0];
    assign next_tid[3] = next_tid_3[DICE_TID_WIDTH-1:0];

    assign next_tid_compare[0] = next_tid_0[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];
    assign next_tid_compare[1] = next_tid_1[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];
    assign next_tid_compare[2] = next_tid_2[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];
    assign next_tid_compare[3] = next_tid_3[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];

    assign obs_next_tid_0 = next_tid[0];
    assign obs_next_tid_1 = next_tid[1];
    assign obs_next_tid_2 = next_tid[2];
    assign obs_next_tid_3 = next_tid[3];
    assign obs_next_tid_compare_0 = next_tid_compare[0];
    assign obs_next_tid_compare_1 = next_tid_compare[1];
    assign obs_next_tid_compare_2 = next_tid_compare[2];
    assign obs_next_tid_compare_3 = next_tid_compare[3];

    assign valid = {valid_3, valid_2, valid_1, valid_0};

    // Generate selective pop signals — only pop from non-empty FIFOs
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            fifo_pop_individual[i] = fifo_pop && !fifo_empty_individual[i];
        end
    end

    assign fifo_full  = |fifo_full_individual;   // ANY FIFO full
    assign fifo_empty = &fifo_empty_individual;  // ALL FIFOs empty

    // Dispatch logic
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            fifo_push[i]      = 1'b0;
            fifo_push_data[i] = {(DICE_TID_WIDTH+1){1'b0}};
            update[i]         = 1'b0;
        end

        case (unrolling_factor)
            2'b00: begin // unrolling_factor = 1 — only lane 0
                if (valid[0] && !fifo_full_individual[0]) begin
                    fifo_push[0]      = 1'b1;
                    fifo_push_data[0] = {1'b1, next_tid[0]};
                    update[0]         = 1'b1;
                end
            end

            2'b01: begin // unrolling_factor = 2 — lanes 0 and 1
                logic [DICE_TID_WIDTH-1:0] pi_0, pi_1, min_index;
                logic [NUM_LANES-1:0] fifos_ready;
                logic any_valid;

                pi_0      = valid[0] ? next_tid_compare[0] : {DICE_TID_WIDTH{1'b1}};
                pi_1      = valid[1] ? next_tid_compare[1] : {DICE_TID_WIDTH{1'b1}};
                any_valid = valid[0] | valid[1];
                min_index = (pi_0 < pi_1) ? pi_0 : pi_1;
                fifos_ready = ~(|fifo_full_individual);

                if (any_valid && fifos_ready[1:0] == 2'b11) begin
                    if (valid[0] && (pi_0 == min_index)) begin
                        fifo_push[0]      = 1'b1;
                        fifo_push_data[0] = {1'b1, next_tid[0]};
                        update[0]         = 1'b1;
                    end else begin
                        fifo_push[0]      = 1'b1;
                        fifo_push_data[0] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end

                    if (valid[1] && (pi_1 == min_index)) begin
                        fifo_push[1]      = 1'b1;
                        fifo_push_data[1] = {1'b1, next_tid[1]};
                        update[1]         = 1'b1;
                    end else begin
                        fifo_push[1]      = 1'b1;
                        fifo_push_data[1] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end
                end
            end

            2'b10: begin // unrolling_factor = 4 — all 4 lanes
                logic [DICE_TID_WIDTH-1:0] pi_0, pi_1, pi_2, pi_3, min_index;
                logic [NUM_LANES-1:0] fifos_ready;
                logic any_valid;

                pi_0 = valid[0] ? next_tid_compare[0] : {DICE_TID_WIDTH{1'b1}};
                pi_1 = valid[1] ? next_tid_compare[1] : {DICE_TID_WIDTH{1'b1}};
                pi_2 = valid[2] ? next_tid_compare[2] : {DICE_TID_WIDTH{1'b1}};
                pi_3 = valid[3] ? next_tid_compare[3] : {DICE_TID_WIDTH{1'b1}};

                any_valid = |valid;
                min_index = (pi_0 < pi_1) ? pi_0 : pi_1;
                min_index = (min_index < pi_2) ? min_index : pi_2;
                min_index = (min_index < pi_3) ? min_index : pi_3;
                fifos_ready = ~(|fifo_full_individual);

                if (any_valid && (&fifos_ready)) begin
                    if (valid[0] && (pi_0 == min_index)) begin
                        fifo_push[0]      = 1'b1;
                        fifo_push_data[0] = {1'b1, next_tid[0]};
                        update[0]         = 1'b1;
                    end else begin
                        fifo_push[0]      = 1'b1;
                        fifo_push_data[0] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end

                    if (valid[1] && (pi_1 == min_index)) begin
                        fifo_push[1]      = 1'b1;
                        fifo_push_data[1] = {1'b1, next_tid[1]};
                        update[1]         = 1'b1;
                    end else begin
                        fifo_push[1]      = 1'b1;
                        fifo_push_data[1] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end

                    if (valid[2] && (pi_2 == min_index)) begin
                        fifo_push[2]      = 1'b1;
                        fifo_push_data[2] = {1'b1, next_tid[2]};
                        update[2]         = 1'b1;
                    end else begin
                        fifo_push[2]      = 1'b1;
                        fifo_push_data[2] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end

                    if (valid[3] && (pi_3 == min_index)) begin
                        fifo_push[3]      = 1'b1;
                        fifo_push_data[3] = {1'b1, next_tid[3]};
                        update[3]         = 1'b1;
                    end else begin
                        fifo_push[3]      = 1'b1;
                        fifo_push_data[3] = {1'b0, {DICE_TID_WIDTH{1'b0}}};
                    end
                end
            end

            default: begin
                // Invalid unrolling factor — do nothing
            end
        endcase
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
    assign fifo_data_0 = fifo_data[0];
    assign fifo_data_1 = fifo_data[1];
    assign fifo_data_2 = fifo_data[2];
    assign fifo_data_3 = fifo_data[3];
    assign fifo_data_valid = |sync_fifo_data_valid;

endmodule
