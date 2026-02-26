module active_mask_mapper(
    input logic [255:0] active_mask_chunk,    // 256-bit chunk of active mask
    input logic [1:0] unrolling_factor,       // 0=1, 1=2, 2=4
    
    output logic [63:0] mask_lane0,           // Active mask for next_tid_logic 0
    output logic [63:0] mask_lane1,           // Active mask for next_tid_logic 1  
    output logic [63:0] mask_lane2,           // Active mask for next_tid_logic 2
    output logic [63:0] mask_lane3            // Active mask for next_tid_logic 3
);

    // Internal signals for bit extraction
    logic [63:0] lane0_bits, lane1_bits, lane2_bits, lane3_bits;

    always_comb begin
        // Initialize all lanes to zero
        lane0_bits = 64'b0;
        lane1_bits = 64'b0; 
        lane2_bits = 64'b0;
        lane3_bits = 64'b0;
        
        case (unrolling_factor)
            2'b00: begin // unrolling_factor = 1
                // Simple sequential distribution: 64 bits per lane
                // Lane 0: 0-63, Lane 1: 64-127, Lane 2: 128-191, Lane 3: 192-255
                lane0_bits = active_mask_chunk[63:0];
                lane1_bits = active_mask_chunk[127:64];
                lane2_bits = active_mask_chunk[191:128];
                lane3_bits = active_mask_chunk[255:192];
            end
            
            2'b01: begin // unrolling_factor = 2
                // Interleaved pattern: 16-bit chunks alternate between lanes within each 128-bit half
                // Lane 0: 0-15, 32-47, 64-79, 96-111 (first half, even 16-bit chunks)
                // Lane 1: 16-31, 48-63, 80-95, 112-127 (first half, odd 16-bit chunks)
                // Lane 2: 128-143, 160-175, 192-207, 224-239 (second half, even 16-bit chunks)
                // Lane 3: 144-159, 176-191, 208-223, 240-255 (second half, odd 16-bit chunks)
                
                // First half (0-127): lanes 0 and 1
                for (int i = 0; i < 4; i++) begin
                    lane0_bits[i*16 +: 16] = active_mask_chunk[i*32 +: 16];    // 0-15, 32-47, 64-79, 96-111
                    lane1_bits[i*16 +: 16] = active_mask_chunk[i*32+16 +: 16]; // 16-31, 48-63, 80-95, 112-127
                end
                
                // Second half (128-255): lanes 2 and 3
                for (int i = 0; i < 4; i++) begin
                    lane2_bits[i*16 +: 16] = active_mask_chunk[128+i*32 +: 16];    // 128-143, 160-175, 192-207, 224-239
                    lane3_bits[i*16 +: 16] = active_mask_chunk[128+i*32+16 +: 16]; // 144-159, 176-191, 208-223, 240-255
                end
            end
            
            2'b10: begin // unrolling_factor = 4
                // Interleaved pattern: every 8 bits cycles through 4 lanes
                // Lane 0: 0-7, 32-39, 64-71, 96-103, 128-135, 160-167, 192-199, 224-231
                // Lane 1: 8-15, 40-47, 72-79, 104-111, 136-143, 168-175, 200-207, 232-239
                // Lane 2: 16-23, 48-55, 80-87, 112-119, 144-151, 176-183, 208-215, 240-247
                // Lane 3: 24-31, 56-63, 88-95, 120-127, 152-159, 184-191, 216-223, 248-255
                for (int i = 0; i < 8; i++) begin
                    lane0_bits[i*8 +: 8] = active_mask_chunk[i*32 +: 8];      // 0-7, 32-39, etc.
                    lane1_bits[i*8 +: 8] = active_mask_chunk[i*32+8 +: 8];    // 8-15, 40-47, etc.
                    lane2_bits[i*8 +: 8] = active_mask_chunk[i*32+16 +: 8];   // 16-23, 48-55, etc.
                    lane3_bits[i*8 +: 8] = active_mask_chunk[i*32+24 +: 8];   // 24-31, 56-63, etc.
                end
            end
            
            default: begin
                // Default to unrolling_factor = 1 behavior
                lane0_bits = active_mask_chunk[63:0];
                lane1_bits = active_mask_chunk[127:64];
                lane2_bits = active_mask_chunk[191:128];
                lane3_bits = active_mask_chunk[255:192];
            end
        endcase
    end

    // Output assignments
    assign mask_lane0 = lane0_bits;
    assign mask_lane1 = lane1_bits;
    assign mask_lane2 = lane2_bits;
    assign mask_lane3 = lane3_bits;

endmodule