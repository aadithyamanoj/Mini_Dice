module priority_encoder_64bit
<<<<<<< HEAD
  import DE_pkg::*;
(
    input logic [ LANE_SIZE-1:0] data_in,   // Lane-wide input data
    input logic [LANE_WIDTH-1:0] start_pos, // Starting position for search

    output logic [LANE_WIDTH-1:0] encoded_out,  // Encoded position of first set bit
    output logic                  valid
);

  // Number of 8-bit chunks
  localparam int NUM_CHUNKS = LANE_SIZE / 8;
  localparam int CHUNK_IDX_WIDTH = $clog2(NUM_CHUNKS);
=======
    import DE_pkg::*;
(
    input  logic [LANE_SIZE-1:0]  data_in,     // Lane-wide input data
    input  logic [LANE_WIDTH-1:0]  start_pos,  // Starting position for search

    output logic [LANE_WIDTH-1:0]  encoded_out, // Encoded position of first set bit
    output logic                   valid
);

    // Number of 8-bit chunks
    localparam int NUM_CHUNKS = LANE_SIZE / 8;
    localparam int CHUNK_IDX_WIDTH = $clog2(NUM_CHUNKS);

    // Compute chunk index and bit index mathematically (NOT by slicing)
    wire [CHUNK_IDX_WIDTH-1:0] start_chunk = start_pos >> 3; // divide by 8
    wire [2:0]                 start_bit   = start_pos[2:0];

    // Per-chunk signals
    logic [7:0] chunk_data      [NUM_CHUNKS];
    logic [2:0] chunk_start_pos [NUM_CHUNKS];
    logic [2:0] chunk_encoded   [NUM_CHUNKS];
    logic       chunk_valid     [NUM_CHUNKS];

    // Second stage
    logic [NUM_CHUNKS-1:0]         chunk_valid_mask;
    logic [CHUNK_IDX_WIDTH-1:0]    winning_chunk;
    logic                          second_stage_valid;

    // Split input into chunks
    always_comb begin
        for (int i = 0; i < NUM_CHUNKS; i++) begin
            chunk_data[i] = data_in[i*8 +: 8];
        end
    end

    // Assign start bit per chunk
    always_comb begin
        for (int i = 0; i < NUM_CHUNKS; i++) begin
            if (i < start_chunk)
                chunk_start_pos[i] = 3'b111; // skip
            else if (i == start_chunk)
                chunk_start_pos[i] = start_bit;
            else
                chunk_start_pos[i] = 3'b000;
        end
    end

    // 8-bit priority encoders per chunk
    genvar gi;
    generate
        for (gi = 0; gi < NUM_CHUNKS; gi++) begin : gen_chunks
            priority_encoder_8bit pe8 (
                .data_in    (chunk_data[gi]),
                .start_pos  (chunk_start_pos[gi]),
                .encoded_out(chunk_encoded[gi]),
                .valid      (chunk_valid[gi])
            );
        end
    endgenerate

    // Build chunk-valid mask
    always_comb begin
        for (int i = 0; i < NUM_CHUNKS; i++) begin
            chunk_valid_mask[i] = (i >= start_chunk) ? chunk_valid[i] : 1'b0;
        end
    end

    // Zero-extend chunk-valid mask to 8 bits for second stage PE
    logic [7:0] chunk_valid_mask_ext;
    always_comb begin
        chunk_valid_mask_ext = 8'b0;
        chunk_valid_mask_ext[NUM_CHUNKS-1:0] = chunk_valid_mask;
    end

    // Second stage PE
    priority_encoder_8bit second_stage_pe (
        .data_in    (chunk_valid_mask_ext),
        .start_pos  (start_chunk),
        .encoded_out(winning_chunk),
        .valid      (second_stage_valid)
    );

    // Final output
    always_comb begin
        if (second_stage_valid) begin
            encoded_out = {winning_chunk, chunk_encoded[winning_chunk]};
            valid       = 1'b1;
        end else begin
            encoded_out = '0;
            valid       = 1'b0;
        end
    end
>>>>>>> origin/merging

  // Compute chunk index and bit index mathematically (NOT by slicing)
  wire  [CHUNK_IDX_WIDTH-1:0] start_chunk = start_pos >> 3;  // divide by 8
  wire  [                2:0] start_bit = start_pos[2:0];

  // Per-chunk signals
  logic [                7:0] chunk_data                                   [NUM_CHUNKS];
  logic [                2:0] chunk_start_pos                              [NUM_CHUNKS];
  logic [                2:0] chunk_encoded                                [NUM_CHUNKS];
  logic                       chunk_valid                                  [NUM_CHUNKS];

  // Second stage
  logic [     NUM_CHUNKS-1:0] chunk_valid_mask;
  logic [CHUNK_IDX_WIDTH-1:0] winning_chunk;
  logic [                2:0] winning_chunk_pe;
  logic [                2:0] second_stage_start_pos;
  logic                       second_stage_valid;

  // Split input into chunks
  always_comb begin
    for (int i = 0; i < NUM_CHUNKS; i++) begin
      chunk_data[i] = data_in[i*8+:8];
    end
  end

  // Assign start bit per chunk
  always_comb begin
    for (int i = 0; i < NUM_CHUNKS; i++) begin
      if (i < start_chunk) chunk_start_pos[i] = 3'b111;  // skip
      else if (i == start_chunk) chunk_start_pos[i] = start_bit;
      else chunk_start_pos[i] = 3'b000;
    end
  end

  // 8-bit priority encoders per chunk
  genvar gi;
  generate
    for (gi = 0; gi < NUM_CHUNKS; gi++) begin : gen_chunks
      priority_encoder_8bit pe8 (
          .data_in    (chunk_data[gi]),
          .start_pos  (chunk_start_pos[gi]),
          .encoded_out(chunk_encoded[gi]),
          .valid      (chunk_valid[gi])
      );
    end
  endgenerate

  // Build chunk-valid mask
  always_comb begin
    for (int i = 0; i < NUM_CHUNKS; i++) begin
      chunk_valid_mask[i] = (i >= start_chunk) ? chunk_valid[i] : 1'b0;
    end
  end

  // Zero-extend chunk-valid mask to 8 bits for second stage PE
  logic [7:0] chunk_valid_mask_ext;
  always_comb begin
    chunk_valid_mask_ext = 8'b0;
    chunk_valid_mask_ext[NUM_CHUNKS-1:0] = chunk_valid_mask;
  end

  // Explicitly zero-extend the chunk index into the 8-bit PE control width.
  always_comb begin
    second_stage_start_pos = '0;
    second_stage_start_pos[CHUNK_IDX_WIDTH-1:0] = start_chunk;
  end

  // Second stage PE
  priority_encoder_8bit second_stage_pe (
      .data_in    (chunk_valid_mask_ext),
      .start_pos  (second_stage_start_pos),
      .encoded_out(winning_chunk_pe),
      .valid      (second_stage_valid)
  );

  // Final output
  always_comb begin
    winning_chunk = winning_chunk_pe[CHUNK_IDX_WIDTH-1:0];
    if (second_stage_valid) begin
      encoded_out = {winning_chunk, chunk_encoded[winning_chunk]};
      valid       = 1'b1;
    end else begin
      encoded_out = '0;
      valid       = 1'b0;
    end
  end

endmodule
