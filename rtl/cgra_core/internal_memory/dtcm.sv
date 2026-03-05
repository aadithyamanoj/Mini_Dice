module dtcm #(
    parameter WORD_WIDTH = 32,
    parameter NUM_WORDS  = 1024,
    parameter ADDR_WIDTH = $clog2(NUM_WORDS),
    parameter NUM_BYTES  = WORD_WIDTH / 8
)(
    input  logic                    clk,
    input  logic [NUM_BYTES-1:0]    we,       // byte-enable write strobes
    input  logic [ADDR_WIDTH-1:0]   addr,
    input  logic [WORD_WIDTH-1:0]   wdata,
    output logic [WORD_WIDTH-1:0]   rdata
);

    logic [WORD_WIDTH-1:0] mem [0:NUM_WORDS-1];

    // Synchronous byte-enable write
    always_ff @(posedge clk) begin
        for (int i = 0; i < NUM_BYTES; i++) begin
            if (we[i])
                mem[addr][i*8 +: 8] <= wdata[i*8 +: 8];
        end
    end

    // Synchronous read with write-first forwarding (same-cycle RAW hazard)
    logic [WORD_WIDTH-1:0] fwd_data;
    always_comb begin
        fwd_data = mem[addr];
        for (int i = 0; i < NUM_BYTES; i++) begin
            if (we[i])
                fwd_data[i*8 +: 8] = wdata[i*8 +: 8];
        end
    end

    always_ff @(posedge clk) begin
        rdata <= fwd_data;
    end

endmodule
