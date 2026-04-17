module reverse_mapper #(
    parameter int UNROLLING_INDEX = 0       // Index for unrolling lane (0-3)
)(
    input logic [5:0] encoded_pos,          // 6-bit position from 64-bit priority encoder (0-63)
    input logic [1:0] unrolling_factor,     // 0=1, 1=2, 2=4
    input logic valid_in,                   // Valid input from priority encoder
    
    output logic [7:0] active_mask_index,   // 8-bit index in the 256-bit active mask chunk
    output logic valid_out                  // Valid output
);

    // Internal signals
    logic [7:0] mapped_index;
    
    always_comb begin
        mapped_index = 8'b0;
        valid_out = valid_in;
        
        if (valid_in) begin
            case (unrolling_factor)
                2'b00: begin // unrolling_factor = 1
                    // Simple sequential mapping: lane maps to consecutive 64-bit blocks
                    // Lane 0: 0-63, Lane 1: 64-127, Lane 2: 128-191, Lane 3: 192-255
                    mapped_index = {UNROLLING_INDEX[1:0], encoded_pos};
                end
                
                2'b01: begin // unrolling_factor = 2
                    // Interleaved 16-bit chunks mapping
                    // Lane 0: 0-15, 32-47, 64-79, 96-111 (first half, even chunks)
                    // Lane 1: 16-31, 48-63, 80-95, 112-127 (first half, odd chunks)  
                    // Lane 2: 128-143, 160-175, 192-207, 224-239 (second half, even chunks)
                    // Lane 3: 144-159, 176-191, 208-223, 240-255 (second half, odd chunks)
                    
                    case (UNROLLING_INDEX)
                        2'b00: begin // Lane 0: even chunks in first half
                            mapped_index = {1'b0, encoded_pos[5:4], 1'b0, encoded_pos[3:0]};  // 0-15, 32-47, 64-79, 96-111
                        end
                        2'b01: begin // Lane 1: odd chunks in first half
                            mapped_index = {1'b0, encoded_pos[5:4], 1'b1, encoded_pos[3:0]};  // 16-31, 48-63, 80-95, 112-127
                        end
                        2'b10: begin // Lane 2: even chunks in second half
                            mapped_index = {1'b1, encoded_pos[5:4], 1'b0, encoded_pos[3:0]}; // 128-143, 160-175, 192-207, 224-239
                        end
                        2'b11: begin // Lane 3: odd chunks in second half
                            mapped_index = {1'b1, encoded_pos[5:4], 1'b1, encoded_pos[3:0]}; // 144-159, 176-191, 208-223, 240-255
                        end
                    endcase
                end
                
                2'b10: begin // unrolling_factor = 4
                    // Interleaved 8-bit chunks mapping
                    // Lane 0: 0-7, 32-39, 64-71, 96-103, 128-135, 160-167, 192-199, 224-231
                    // Lane 1: 8-15, 40-47, 72-79, 104-111, 136-143, 168-175, 200-207, 232-239
                    // Lane 2: 16-23, 48-55, 80-87, 112-119, 144-151, 176-183, 208-215, 240-247
                    // Lane 3: 24-31, 56-63, 88-95, 120-127, 152-159, 184-191, 216-223, 248-255
                    
                    // Map back to original position: chunk_in_lane*32 + UNROLLING_INDEX*8 + bit_in_chunk
                    mapped_index = {encoded_pos[5:3], UNROLLING_INDEX[1:0], encoded_pos[2:0]};
                end
                
                default: begin
                    // Default to unrolling_factor = 1 behavior
                    mapped_index = {UNROLLING_INDEX[1:0], encoded_pos};
                    valid_out = 1'b0; // Invalid unrolling factor
                end
            endcase
        end else begin
            mapped_index = 8'b0;
            valid_out = 1'b0;
        end
    end

    assign active_mask_index = mapped_index;

endmodule