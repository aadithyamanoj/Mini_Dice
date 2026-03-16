module mux_generic (
    input  logic [7:0] in_add,
    input  logic [7:0] in_mul,
    input  logic [1:0] en,
    input  logic        clk_i,
    output logic [7:0] out
);

    logic [7:0] out_comb;

    always_comb begin
        // default: nothing selected
        out_comb = 8'b0;
        if (en[0])
            out_comb |= in_add;
        if (en[1])
            out_comb |= in_mul;
    end

    always_ff @(posedge clk_i) begin
        out <= out_comb;
    end

endmodule