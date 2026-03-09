module dtcm #(
    parameter int NUM_BYTES  = 128,
    parameter int NUM_WORDS  = 8,
    parameter int WORD_WIDTH = NUM_BYTES * 8
)(
    input  logic                  clk_i,
    input  logic                  en_i,
    input  logic [NUM_BYTES-1:0]  we_i,
    input  logic [2:0]            addr_i,
    input  logic [WORD_WIDTH-1:0] wdata_i,
    output logic [WORD_WIDTH-1:0] rdata_o
);
    logic [WORD_WIDTH-1:0] mem [0:NUM_WORDS-1];

    always_ff @(posedge clk_i) begin
        if (en_i) begin
            for (int i = 0; i < NUM_BYTES; i++) begin
                if (we_i[i]) begin
                    mem[addr_i][i*8 +: 8] <= wdata_i[i*8 +: 8];
                end
            end
            rdata_o <= mem[addr_i];
        end
    end
endmodule
