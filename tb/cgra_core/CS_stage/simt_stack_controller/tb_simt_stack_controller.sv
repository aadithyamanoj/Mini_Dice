// =============================================================================
// Testbench: tb_simt_stack_controller.sv
// =============================================================================

`include "dice_define.vh"

module tb_simt_stack_controller;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  // Parameters
  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 1000;

  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1000 = 16'h1000;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1100 = 16'h1100;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1200 = 16'h1200;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1300 = 16'h1300;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1400 = 16'h1400;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1500 = 16'h1500;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1600 = 16'h1600;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1700 = 16'h1700;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1800 = 16'h1800;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc1900 = 16'h1900;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc2000 = 16'h2000;
  localparam logic [DICE_ADDR_WIDTH-1:0] Pc2100 = 16'h2100;

  localparam thread_mask_t MaskAll = 16'hFFFF;
  localparam thread_mask_t MaskT0T9 = 16'h03FF;
  localparam thread_mask_t MaskT10T15 = 16'hFC00;
  localparam thread_mask_t MaskT0T5 = 16'h003F;
  localparam thread_mask_t MaskT6T9 = 16'h03C0;
  localparam thread_mask_t MaskT10T12 = 16'h1C00;
  localparam thread_mask_t MaskT13T15 = 16'hE000;

  // Signals
  logic clk;
  logic rst;

  logic                       update_valid_i;
  logic                       update_with_divergence_i;
  logic [DICE_ADDR_WIDTH-1:0] update_next_pc_i;
  thread_mask_t               predicate_regs_value_i;
  logic [DICE_ADDR_WIDTH-1:0] branch_not_taken_pc_i;
  logic [DICE_ADDR_WIDTH-1:0] branch_reconvergence_pc_i;
  logic                       update_ready_o;

  // CTA controller init interface
  logic                       init_valid_i;
  logic [DICE_ADDR_WIDTH-1:0] init_pc_i;
  logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_i;
  logic [DICE_TID_WIDTH:0]    init_thread_count_i;
  logic                       init_ready_o;

  // Stack top and status outputs
  logic                       stack_top_valid_o;
  logic [DICE_ADDR_WIDTH-1:0] stack_top_next_pc_o;
  logic [DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_o;
  thread_mask_t               stack_top_active_mask_o;
  logic                       stack_empty_o;
  logic                       stack_full_o;

  int cycle_count;
  int error_count;

  // Clock and timeout
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $error("TIMEOUT");
        $finish;
      end
    end
  end

  // DUT
  simt_stack_controller u_dut (
      .clk_i                       (clk),
      .rst_i                       (rst),
      .update_valid_i              (update_valid_i),
      .update_with_divergence_i    (update_with_divergence_i),
      .update_next_pc_i            (update_next_pc_i),
      .predicate_regs_value_i      (predicate_regs_value_i),
      .branch_not_taken_pc_i       (branch_not_taken_pc_i),
      .branch_reconvergence_pc_i   (branch_reconvergence_pc_i),
      .update_ready_o              (update_ready_o),
      .init_valid_i                (init_valid_i),
      .init_pc_i                   (init_pc_i),
      .init_reconvergence_pc_i     (init_reconvergence_pc_i),
      .init_thread_count_i         (init_thread_count_i),
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

  // Tasks
  task automatic reset_dut();
    rst = 1'b1;

    update_valid_i            = 1'b0;
    update_with_divergence_i  = 1'b0;
    update_next_pc_i          = '0;
    predicate_regs_value_i    = '0;
    branch_not_taken_pc_i     = '0;
    branch_reconvergence_pc_i = '0;

    init_valid_i              = 1'b0;
    init_pc_i                 = '0;
    init_reconvergence_pc_i   = '0;
    init_thread_count_i       = '0;

    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic init_stack(
      input logic [DICE_ADDR_WIDTH-1:0] pc,
      input logic [DICE_ADDR_WIDTH-1:0] reconv_pc,
      input logic [DICE_TID_WIDTH:0]    thread_count
  );
    wait (init_ready_o == 1'b1);

    @(negedge clk);
    init_pc_i               = pc;
    init_reconvergence_pc_i = reconv_pc;
    init_thread_count_i     = thread_count;
    init_valid_i            = 1'b1;

    @(posedge clk);
    @(negedge clk);
    init_valid_i            = 1'b0;
    init_pc_i               = '0;
    init_reconvergence_pc_i = '0;
    init_thread_count_i     = '0;
  endtask

  task automatic update_stack(
      input logic                       with_divergence,
      input logic [DICE_ADDR_WIDTH-1:0] next_pc,
      input thread_mask_t               pred_mask,
      input logic [DICE_ADDR_WIDTH-1:0] not_taken_pc,
      input logic [DICE_ADDR_WIDTH-1:0] reconv_pc
  );
    wait (update_ready_o == 1'b1);

    @(negedge clk);
    update_with_divergence_i  = with_divergence;
    update_next_pc_i          = next_pc;
    predicate_regs_value_i    = pred_mask;
    branch_not_taken_pc_i     = not_taken_pc;
    branch_reconvergence_pc_i = reconv_pc;
    update_valid_i            = 1'b1;

    @(posedge clk);
    @(negedge clk);
    update_valid_i            = 1'b0;
    update_with_divergence_i  = 1'b0;
    update_next_pc_i          = '0;
    predicate_regs_value_i    = '0;
    branch_not_taken_pc_i     = '0;
    branch_reconvergence_pc_i = '0;

    @(posedge clk);
    wait (update_ready_o == 1'b1);
  endtask

  task automatic expect_stack_status(
      input logic  expected_empty,
      input logic  expected_full,
      input logic  expected_valid,
      input string label
  );
    assert (stack_empty_o == expected_empty)
      else begin
        error_count++;
        $error("%s: stack_empty_o mismatch: expected=%0b actual=%0b",
               label, expected_empty, stack_empty_o);
      end
    assert (stack_full_o == expected_full)
      else begin
        error_count++;
        $error("%s: stack_full_o mismatch: expected=%0b actual=%0b",
               label, expected_full, stack_full_o);
      end
    assert (stack_top_valid_o == expected_valid)
      else begin
        error_count++;
        $error("%s: stack_top_valid_o mismatch: expected=%0b actual=%0b",
               label, expected_valid, stack_top_valid_o);
      end
  endtask

  task automatic expect_stack_top(
      input logic [DICE_ADDR_WIDTH-1:0] expected_pc,
      input logic [DICE_ADDR_WIDTH-1:0] expected_reconvergence_pc,
      input thread_mask_t               expected_active_mask,
      input string                      label
  );
    wait (stack_top_valid_o == 1'b1);

    assert (stack_top_next_pc_o == expected_pc)
      else begin
        error_count++;
        $error("%s: stack_top_next_pc_o mismatch: expected=%h actual=%h",
               label, expected_pc, stack_top_next_pc_o);
      end
    assert (stack_top_reconvergence_pc_o == expected_reconvergence_pc)
      else begin
        error_count++;
        $error("%s: stack_top_reconvergence_pc_o mismatch: expected=%h actual=%h",
               label, expected_reconvergence_pc, stack_top_reconvergence_pc_o);
      end
    assert (stack_top_active_mask_o == expected_active_mask)
      else begin
        error_count++;
        $error("%s: stack_top_active_mask_o mismatch: expected=%h actual=%h",
               label, expected_active_mask, stack_top_active_mask_o);
      end
  endtask

  // Stimulus
  initial begin
    logic [DICE_ADDR_WIDTH-1:0] init_pc;
    logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc;
    logic [DICE_TID_WIDTH:0]    init_thread_count;

    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_simt_stack_controller, "+struct", "+mda");

    $display("tb_simt_stack_controller (nested divergence smoke)");

    reset_dut();

    error_count = 0;

    expect_stack_status(1'b1, 1'b0, 1'b0, "after reset");

    init_pc = Pc1000;
    init_reconvergence_pc = '1;
    init_thread_count = 5'd16;

    init_stack(init_pc, init_reconvergence_pc, init_thread_count);

    expect_stack_top(init_pc, init_reconvergence_pc, MaskAll, "after init");
    expect_stack_status(1'b0, 1'b0, 1'b1, "after init");

    update_stack(1'b0, Pc1100, '0, '0, '0);
    expect_stack_top(Pc1100, init_reconvergence_pc, MaskAll, "all threads at 0x1100");

    update_stack(1'b0, Pc1200, '0, '0, '0);
    expect_stack_top(Pc1200, init_reconvergence_pc, MaskAll, "all threads at 0x1200");

    update_stack(1'b1, Pc1400, MaskT10T15, Pc1300, Pc2000);
    expect_stack_top(Pc1300, Pc2000, MaskT0T9, "global divergence left path");

    update_stack(1'b1, Pc1600, MaskT6T9, Pc1500, Pc1900);
    expect_stack_top(Pc1500, Pc1900, MaskT0T5, "left nested path T0-T5");

    update_stack(1'b0, Pc1900, '0, '0, '0);
    expect_stack_top(Pc1600, Pc1900, MaskT6T9, "left nested path T6-T9");

    update_stack(1'b0, Pc1900, '0, '0, '0);
    expect_stack_top(Pc1900, Pc2000, MaskT0T9, "left reconvergence at 0x1900");

    update_stack(1'b0, Pc2000, '0, '0, '0);
    expect_stack_top(Pc1400, Pc2000, MaskT10T15, "global divergence right path");

    update_stack(1'b1, Pc1800, MaskT13T15, Pc1700, Pc2000);
    expect_stack_top(Pc1700, Pc2000, MaskT10T12, "right nested path T10-T12");

    update_stack(1'b0, Pc2000, '0, '0, '0);
    expect_stack_top(Pc1800, Pc2000, MaskT13T15, "right nested path T13-T15");

    update_stack(1'b0, Pc2000, '0, '0, '0);
    expect_stack_top(Pc2000, Pc2000, MaskT10T15, "right reconvergence at 0x2000");

    update_stack(1'b0, Pc2000, '0, '0, '0);
    expect_stack_top(Pc2000, init_reconvergence_pc, MaskAll, "global reconvergence at 0x2000");

    update_stack(1'b0, Pc2100, '0, '0, '0);
    expect_stack_top(Pc2100, init_reconvergence_pc, MaskAll, "all threads continue to 0x2100");

    if (error_count == 0) begin
      $display("PASS: nested divergence DAG");
    end else begin
      $display("FAIL: nested divergence DAG completed with %0d error(s)", error_count);
    end
    $finish;
  end

endmodule
