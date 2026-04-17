module active_mask_mapper
    import DE_pkg::*;
(
    input  logic [CHUNK_SIZE-1:0] active_mask_chunk,
    output logic [LANE_SIZE-1:0]  mask_lane0
);
    // NUM_LANES=1 => LANE_SIZE=CHUNK_SIZE, lane 0 gets the full active mask
    assign mask_lane0 = active_mask_chunk;

endmodule
