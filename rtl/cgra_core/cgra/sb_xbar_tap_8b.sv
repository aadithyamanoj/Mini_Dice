// sb_xbar_tap_8b.sv - 8b xbar tap buffer (BSG-based)
// Dora & Claude (AI-generated)

`include "bsg_defines.sv"
`timescale 1ns/1ps

module sb_xbar_tap_8b #(
    parameter int width_p = 8
)(
    input  logic [width_p-1:0] data_i
    ,output logic [width_p-1:0] data_o
);

    bsg_buf #(.width_p(width_p))
      i_buf (.i(data_i)
             ,.o(data_o)
             );

endmodule
