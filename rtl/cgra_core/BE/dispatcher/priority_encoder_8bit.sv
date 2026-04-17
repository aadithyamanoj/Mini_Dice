 module priority_encoder_8bit(
    input logic [7:0] data_in,          // 8-bit input data
    input logic [2:0] start_pos,        // Starting position for search (0-7)
    
    output logic [2:0] encoded_out,     // 3-bit encoded position (0-7)
    output logic valid                  // Valid output (1 if any bit found)
);

    // Priority encoder starting from start_pos
    always_comb begin
        valid = 1'b0;
        encoded_out = 3'b000;
        
        // Search from start_pos onwards
        case (start_pos)
            3'b000: begin // Start from bit 0
                if (data_in[0]) begin
                    encoded_out = 3'b000; valid = 1'b1;
                end else if (data_in[1]) begin
                    encoded_out = 3'b001; valid = 1'b1;
                end else if (data_in[2]) begin
                    encoded_out = 3'b010; valid = 1'b1;
                end else if (data_in[3]) begin
                    encoded_out = 3'b011; valid = 1'b1;
                end else if (data_in[4]) begin
                    encoded_out = 3'b100; valid = 1'b1;
                end else if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b001: begin // Start from bit 1
                if (data_in[1]) begin
                    encoded_out = 3'b001; valid = 1'b1;
                end else if (data_in[2]) begin
                    encoded_out = 3'b010; valid = 1'b1;
                end else if (data_in[3]) begin
                    encoded_out = 3'b011; valid = 1'b1;
                end else if (data_in[4]) begin
                    encoded_out = 3'b100; valid = 1'b1;
                end else if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b010: begin // Start from bit 2
                if (data_in[2]) begin
                    encoded_out = 3'b010; valid = 1'b1;
                end else if (data_in[3]) begin
                    encoded_out = 3'b011; valid = 1'b1;
                end else if (data_in[4]) begin
                    encoded_out = 3'b100; valid = 1'b1;
                end else if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b011: begin // Start from bit 3
                if (data_in[3]) begin
                    encoded_out = 3'b011; valid = 1'b1;
                end else if (data_in[4]) begin
                    encoded_out = 3'b100; valid = 1'b1;
                end else if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b100: begin // Start from bit 4
                if (data_in[4]) begin
                    encoded_out = 3'b100; valid = 1'b1;
                end else if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b101: begin // Start from bit 5
                if (data_in[5]) begin
                    encoded_out = 3'b101; valid = 1'b1;
                end else if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b110: begin // Start from bit 6
                if (data_in[6]) begin
                    encoded_out = 3'b110; valid = 1'b1;
                end else if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
            3'b111: begin // Start from bit 7
                if (data_in[7]) begin
                    encoded_out = 3'b111; valid = 1'b1;
                end
            end
        endcase
    end

endmodule