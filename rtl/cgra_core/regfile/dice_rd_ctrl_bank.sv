`include "DE_pkg.sv"
`include "dice_pkg.sv"




module dice_rd_ctrl_bank
import DE_pkg::*;
import dice_pkg::*;
#
(
      parameter WIDTH =  32
    , parameter DEPTH = 512
    , parameter ADDR_WIDTH = $clog2(DEPTH)
)

(
      input logic clk_i
    , input logic reset_i

    , input logic [WIDTH-1:0] reg_data_i

    // , input logic [WIDTH-1:0] fw_data_i
    // , input logic             fw_valid_i


    , output logic [WIDTH-1:0] data_o
);

    // assign data_o = fw_valid_i ? fw_data_i : reg_data_i;
    assign data_o = reg_data_i;

endmodule
