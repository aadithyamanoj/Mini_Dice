module priority_encoder_64bit(
    input logic [63:0] data_in,         // 64-bit input data
    input logic [5:0] start_pos,        // Starting position for search (0-63)
    
    output logic [5:0] encoded_out,     // 6-bit encoded position (0-63)
    output logic valid                  // Valid output (1 if any bit found)
);

    // Break down start_pos into chunk index and bit index
    wire [2:0] start_chunk = start_pos[5:3];  // Which 8-bit chunk to start from (0-7)
    wire [2:0] start_bit = start_pos[2:0];    // Which bit within the chunk to start from (0-7)
    
    // Signals for 8-bit priority encoders
    logic [7:0] chunk_data [8];         // 8 chunks of 8-bit data
    logic [2:0] chunk_start_pos [8];    // Start position for each chunk
    logic [2:0] chunk_encoded [8];      // Encoded output from each chunk
    logic chunk_valid [8];              // Valid output from each chunk
    
    // Second stage signals
    logic [7:0] chunk_valid_mask;       // Valid mask for second stage priority encoder
    logic [2:0] winning_chunk;          // Which chunk has the result
    logic second_stage_valid;           // Valid output from second stage
    
    // Split 64-bit data into 8 chunks of 8 bits
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            chunk_data[i] = data_in[i*8 +: 8];
        end
    end
    
    // Set start positions for each chunk
    always_comb begin
        for (int i = 0; i < 8; i++) begin
            if (i < start_chunk) begin
                // Chunks before start_chunk are not searched
                chunk_start_pos[i] = 3'b111;  // Invalid start position
            end else if (i == start_chunk) begin
                // Start chunk uses the specified start bit
                chunk_start_pos[i] = start_bit;
            end else begin
                // Chunks after start_chunk start from bit 0
                chunk_start_pos[i] = 3'b000;
            end
        end
    end
    
    // Generate 8-bit priority encoders
    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : gen_8bit_encoders
            priority_encoder_8bit pe8 (
                .data_in(chunk_data[i]),
                .start_pos(chunk_start_pos[i]),
                .encoded_out(chunk_encoded[i]),
                .valid(chunk_valid[i])
            );
        end
    endgenerate
    
    // Create valid mask for second stage, masking out chunks before start_chunk
    always_comb begin
        chunk_valid_mask = 8'b0;
        for (int i = 0; i < 8; i++) begin
            if (i >= start_chunk) begin
                chunk_valid_mask[i] = chunk_valid[i];
            end else begin
                chunk_valid_mask[i] = 1'b0;
            end
        end
    end
    
    // Second stage: use 8-bit priority encoder to select among valid chunks
    logic [2:0] second_stage_start_pos;
    
    // Start position for second stage should be start_chunk
    assign second_stage_start_pos = start_chunk;
    
    // Second stage priority encoder
    priority_encoder_8bit second_stage_pe (
        .data_in(chunk_valid_mask),
        .start_pos(second_stage_start_pos),
        .encoded_out(winning_chunk),
        .valid(second_stage_valid)
    );
    
    // Final output generation
    always_comb begin
        if (second_stage_valid) begin
            encoded_out = {winning_chunk, chunk_encoded[winning_chunk]};
            valid = 1'b1;
        end else begin
            encoded_out = 6'b000000;
            valid = 1'b0;
        end
    end

endmodule