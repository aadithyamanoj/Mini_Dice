// =============================================================================
// Testbench: tb_simt_stack_controller.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_simt_stack_controller;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int NumStack = DICE_NUM_MAX_CTA_PER_CORE;
  localparam int ThreadWidth = DICE_NUM_MAX_THREADS_PER_CORE / DICE_NUM_MAX_CTA_PER_CORE;
  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 1000;

  logic clk;
  logic rst;

  // Branch handler interface
  logic [$clog2(NumStack)-1:0] hw_cta_id_i;
  cta_size_e                   hw_cta_size_i;
  logic                        update_valid_i;
  logic                        update_ready_o;
  logic                        update_with_divergence_i;
  logic [DICE_ADDR_WIDTH-1:0]  update_next_pc_i;
  thread_mask_t                predicate_regs_value_i;
  logic [DICE_ADDR_WIDTH-1:0]  branch_not_taken_pc_i;
  logic [DICE_ADDR_WIDTH-1:0]  branch_reconvergence_pc_i;

  // CTA controller interface
  logic                        init_valid_i;
  logic [$clog2(NumStack)-1:0] init_hw_cta_id_i;
  cta_size_e                   init_hw_cta_size_i;
  logic [DICE_ADDR_WIDTH-1:0]  init_pc_i;
  logic [DICE_ADDR_WIDTH-1:0]  init_reconvergence_pc_i;
  logic                        init_ready_o;

  // Stack outputs
  logic [NumStack-1:0] stack_top_valid_o;
  logic [NumStack-1:0][DICE_ADDR_WIDTH-1:0] stack_top_next_pc_o;
  logic [NumStack-1:0][DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_o;
  logic [NumStack-1:0][ThreadWidth-1:0] stack_top_active_mask_o;
  logic [NumStack-1:0] stack_empty_o;
  logic [NumStack-1:0] stack_full_o;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  simt_stack_controller u_dut (
      .clk_i                       (clk),
      .rst_i                       (rst),
      .hw_cta_id_i                 (hw_cta_id_i),
      .hw_cta_size_i               (hw_cta_size_i),
      .update_valid_i              (update_valid_i),
      .update_with_divergence_i    (update_with_divergence_i),
      .update_next_pc_i            (update_next_pc_i),
      .predicate_regs_value_i      (predicate_regs_value_i),
      .branch_not_taken_pc_i       (branch_not_taken_pc_i),
      .branch_reconvergence_pc_i   (branch_reconvergence_pc_i),
      .update_ready_o              (update_ready_o),
      .init_valid_i                (init_valid_i),
      .init_hw_cta_id_i            (init_hw_cta_id_i),
      .init_hw_cta_size_i          (init_hw_cta_size_i),
      .init_pc_i                   (init_pc_i),
      .init_reconvergence_pc_i     (init_reconvergence_pc_i),
      .init_ready_o                (init_ready_o),
      .stack_top_valid_o           (stack_top_valid_o),
      .stack_top_next_pc_o         (stack_top_next_pc_o),
      .stack_top_reconvergence_pc_o(stack_top_reconvergence_pc_o),
      .stack_top_active_mask_o     (stack_top_active_mask_o),
      .stack_empty_o               (stack_empty_o),
      .stack_full_o                (stack_full_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst = 1'b1;
    hw_cta_id_i               = '0;
    hw_cta_size_i             = CTA_SIZE_1;
    update_valid_i            = 1'b0;
    update_with_divergence_i  = 1'b0;
    update_next_pc_i          = '0;
    predicate_regs_value_i    = '0;
    branch_not_taken_pc_i     = '0;
    branch_reconvergence_pc_i = '0;
    init_valid_i              = 1'b0;
    init_hw_cta_id_i          = '0;
    init_hw_cta_size_i        = CTA_SIZE_1;
    init_pc_i                 = '0;
    init_reconvergence_pc_i   = '0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    logic [DICE_ADDR_WIDTH-1:0] init_pc;

    $display("tb_simt_stack_controller (happy-path)");

    reset_dut();

    init_pc = 32'h0000_1000;

    // Issue init for CTA 0
    wait (init_ready_o == 1'b1);
    init_hw_cta_id_i        = '0;
    init_hw_cta_size_i      = CTA_SIZE_1;
    init_pc_i               = init_pc;
    init_reconvergence_pc_i = 32'hFFFF_FFFF;
    init_valid_i            = 1'b1;
    @(posedge clk);
    init_valid_i            = 1'b0;

    // Wait for stack top to become valid
    wait (stack_top_valid_o[0] == 1'b1);
    assert (stack_top_next_pc_o[0] == init_pc)
      else $fatal(1, "stack_top_next_pc_o mismatch");

    $display("PASS: init -> stack top valid");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_simt_stack_controller.vcd");
    $dumpvars(0, tb_simt_stack_controller);
  end
`endif

endmodule
