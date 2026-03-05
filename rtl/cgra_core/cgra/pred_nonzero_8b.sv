// pred_nonzero_8b.sv - 8b non-zero predicate producer (BSG-based)
// Dora & Claude (AI-generated)

`include "bsg_defines.sv"
`timescale 1ns/1ps

module pred_nonzero_8b #(
    parameter int width_p = 8
)(
    input  logic [width_p-1:0] data_i
    ,output logic              pred_o
);

    bsg_reduce #(.width_p(width_p)
                 ,.or_p(1'b1)
                 )
      i_nonzero (.i(data_i)
                 ,.o(pred_o)
                 );

endmodule
