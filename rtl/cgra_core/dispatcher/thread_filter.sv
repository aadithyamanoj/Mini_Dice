module thread_filter(
    input logic clk,
    input logic rst,
    input logic [1:0] unrolling_factor,     // 0=1, 1=2, 2=4
    
    // Inputs from next_thread_logic_top
    input logic [19:0] next_tid_0,
    input logic valid_0,
    input logic [19:0] next_tid_1,
    input logic valid_1,
    input logic [19:0] next_tid_2,
    input logic valid_2,
    input logic [19:0] next_tid_3,
    input logic valid_3,
    
    // FIFO pop interface
    input logic fifo_pop,                   // Single pop signal for all FIFOs
    
    // Outputs to next_thread_logic_top
    output logic [3:0] update,              // Update signals for each lane
    
    // FIFO outputs - simplified
    output logic [10:0] fifo_data_0,        // {valid, tid} from FIFO 0
    output logic [10:0] fifo_data_1,        // {valid, tid} from FIFO 1  
    output logic [10:0] fifo_data_2,        // {valid, tid} from FIFO 2
    output logic [10:0] fifo_data_3,        // {valid, tid} from FIFO 3
    output logic fifo_data_valid,
    output logic fifo_empty,                // 1 if ALL FIFOs are empty
    output logic fifo_full                  // 1 if ANY FIFO is full
);

    // FIFO control signals
    logic [3:0] fifo_push;                  // Push signals for each FIFO
    logic [10:0] fifo_push_data [4];        // Push data for each FIFO {valid, tid}
    logic [3:0] fifo_full_individual;       // Individual full flags from FIFOs
    logic [3:0] fifo_empty_individual;      // Individual empty flags from FIFOs
    logic [3:0] fifo_pop_individual;        // Individual pop signals for each FIFO
    logic [10:0] fifo_data [4];             // Data from FIFOs
    logic [2:0] fifo_count [4];             // Count from FIFOs (unused but available)
    
    // Input arrays for easier processing
    logic [9:0] next_tid [4];
    logic [9:0] next_tid_compare [4];
    logic [3:0] valid;

    
    assign next_tid[0] = next_tid_0[9:0];
    assign next_tid[1] = next_tid_1[9:0];
    assign next_tid[2] = next_tid_2[9:0];
    assign next_tid[3] = next_tid_3[9:0];

    assign next_tid_compare[0] = next_tid_0[19:10];
    assign next_tid_compare[1] = next_tid_1[19:10];
    assign next_tid_compare[2] = next_tid_2[19:10];
    assign next_tid_compare[3] = next_tid_3[19:10];

       //observe in waveform
    logic [9:0] obs_next_tid_0, obs_next_tid_1, obs_next_tid_2, obs_next_tid_3;
    logic [9:0] obs_next_tid_compare_0, obs_next_tid_compare_1, obs_next_tid_compare_2, obs_next_tid_compare_3;
    assign obs_next_tid_0 = next_tid[0];
    assign obs_next_tid_1 = next_tid[1];
    assign obs_next_tid_2 = next_tid[2];
    assign obs_next_tid_3 = next_tid[3];
    assign obs_next_tid_compare_0 = next_tid_compare[0];
    assign obs_next_tid_compare_1 = next_tid_compare[1];
    assign obs_next_tid_compare_2 = next_tid_compare[2];
    assign obs_next_tid_compare_3 = next_tid_compare[3];

    assign valid = {valid_3, valid_2, valid_1, valid_0};
    
    // Generate selective pop signals - only pop from non-empty FIFOs
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            fifo_pop_individual[i] = fifo_pop && !fifo_empty_individual[i];
        end
    end
    
    // Generate combined status signals
    assign fifo_full = |fifo_full_individual;      // ANY FIFO is full
    assign fifo_empty = &fifo_empty_individual;    // ALL FIFOs are empty
    
    // Dispatch logic
    always_comb begin
        // Initialize all signals
        for (int i = 0; i < 4; i++) begin
            fifo_push[i] = 1'b0;
            fifo_push_data[i] = 11'b0;
            update[i] = 1'b0;
        end
        
        case (unrolling_factor)
            2'b00: begin // unrolling_factor = 1
                // Only use lane 0
                if (valid[0] && !fifo_full_individual[0]) begin
                    fifo_push[0] = 1'b1;
                    fifo_push_data[0] = {1'b1, next_tid[0]};  // {valid=1, tid}
                    update[0] = 1'b1; // Update lane 0
                end
            end
            
            2'b01: begin // unrolling_factor = 2
                // Use lanes 0 and 1
                logic [9:0] pi_0, pi_1;
                logic [9:0] min_index;
                logic [3:0] fifos_ready;
                logic any_valid;
                
                pi_0 = valid[0] ? next_tid_compare[0]: 10'h3ff; // Lane 0
                pi_1 = valid[1] ? next_tid_compare[1]: 10'h3ff;  // Corrected offset to match C code
                
                // Check if any lanes are valid
                any_valid = valid[0] | valid[1];
                
                // Find minimum index
                min_index = (pi_0 < pi_1) ? pi_0 : pi_1;
                
                // Check if FIFOs are ready
                fifos_ready = ~ (|fifo_full_individual);
                
                // Only proceed if there are valid threads and both FIFOs are ready
                if (any_valid && fifos_ready[1:0] == 2'b11) begin
                    // Dispatch lanes that match minimum index
                    if (valid[0] && (pi_0 == min_index)) begin
                        fifo_push[0] = 1'b1;
                        fifo_push_data[0] = {1'b1, next_tid[0]};
                        update[0] = 1'b1; // Update lane 0
                    end else begin
                        fifo_push[0] = 1'b1;
                        fifo_push_data[0] = {1'b0, 10'b0};  // Invalid entry
                    end
                    
                    if (valid[1] && (pi_1 == min_index)) begin
                        fifo_push[1] = 1'b1;
                        fifo_push_data[1] = {1'b1, next_tid[1]};
                        update[1] = 1'b1; // Update lane 1
                    end else begin
                        fifo_push[1] = 1'b1;
                        fifo_push_data[1] = {1'b0, 10'b0};  // Invalid entry
                    end
                end
            end
            
            2'b10: begin // unrolling_factor = 4
                // Use all 4 lanes
                logic [9:0] pi_0, pi_1, pi_2, pi_3;
                logic [9:0] min_index;
                logic [3:0] fifos_ready;
                logic any_valid;
                
                // Calculate adjusted indices (pi values)
                pi_0 = valid[0] ? next_tid_compare[0]: 10'h3ff; // Lane 0
                pi_1 = valid[1] ? next_tid_compare[1]: 10'h3ff;  // Lane 1
                pi_2 = valid[2] ? next_tid_compare[2]: 10'h3ff; // Lane 2
                pi_3 = valid[3] ? next_tid_compare[3]: 10'h3ff;  // Lane 3
                
                // Check if any lanes are valid
                any_valid = valid[0] | valid[1] | valid[2] | valid[3];
                
                // Find minimum index (matches C code logic)
                min_index = (pi_0 < pi_1) ? pi_0 : pi_1;
                min_index = (min_index < pi_2) ? min_index : pi_2;
                min_index = (min_index < pi_3) ? min_index : pi_3;
                
                // Check if all FIFOs are ready
                fifos_ready = ~ (|fifo_full_individual);
                
                // Only proceed if there are valid threads and all FIFOs are ready
                if (any_valid && (&fifos_ready)) begin
                    // Dispatch lanes that match minimum index
                    if (valid[0] && (pi_0 == min_index)) begin
                        fifo_push[0] = 1'b1;
                        fifo_push_data[0] = {1'b1, next_tid[0]};
                        update[0] = 1'b1;
                    end else begin
                        fifo_push[0] = 1'b1;
                        fifo_push_data[0] = {1'b0, 10'b0};  // Invalid entry
                    end
                    
                    if (valid[1] && (pi_1 == min_index)) begin
                        fifo_push[1] = 1'b1;
                        fifo_push_data[1] = {1'b1, next_tid[1]};
                        update[1] = 1'b1;
                    end else begin
                        fifo_push[1] = 1'b1;
                        fifo_push_data[1] = {1'b0, 10'b0};  // Invalid entry
                    end
                    
                    if (valid[2] && (pi_2 == min_index)) begin
                        fifo_push[2] = 1'b1;
                        fifo_push_data[2] = {1'b1, next_tid[2]};
                        update[2] = 1'b1;
                    end else begin
                        fifo_push[2] = 1'b1;
                        fifo_push_data[2] = {1'b0, 10'b0};  // Invalid entry
                    end
                    
                    if (valid[3] && (pi_3 == min_index)) begin
                        fifo_push[3] = 1'b1;
                        fifo_push_data[3] = {1'b1, next_tid[3]};
                        update[3] = 1'b1;
                    end else begin
                        fifo_push[3] = 1'b1;
                        fifo_push_data[3] = {1'b0, 10'b0};  // Invalid entry
                    end
                end
            end
            
            default: begin
                // Invalid unrolling factor, do nothing
            end
        endcase
    end
    
    // Generate 4 parameterized sync_fifo instances
    logic [3:0] sync_fifo_data_valid;
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_fifos
            sync_fifo #(
                .DATA_WIDTH(11),    // 11 bits: {valid[10], tid[9:0]}
                .DEPTH(4)           // 4 entries deep
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                
                // Write interface
                .push(fifo_push[i]),
                .push_data(fifo_push_data[i]),
                
                // Read interface
                .pop(fifo_pop_individual[i]), // Individual pop signal per FIFO
                .pop_data(fifo_data[i]),
                .pop_data_valid(sync_fifo_data_valid[i]), // Not used in this design
                
                // Status signals
                .empty(fifo_empty_individual[i]),
                .full(fifo_full_individual[i]),
                .count(fifo_count[i])   // Available but not used in this design
            );
        end
    endgenerate
    
    // Output assignments
    assign fifo_data_0 = fifo_data[0];
    assign fifo_data_1 = fifo_data[1];
    assign fifo_data_2 = fifo_data[2];
    assign fifo_data_3 = fifo_data[3];
    //assign fifo_data_0[9:0] = fifo_data[0][9:0];
    //assign fifo_data_1[9:0] = fifo_data[1][9:0];
    //assign fifo_data_2[9:0] = fifo_data[2][9:0];
    //assign fifo_data_3[9:0] = fifo_data[3][9:0];
    //assign fifo_data_0[10] = fifo_data[0][10] && !fifo_empty_individual[0];
    //assign fifo_data_1[10] = fifo_data[1][10] && !fifo_empty_individual[1];
    //assign fifo_data_2[10] = fifo_data[2][10] && !fifo_empty_individual[2];
    //assign fifo_data_3[10] = fifo_data[3][10] && !fifo_empty_individual[3];
    assign fifo_data_valid = sync_fifo_data_valid[0] | sync_fifo_data_valid[1] |
                             sync_fifo_data_valid[2] | sync_fifo_data_valid[3];

endmodule