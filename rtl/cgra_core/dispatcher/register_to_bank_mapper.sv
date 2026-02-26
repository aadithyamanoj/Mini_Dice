module register_to_bank_mapper(
    input logic [31:0] reg_bitmap,      // 32-bit register bitmap (bit 0 = reg0, bit 1 = reg1, etc.)
    input logic [4:0] tid,              // Thread ID (lower 5 bits only)
    
    output logic [31:0] bank_bitmap     // 32-bit bank ID bitmap (bit 0 = bank0, bit 1 = bank1, etc.)
);

    // Internal signals
    logic [4:0] offset;                 // Offset based on TID range
    logic [4:0] bank_id [32];           // Bank ID for each register
    
    // Determine offset based on TID range
    always_comb begin
        if (tid < 5'd8) begin
            offset = 5'd0;              // No offset for range [0, 7]
        end else if (tid < 5'd16) begin
            offset = 5'd16;             // +16 offset for range [8, 15]
        end else if (tid < 5'd24) begin
            offset = 5'd8;              // +8 offset for range [16, 23]
        end else begin
            offset = 5'd24;             // +24 offset for range [24, 31]
        end
    end
    
    // Calculate bank ID for each register
    genvar i;
    generate
        for (i = 0; i < 32; i++) begin : gen_bank_mapping
            always_comb begin
                // bank_id = (tid + reg_num + offset)[4:0] - use lower 5 bits instead of %32
                bank_id[i] = tid + i[4:0] + offset;  // Automatic wraparound with 5-bit result
            end
        end
    endgenerate
    
    // Generate output bank bitmap
    always_comb begin
        // Initialize output
        bank_bitmap = 32'b0;
        
        // For each register that is set in input bitmap
        for (int reg_num = 0; reg_num < 32; reg_num++) begin
            if (reg_bitmap[reg_num]) begin
                // Set the corresponding bank bit
                bank_bitmap[bank_id[reg_num]] = 1'b1;
            end
        end
    end

endmodule