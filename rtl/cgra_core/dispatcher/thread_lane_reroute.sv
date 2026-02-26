module thread_lane_reroute(
    input logic clk,                     // Clock signal
    input logic rst,                   // Active low reset signal
    input logic [1:0] unrolling_factor, // Unrolling factor (00=1, 01=2, 10=4)
    input logic [1:0] chunk_base_addr, // Base address for the chunk (10 bits)

    output logic [3:0] update_next_active_thread_logic,

    input logic [3:0] fifo_pop,
    // Inputs from next_thread_logic_top
    input logic [7:0] next_tid_0,
    input logic valid_0,
    input logic [7:0] next_tid_1,
    input logic valid_1,
    input logic [7:0] next_tid_2,
    input logic valid_2,
    input logic [7:0] next_tid_3,
    input logic valid_3,

    output logic [19:0] fifo_data_0, // FIFO data outputs
    output logic [19:0] fifo_data_1,
    output logic [19:0] fifo_data_2,
    output logic [19:0] fifo_data_3,

    output logic [3:0] fifo_data_valid          // FIFO empty signal
);

    logic [3:0] valid;
    assign valid = {valid_3, valid_2, valid_1, valid_0}; // Combine valid signals

    logic [3:0] fifo_push;                // Push signals for each FIFO
    logic [3:0] pre_fifo_pop;          // FIFO data valid signals
    logic [19:0] fifo_push_data [4];      // Data to push into
    logic [3:0] fifo_pop_individual;      // Individual pop signals for each FIFO

    logic [3:0] full;

    logic [10:0] fifo_full_tid [4];           // Data read from each FIFO
    logic [19:0] fifo_data [4];              // Data read from each FIFO
    assign fifo_data_0 = fifo_data[0];
    assign fifo_data_1 = fifo_data[1];
    assign fifo_data_2 = fifo_data[2];
    assign fifo_data_3 = fifo_data[3];

    always_comb begin
        // Initialize push signals to 0
        fifo_full_tid[0] = {chunk_base_addr, next_tid_0};
        fifo_full_tid[1] = {chunk_base_addr, next_tid_1};
        fifo_full_tid[2] = {chunk_base_addr, next_tid_2};    
        fifo_full_tid[3] = {chunk_base_addr, next_tid_3};
    end

    assign update_next_active_thread_logic[0] = pre_fifo_pop[0] && valid_0;
    assign update_next_active_thread_logic[1] = pre_fifo_pop[1] && valid_1;
    assign update_next_active_thread_logic[2] = pre_fifo_pop[2] && valid_2;
    assign update_next_active_thread_logic[3] = pre_fifo_pop[3] && valid_3;
// Selection logic based on unrolling factor
    always_comb begin
        // Initialize all outputs to invalid
        for (int j = 0; j < 4; j++) begin
            pre_fifo_pop[j] = 1'b0;
            fifo_push[j] = 1'b0;
            fifo_push_data[j] = 20'b0;
        end
        
        case (unrolling_factor)
            2'b10: begin // unrolling_factor = 4
                // Output all 4 lanes directly
                if (valid[0] && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[0], fifo_full_tid[0]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[0] = 1'b1;
                end

                if (valid[1] && !full[1]) begin
                    fifo_push_data[1] = {fifo_full_tid[1]-10'd8, fifo_full_tid[1]}; 
                    fifo_push[1] = 1'b1;
                    pre_fifo_pop[1] = 1'b1;
                end

                if (valid[2] && !full[2]) begin
                    fifo_push_data[2] = {fifo_full_tid[2]-10'd16, fifo_full_tid[2]}; 
                    fifo_push[2] = 1'b1;
                    pre_fifo_pop[2] = 1'b1;
                end

                if (valid[3]  && !full[3]) begin
                    fifo_push_data[3] = {fifo_full_tid[3]-10'd24, fifo_full_tid[3]}; 
                    fifo_push[3] = 1'b1;
                    pre_fifo_pop[3] = 1'b1;
                end
            end
            
            2'b01: begin // unrolling_factor = 2
                // Lane 0 and Lane 2 compete for output 0 (Lane 0 has priority)
                if (valid[0]  && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[0], fifo_full_tid[0]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[0] = 1'b1; // Update lane 0
                end else if (valid[2]  && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[2], fifo_full_tid[2]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[2] = 1'b1; 
                end
                
                // Lane 1 and Lane 3 compete for output 1 (Lane 1 has priority)
                if (valid[1]  && !full[1]) begin
                    fifo_push_data[1] = {fifo_full_tid[1]-10'd16, fifo_full_tid[1]}; 
                    fifo_push[1] = 1'b1;
                    pre_fifo_pop[1] = 1'b1; 
                end else if (valid[3]  && !full[1]) begin
                    fifo_push_data[1] = {fifo_full_tid[3]-10'd16, fifo_full_tid[3]}; 
                    fifo_push[1] = 1'b1;
                    pre_fifo_pop[3] = 1'b1; 
                end
                
                // Outputs 2 and 3 are invalid for unrolling_factor = 2
                fifo_push[2] = 1'b0;
                fifo_push[3] = 1'b0;
            end
            
            2'b00: begin // unrolling_factor = 1
                // Priority selection: Lane 0 > Lane 1 > Lane 2 > Lane 3
                // Only output 0 is used
                if (valid[0]  && !full[0]) begin
                    fifo_push_data[0] = { fifo_full_tid[0], fifo_full_tid[0]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[0] = 1'b1; // Update lane 0
                end else if (valid[1]  && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[1], fifo_full_tid[1]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[1] = 1'b1; // Update lane 0
                end else if (valid[2]  && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[2], fifo_full_tid[2]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[2] = 1'b1; // Update lane 0
                end else if (valid[3]  && !full[0]) begin
                    fifo_push_data[0] = {fifo_full_tid[3], fifo_full_tid[3]}; 
                    fifo_push[0] = 1'b1;
                    pre_fifo_pop[3] = 1'b1; // Update lane 0
                end
                
                // Outputs 1, 2, 3 are invalid for unrolling_factor = 1
                fifo_push[1] = 1'b0;
                fifo_push[2] = 1'b0;
                fifo_push[3] = 1'b0;
            end
            
            default: begin
                // All outputs invalid for unsupported unrolling factor
                for (int j = 0; j < 4; j++) begin
                    fifo_push[j] = 1'b0;
                    pre_fifo_pop[j] = 1'b0; // Update lane 0
                end
            end
        endcase
    end


    //sync fifo
    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_fifos
            sync_fifo_read_unreg #(
                .DATA_WIDTH(20),    // 20 bits: {  compared_tid[9:0], real_tid[9:0]} //compared tid for next stage
                .DEPTH(2)           // 4 entries deep
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                
                // Write interface
                .push(fifo_push[i]),
                .push_data(fifo_push_data[i]),
                
                // Read interface
                .pop(fifo_pop[i]), // Individual pop signal per FIFO
                .pop_data(fifo_data[i]),
                .pop_data_valid(fifo_data_valid[i]), // Not used in this design
                
                // Status signals
                .empty(),
                .full(full[i]),
                .count()   // Available but not used in this design
            );
        end
    endgenerate
endmodule