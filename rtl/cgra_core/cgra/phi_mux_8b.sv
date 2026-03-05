// phi_mux_8b.sv - 2-input PHI mux: data_o = pred_i ? data_true_i : data_false_i
// Dora & Claude (AI-generated)

`include "bsg_defines.sv"
`timescale 1ns/1ps

module phi_mux_8b #(
    parameter int width_p = 8
)(
    input  logic                pred_i
    ,input  logic [width_p-1:0] data_true_i
    ,input  logic [width_p-1:0] data_false_i
    ,output logic [width_p-1:0] data_o
);

    bsg_mux #(.width_p(width_p)
              ,.els_p(2)
              )
      i_mux (.data_i({data_true_i, data_false_i})
             ,.sel_i(pred_i)
             ,.data_o(data_o)
             );

endmodule
