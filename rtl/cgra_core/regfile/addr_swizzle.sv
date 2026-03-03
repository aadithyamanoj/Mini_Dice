`include "DE_pkg.sv"
`include "dice_pkg.sv"
module addr_swizzle 
import DE_pkg::*;
import dice_pkg::*;

#(
      parameter WIDTH =  DICE_ADDR_WIDTH
    , parameter NUM_BANK = DICE_NUM_BANKS
    , parameter DEPTH = DICE_NUM_REGS
    , parameter ADDR_WIDTH = $clog2(WIDTH)
)
(
      input reg_rd_cmd rd_cmd
    , output logic [$clog2(NUM_BANK)-1:0] bank_sel
    , output logic [DICE_TID_WIDTH-1:0] rs
);

    assign bank_sel = (rd_cmd.tid[4:0] + rd_cmd.rs[4:0]) & 5'h1F; // (t+r)%32
    // pick which register to read from in the bank
    assign rs = rd_cmd.tid;

endmodule
