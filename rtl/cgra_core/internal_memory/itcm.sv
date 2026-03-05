module itcm #(
    parameter WORD_WIDTH = 32,
    parameter NUM_WORDS  = 1024,
    parameter ADDR_WIDTH = $clog2(NUM_WORDS)
)(
    input  logic                    clk,
    input  logic                    we,
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [WORD_WIDTH-1:0]   wdata,
    output logic [WORD_WIDTH-1:0]   rdata
);

    logic [WORD_WIDTH-1:0] mem [0:NUM_WORDS-1];

    // Synchronous write
    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
    end

    // Synchronous read
    always_ff @(posedge clk) begin
        rdata <= mem[addr];
    end

endmodule
