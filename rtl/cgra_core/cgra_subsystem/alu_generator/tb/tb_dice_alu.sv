`timescale 1ns/1ps
module tb_dice_alu;

  logic clk;
  logic [31:0] in0, in1, in2;
  logic        in3;
  logic [31:0] opcode;
  logic [31:0] out0;

  // Clock
  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // DUT
  dice_alu dut (
    .clk(clk),
    .in0(in0),
    .in1(in1),
    .in2(in2),
    .in3(in3),
    .opcode(opcode),
    .out0(out0),
    .out1() // unused
  );

  import dice_alu_pkg::*;

  initial begin
    // init
    in0 = 0; in1 = 0; in2 = 0; in3 = 0; opcode = 0;
    repeat (5) @(posedge clk);

    // --- ADD ---
    opcode = OPCODE_ADD_U32;
    in0 = 10; in1 = 20;
    @(posedge clk);
    #1;
    if (out0 !== 30)
      $error("ADD failed: got %0d expected %0d", out0, 30);
    else
      $display("ADD passed");

    // --- MAD (4-stage pipeline) ---
    opcode = OPCODE_MAD_U32;
    in0 = 2; in1 = 3; in2 = 4;
    repeat (2) @(posedge clk); // wait pipeline latency
    #1;
    if (out0 !== 10)
      $error("MAD failed: got %0d expected %0d", out0, 10);
    else
      $display("MAD passed");

    $display("✅ All tests done.");
    $finish;
  end

  initial begin
    $dumpfile("tb_dice_alu.vcd");
    $dumpvars(0, tb_dice_alu);
`ifdef XCELIUM
    $recordfile("tb_dice_alu.trn");
    $recordvars("");
`endif
  end

endmodule
