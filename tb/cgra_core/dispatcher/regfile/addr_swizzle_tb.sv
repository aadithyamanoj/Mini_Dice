// `timescale 1ns/1ps
`include "DE_pkg.sv"
`include "dice_pkg.sv"

module addr_swizzle_tb;

import DE_pkg::*;
import dice_pkg::*;

  initial begin
    $fsdbDumpfile("addr_swizzle_tb.fsdb");
    $fsdbDumpvars("+all");
  end

  // parameters (should match DUT)
  localparam NUM_BANK = 32;

  // Declare reg_rd_cmd structure from package
  reg_rd_cmd rd_cmd;
  logic [$clog2(NUM_BANK)-1:0] bank_sel;
  logic [DICE_TID_WIDTH-1:0] rs;

  // Expected values
  logic [$clog2(NUM_BANK)-1:0] expected_bank_sel;

  // DUT instance
  addr_swizzle dut (
      .rd_cmd(rd_cmd),
      .bank_sel(bank_sel),
      .rs(rs)
  );

  initial begin
    $display("=== addr_swizzle Testbench Start ===");

    // loop through some test cases
    for (int i = 0; i < 10; i++) begin
      rd_cmd.tid = $urandom_range(0, 511);  // assuming 9-bit TID width
      rd_cmd.rs = $urandom_range(0, 31);   // assuming 5-bit register index

      //#1; // small delay for combinational logic to settle

      expected_bank_sel = (rd_cmd.tid[4:0] + rd_cmd.rs[4:0]) & 5'h1F;

      if (bank_sel !== expected_bank_sel) begin
        $display("Mismatch at test %0d: tid=%0d reg=%0d -> got bank_sel=%0d, expected=%0d",
               i, rd_cmd.tid, rd_cmd.rs, bank_sel, expected_bank_sel);
      end else begin
        $display("PASS: tid=%0d reg=%0d -> bank_sel=%0d", rd_cmd.tid, rd_cmd.rs, bank_sel);
      end
    end

    $display("=== addr_swizzle Testbench Complete ===");
    $finish;
  end
  


endmodule
