module active_mask_mapper
    import DE_pkg::*;
(
    input logic [CHUNK_SIZE-1:0] active_mask_chunk,   // Active mask chunk
    input logic [1:0] unrolling_factor,               // 0=1, 1=2, 2=4

    output logic [LANE_SIZE-1:0] mask_lane0,          // Active mask for next_tid_logic 0
    output logic [LANE_SIZE-1:0] mask_lane1,          // Active mask for next_tid_logic 1
    output logic [LANE_SIZE-1:0] mask_lane2,          // Active mask for next_tid_logic 2
    output logic [LANE_SIZE-1:0] mask_lane3           // Active mask for next_tid_logic 3
);

    // Internal signals for bit extraction
    logic [LANE_SIZE-1:0] lane0_bits, lane1_bits, lane2_bits, lane3_bits;

    always_comb begin
        // Initialize all lanes to zero
        lane0_bits = {LANE_SIZE{1'b0}};
        lane1_bits = {LANE_SIZE{1'b0}};
        lane2_bits = {LANE_SIZE{1'b0}};
        lane3_bits = {LANE_SIZE{1'b0}};

        case (unrolling_factor)
            2'b00: begin // unrolling_factor = 1
                // Simple sequential distribution: LANE_SIZE bits per lane
                lane0_bits = active_mask_chunk[0*LANE_SIZE +: LANE_SIZE];
                lane1_bits = active_mask_chunk[1*LANE_SIZE +: LANE_SIZE];
                lane2_bits = active_mask_chunk[2*LANE_SIZE +: LANE_SIZE];
                lane3_bits = active_mask_chunk[3*LANE_SIZE +: LANE_SIZE];
            end

            2'b01: begin // unrolling_factor = 2
                // Interleaved in 16-bit chunks between lane pairs within each half.
                // First half: lanes 0 (even 16-bit chunks) and 1 (odd 16-bit chunks)
                // Second half: lanes 2 (even 16-bit chunks) and 3 (odd 16-bit chunks)
                // Loop bound = LANE_SIZE/16 (interleaving granularity is 16 bits)
                for (int i = 0; i < LANE_SIZE/16; i++) begin
                    lane0_bits[i*16 +: 16] = active_mask_chunk[i*32 +: 16];
                    lane1_bits[i*16 +: 16] = active_mask_chunk[i*32+16 +: 16];
                end
                for (int i = 0; i < LANE_SIZE/16; i++) begin
                    lane2_bits[i*16 +: 16] = active_mask_chunk[CHUNK_SIZE/2+i*32 +: 16];
                    lane3_bits[i*16 +: 16] = active_mask_chunk[CHUNK_SIZE/2+i*32+16 +: 16];
                end
            end

            2'b10: begin // unrolling_factor = 4
                // Interleaved in 8-bit chunks cycling through all 4 lanes.
                // Loop bound = LANE_SIZE/8 (interleaving granularity is 8 bits)
                for (int i = 0; i < LANE_SIZE/8; i++) begin
                    lane0_bits[i*8 +: 8] = active_mask_chunk[i*32 +: 8];
                    lane1_bits[i*8 +: 8] = active_mask_chunk[i*32+8 +: 8];
                    lane2_bits[i*8 +: 8] = active_mask_chunk[i*32+16 +: 8];
                    lane3_bits[i*8 +: 8] = active_mask_chunk[i*32+24 +: 8];
                end
            end

            default: begin
                // Default to unrolling_factor = 1 behavior
                lane0_bits = active_mask_chunk[0*LANE_SIZE +: LANE_SIZE];
                lane1_bits = active_mask_chunk[1*LANE_SIZE +: LANE_SIZE];
                lane2_bits = active_mask_chunk[2*LANE_SIZE +: LANE_SIZE];
                lane3_bits = active_mask_chunk[3*LANE_SIZE +: LANE_SIZE];
            end
        endcase
    end

    // Output assignments
    assign mask_lane0 = lane0_bits;
    assign mask_lane1 = lane1_bits;
    assign mask_lane2 = lane2_bits;
    assign mask_lane3 = lane3_bits;

endmodule
