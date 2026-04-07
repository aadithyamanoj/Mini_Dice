// bsg_dffre.tmpl.sv - Wrapper for bsg_dff_reset_en
// Dora & Claude (AI-generated)

`include "bsg_defines.sv"
`timescale 1ns/1ps

module reg_1b #(
    parameter int width_p = 1
)(
    input  logic             clk_i
    ,input  logic             reset_i
    ,input  logic             en_i
    ,input  logic [width_p-1:0] data_i
    ,output logic [width_p-1:0] data_o
);

    bsg_dff_reset_en #(.width_p(width_p)
                      ,.reset_val_p(0)
                      )
      dff (.clk_i(clk_i)
          ,.reset_i(reset_i)
          ,.en_i(en_i)
          ,.data_i(data_i)
          ,.data_o(data_o)
          );

endmodule