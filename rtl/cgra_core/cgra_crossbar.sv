// Parameterized all-to-all crossbar: routes NUM_INPUTS register values (from TID 0
// of the register file) to NUM_OUTPUTS PE-array inputs.
module cgra_crossbar #(
    parameter int NUM_INPUTS   = 16,                // number of sources
    parameter int NUM_OUTPUTS  = 8,                 // number of destinations
    parameter int DATA_WIDTH   = 8,                 // bits per channel
    parameter int SEL_WIDTH    = $clog2(NUM_INPUTS) // bits per selector; override to 1 when NUM_INPUTS == 1
)(
    input  logic clk_i,
    input  logic rst_i,

    // -------------------------------------------------------------------------
    // Input side: NUM_INPUTS sources, each DATA_WIDTH bits wide.
    // -------------------------------------------------------------------------
    input  logic [NUM_INPUTS-1:0][DATA_WIDTH-1:0]   data_i,

    // -------------------------------------------------------------------------
    // Configuration interface.
    // cfg_sel_i is a flat bitstream: output i selects data_i[sel[i]].
    // Assert cfg_load_i for one cycle to latch a new routing configuration.
    // -------------------------------------------------------------------------
    input  logic                                     cfg_load_i,
    input  logic [NUM_OUTPUTS*SEL_WIDTH-1:0]         cfg_sel_i,

    // -------------------------------------------------------------------------
    // Output side: NUM_OUTPUTS routed outputs, each DATA_WIDTH bits wide.
    // -------------------------------------------------------------------------
    output logic [NUM_OUTPUTS-1:0][DATA_WIDTH-1:0]   data_o
);

    // -------------------------------------------------------------------------
    // Configuration registers — one SEL_WIDTH-bit selector per output
    // -------------------------------------------------------------------------
    logic [NUM_OUTPUTS-1:0][SEL_WIDTH-1:0] sel_reg;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            sel_reg <= '0;
        end else if (cfg_load_i) begin
            for (int i = 0; i < NUM_OUTPUTS; i++) begin
                sel_reg[i] <= cfg_sel_i[(i+1)*SEL_WIDTH-1 : i*SEL_WIDTH];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Routing: each output is a NUM_INPUTS:1 mux driven by its stored selector
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_OUTPUTS; i++) begin : gen_out_mux
            assign data_o[i] = data_i[sel_reg[i]];
        end
    endgenerate

endmodule

