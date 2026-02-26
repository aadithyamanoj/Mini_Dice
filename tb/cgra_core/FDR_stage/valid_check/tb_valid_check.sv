// =============================================================================
// Testbench: tb_valid_check.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_valid_check;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 200;

  logic clk;
  logic rst;
  int cycle_count;

  // DUT I/O
  logic barrier_indicator_i;
  logic decode_done_i;
  logic [DICE_ADDR_WIDTH-1:0] eblock_pc_i;
  logic prefetch_block_i;
  logic [DICE_ADDR_WIDTH-1:0] simt_stack_pc_i;
  logic bitstream_loaded_i;
  logic unresolved_div_i;
  logic barrier_complete_i;
  logic prefetch_cleared_i;
  logic ex_ready_i;
  logic fdr_valid_o;
  logic fire_eblock_o;
  logic clear_prefetch_o;
  logic predict_miss_o;

  valid_check u_dut (
      .barrier_indicator_i(barrier_indicator_i),
      .decode_done_i      (decode_done_i),
      .eblock_pc_i        (eblock_pc_i),
      .prefetch_block_i   (prefetch_block_i),
      .simt_stack_pc_i    (simt_stack_pc_i),
      .bitstream_loaded_i (bitstream_loaded_i),
      .unresolved_div_i   (unresolved_div_i),
      .barrier_complete_i (barrier_complete_i),
      .prefetch_cleared_i (prefetch_cleared_i),
      .fdr_valid_o        (fdr_valid_o),
      .ex_ready_i         (ex_ready_i),
      .fire_eblock_o      (fire_eblock_o),
      .clear_prefetch_o   (clear_prefetch_o),
      .predict_miss_o     (predict_miss_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  task automatic reset_inputs();
    rst = 1'b1;
    barrier_indicator_i = 1'b0;
    decode_done_i       = 1'b0;
    eblock_pc_i         = '0;
    prefetch_block_i    = 1'b0;
    simt_stack_pc_i     = '0;
    bitstream_loaded_i  = 1'b0;
    unresolved_div_i    = 1'b0;
    barrier_complete_i  = 1'b0;
    prefetch_cleared_i  = 1'b0;
    ex_ready_i          = 1'b0;
    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    $display("tb_valid_check (happy-path)");

    reset_inputs();

    eblock_pc_i        = 32'h0000_1000;
    simt_stack_pc_i    = 32'h0000_1000;
    bitstream_loaded_i = 1'b1;
    decode_done_i      = 1'b1;
    barrier_indicator_i = 1'b0;
    prefetch_block_i    = 1'b0;
    unresolved_div_i    = 1'b0;
    barrier_complete_i  = 1'b1;
    prefetch_cleared_i  = 1'b0;
    ex_ready_i          = 1'b1;
    #1;

    assert (fdr_valid_o == 1'b1)
      else $fatal(1, "fdr_valid_o not asserted");
    assert (fire_eblock_o == 1'b1)
      else $fatal(1, "fire_eblock_o not asserted");
    assert (predict_miss_o == 1'b0)
      else $fatal(1, "predict_miss_o should be 0");
    assert (clear_prefetch_o == 1'b0)
      else $fatal(1, "clear_prefetch_o should be 0");

    $display("PASS: valid_check outputs");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

endmodule
