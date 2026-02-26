// =============================================================================
// Testbench: tb_simt_stack.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_simt_stack;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ThreadWidth = DICE_NUM_MAX_THREADS_PER_CORE / DICE_NUM_MAX_CTA_PER_CORE;
  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 500;

  logic clk;
  logic rst;

  logic                                 push_i;
  logic                                 modify_top_i;
  logic [DICE_ADDR_WIDTH-1:0]           push_next_pc_i;
  logic [DICE_ADDR_WIDTH-1:0]           push_reconvergence_pc_i;
  logic [ThreadWidth-1:0]               push_active_mask_i;

  logic                                 pop_i;
  logic                                 read_top_i;

  logic [DICE_ADDR_WIDTH-1:0]           top_next_pc_o;
  logic [DICE_ADDR_WIDTH-1:0]           top_reconvergence_pc_o;
  logic [ThreadWidth-1:0]               top_active_mask_o;
  logic                                 out_valid_o;

  logic                                 stack_empty_o;
  logic                                 stack_full_o;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  simt_stack u_dut (
      .clk_i                  (clk),
      .rst_i                  (rst),
      .push_i                 (push_i),
      .modify_top_i           (modify_top_i),
      .push_next_pc_i         (push_next_pc_i),
      .push_reconvergence_pc_i(push_reconvergence_pc_i),
      .push_active_mask_i     (push_active_mask_i),
      .pop_i                  (pop_i),
      .read_top_i             (read_top_i),
      .top_next_pc_o          (top_next_pc_o),
      .top_reconvergence_pc_o (top_reconvergence_pc_o),
      .top_active_mask_o      (top_active_mask_o),
      .out_valid_o            (out_valid_o),
      .stack_empty_o          (stack_empty_o),
      .stack_full_o           (stack_full_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst = 1'b1;
    push_i = 1'b0;
    modify_top_i = 1'b0;
    push_next_pc_i = '0;
    push_reconvergence_pc_i = '0;
    push_active_mask_i = '0;
    pop_i = 1'b0;
    read_top_i = 1'b0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    logic [DICE_ADDR_WIDTH-1:0] pc;
    logic [DICE_ADDR_WIDTH-1:0] reconv;
    logic [ThreadWidth-1:0] mask;

    $display("tb_simt_stack (happy-path)");

    reset_dut();

    pc = 32'h0000_1000;
    reconv = 32'h0000_2000;
    mask = {ThreadWidth{1'b1}};

    // Push one entry
    push_next_pc_i = pc;
    push_reconvergence_pc_i = reconv;
    push_active_mask_i = mask;
    push_i = 1'b1;
    @(posedge clk);
    push_i = 1'b0;

    // Read top (out_valid asserted one cycle after read_top)
    read_top_i = 1'b1;
    @(posedge clk);
    read_top_i = 1'b0;
    @(posedge clk);

    assert (out_valid_o == 1'b1)
      else $fatal(1, "out_valid_o not asserted");
    assert (top_next_pc_o == pc)
      else $fatal(1, "top_next_pc_o mismatch");
    assert (top_reconvergence_pc_o == reconv)
      else $fatal(1, "top_reconvergence_pc_o mismatch");

    $display("PASS: push -> read top");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_simt_stack.vcd");
    $dumpvars(0, tb_simt_stack);
  end
`endif

endmodule
