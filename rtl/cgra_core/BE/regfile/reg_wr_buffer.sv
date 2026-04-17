`include "DE_pkg.sv"
`include "dice_pkg.sv"

module reg_wr_buffer

  import DE_pkg::*;
  import dice_pkg::*;
#(
      parameter int WIDTH      = $bits(reg_wr_cmd)
    , parameter int ADDR_WIDTH = $clog2(512)
    , parameter int DEPTH      = LDST_BUF_DEPTH
) (
      input logic clk_i
    , input logic reset_i

    , input reg_wr_cmd wr_i
    , input logic      pop_i
    , input logic      valid_i

    , output logic full_o
    , output logic empty_o

    , output reg_wr_cmd cmd_o
    , output logic      wb_valid_o
);

  logic ready_lo;
  logic [WIDTH-1:0] data_li, data_lo;

  assign data_li = wr_i;

  bsg_fifo_1r1w_small #(
      .width_p(WIDTH),
      .els_p(DEPTH)
  ) wr_buf (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .v_i(valid_i),
      .ready_o(ready_lo),
      .data_i(data_li),
      .v_o(wb_valid_o),
      .data_o(data_lo),
      .yumi_i(pop_i)
  );

  assign full_o = ~ready_lo;
  assign cmd_o = data_lo;
  assign empty_o = ~wb_valid_o;

endmodule
