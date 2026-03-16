// alu_8bit_mul.sv
module alu_mul (
    input  logic [7:0] A,
    input  logic [7:0] B,
    input  logic [1:0] opcode,
    input  logic en,
    output logic [7:0] result
);

    // Opcode constants
    localparam [1:0] OPCODE_MUL = 2'b10;

    // Implementation notes:
    // - Front-end: Radix-4 Booth encoding (overlapping groups of 3 multiplier bits)
    // - Back-end: partial-product reduction tree (pairwise adder reduction here)
    // The final product is computed in full width (2*W) internally and truncated
    // to the ALU result width (W) to match the existing ALU result conventions.

    localparam int W = 8;
    localparam int PP = (W + 1) / 2; // number of radix-4 partial products

    // partial products (signed), full precision 2*W bits
    logic signed [2*W-1:0] pp [0:PP-1];
    logic signed [2*W-1:0] sum_partial;
    logic signed [2*W-1:0] product_full;

    // sign-extend multiplicand to 2*W bits for signed operations
    logic signed [2*W-1:0] m_ext;
    logic [W:0] b_ext; // extra LSB 0 for Booth encoding

    integer i;
    logic [2:0] trip;
    integer idx_hi, idx_mid, idx_lo;
    always_comb begin
        // default outputs
        product_full = '0;
        trip = '0;
        idx_hi = 0;
        idx_mid = 0;
        idx_lo = 0;
        for (i = 0; i < PP; i = i + 1) begin
            pp[i] = '0;
        end

        // extend operands
        m_ext = $signed(8'(A));
        b_ext = { B, 1'b0 };

        if (en) begin
            // generate radix-4 Booth partial products
            for (i = 0; i < PP; i = i + 1) begin
                // examine bits: y_{2i+1}, y_{2i}, y_{2i-1}
                // where y_{-1}=0 is stored at b_ext[0] and y_k=B[k] at b_ext[k+1]
                idx_hi = 2*i + 2;
                idx_mid = 2*i + 1;
                idx_lo = 2*i;
                // safely extract bits (if out-of-range, treat as 0)
                trip[2] = (idx_hi <= W) ? b_ext[idx_hi] : 1'b0;
                trip[1] = (idx_mid <= W) ? b_ext[idx_mid] : 1'b0;
                trip[0] = (idx_lo <= W) ? b_ext[idx_lo] : 1'b0;

                // Booth encoding radix-4
                // 000 -> 0; 001/010 -> +1*M; 011 -> +2*M;
                // 100 -> -2*M; 101/110 -> -1*M; 111 -> 0
                case (trip)
                    3'b000, 3'b111: pp[i] = '0;
                    3'b001, 3'b010: pp[i] = ($signed(m_ext) <<< (2*i)); // +1 * M << 2i
                    3'b011:         pp[i] = ($signed(m_ext) <<< (2*i + 1)); // +2 * M << 2i -> <<(2*i+1)
                    3'b100:         pp[i] = -($signed(m_ext) <<< (2*i + 1)); // -2 * M
                    3'b101, 3'b110: pp[i] = -($signed(m_ext) <<< (2*i)); // -1 * M
                    default:        pp[i] = '0;
                endcase
            end

            // simple reduction tree: sum all partial products
            sum_partial = '0;
            for (i = 0; i < PP; i = i + 1) begin
                sum_partial = sum_partial + pp[i];
            end
            product_full = sum_partial;
        end else begin
            product_full = '0;
        end
    end

    // truncate to ALU result width (lower W bits) — matches existing ALU result conventions
    assign result = product_full[W-1:0];

endmodule