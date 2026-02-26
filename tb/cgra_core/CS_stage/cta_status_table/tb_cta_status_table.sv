// =============================================================================
// Testbench: tb_cta_status_table.sv
// Tests bitmap-gated branch_predict updates + clear path
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_cta_status_table;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 500;

  logic clk;
  logic rst;

  branch_predict_interface_t                                 branch_predict_info_i;
  logic                                                      branch_predict_info_we_i;
  block_retire_status_t                                      brt_info_i;
  logic                                                      clear_entry_valid_i;
  logic                      [     DICE_HW_CTA_ID_WIDTH-1:0] clear_entry_hw_id_i;
  dice_cta_status_t          [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_o;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  cta_status_table u_dut (
      .clk_i                   (clk),
      .rst_i                   (rst),
      .branch_predict_info_i   (branch_predict_info_i),
      .branch_predict_info_we_i(branch_predict_info_we_i),
      .brt_info_i              (brt_info_i),
      .clear_entry_valid_i     (clear_entry_valid_i),
      .clear_entry_hw_id_i     (clear_entry_hw_id_i),
      .cta_status_o            (cta_status_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst                      = 1'b1;
    branch_predict_info_i    = '0;
    branch_predict_info_we_i = 1'b0;
    brt_info_i               = '0;
    clear_entry_valid_i      = 1'b0;
    clear_entry_hw_id_i      = '0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  // -------------------------------------------------------
  // Helper: pulse a branch-predict write for one cycle
  // -------------------------------------------------------
  task automatic bp_write(
    input logic [DICE_HW_CTA_ID_WIDTH-1:0] cta_id,
    input logic [2:0]                       bitmap,
    input logic                             ucd,
    input logic [DICE_ADDR_WIDTH-1:0]       pc,
    input logic                             ret
  );
    branch_predict_info_i.hw_cta_id                    = cta_id;
    branch_predict_info_i.valid_edits_bitmap            = bitmap;
    branch_predict_info_i.unresolved_control_divergence = ucd;
    branch_predict_info_i.predict_pc                    = pc;
    branch_predict_info_i.is_return                     = ret;
    branch_predict_info_we_i = 1'b1;
    @(posedge clk);
    branch_predict_info_we_i = 1'b0;
  endtask

  initial begin
    logic [DICE_ADDR_WIDTH-1:0] predict_pc;

    $display("tb_cta_status_table – bitmap-gated tests");

    // ==========================================================
    // TEST 1: Full bitmap (3'b111) — all fields written
    // ==========================================================
    reset_dut();
    predict_pc = 32'hABCD_0000;
    brt_info_i.hw_cta_pending[0] = 1'b1;

    bp_write(.cta_id('0), .bitmap(3'b111),
             .ucd(1'b1), .pc(predict_pc), .ret(1'b1));

    @(posedge clk);
    assert (cta_status_o[0].unresolved_control_divergence == 1'b1)
      else $fatal(1, "T1: unresolved_control_divergence not set");
    assert (cta_status_o[0].predict_pc == predict_pc)
      else $fatal(1, "T1: predict_pc mismatch");
    assert (cta_status_o[0].is_return == 1'b1)
      else $fatal(1, "T1: is_return not set");
    assert (cta_status_o[0].has_pending_eblock == 1'b1)
      else $fatal(1, "T1: has_pending_eblock not set");

    // Clear entry
    brt_info_i.hw_cta_pending[0] = 1'b0;
    clear_entry_valid_i = 1'b1;
    clear_entry_hw_id_i = '0;
    @(posedge clk);
    clear_entry_valid_i = 1'b0;

    @(posedge clk);
    assert (cta_status_o[0].unresolved_control_divergence == 1'b0)
      else $fatal(1, "T1: unresolved_control_divergence not cleared");
    assert (cta_status_o[0].predict_pc == '0)
      else $fatal(1, "T1: predict_pc not cleared");
    assert (cta_status_o[0].is_return == 1'b0)
      else $fatal(1, "T1: is_return not cleared");
    assert (cta_status_o[0].has_pending_eblock == 1'b0)
      else $fatal(1, "T1: has_pending_eblock not cleared");

    $display("PASS: T1 – full bitmap write + clear");

    // ==========================================================
    // TEST 2: Zero bitmap (3'b000) — no fields change
    // ==========================================================
    reset_dut();

    // First set known values via full bitmap
    bp_write(.cta_id('0), .bitmap(3'b111),
             .ucd(1'b1), .pc(32'h1111_0000), .ret(1'b1));
    @(posedge clk);

    // Now write with bitmap=000 and different data — nothing should change
    bp_write(.cta_id('0), .bitmap(3'b000),
             .ucd(1'b0), .pc(32'hDEAD_BEEF), .ret(1'b0));
    @(posedge clk);

    assert (cta_status_o[0].unresolved_control_divergence == 1'b1)
      else $fatal(1, "T2: ucd changed on bitmap=000");
    assert (cta_status_o[0].predict_pc == 32'h1111_0000)
      else $fatal(1, "T2: predict_pc changed on bitmap=000");
    assert (cta_status_o[0].is_return == 1'b1)
      else $fatal(1, "T2: is_return changed on bitmap=000");

    $display("PASS: T2 – zero bitmap, no fields changed");

    // ==========================================================
    // TEST 3: Selective bitmap — only is_return (3'b001)
    // ==========================================================
    reset_dut();

    // Seed all fields
    bp_write(.cta_id('0), .bitmap(3'b111),
             .ucd(1'b1), .pc(32'hAAAA_0000), .ret(1'b0));
    @(posedge clk);

    // Update only is_return
    bp_write(.cta_id('0), .bitmap(3'b001),
             .ucd(1'b0), .pc(32'hBBBB_0000), .ret(1'b1));
    @(posedge clk);

    assert (cta_status_o[0].is_return == 1'b1)
      else $fatal(1, "T3: is_return not updated");
    assert (cta_status_o[0].unresolved_control_divergence == 1'b1)
      else $fatal(1, "T3: ucd should be unchanged");
    assert (cta_status_o[0].predict_pc == 32'hAAAA_0000)
      else $fatal(1, "T3: predict_pc should be unchanged");

    $display("PASS: T3 – selective bitmap 001 (is_return only)");

    // ==========================================================
    // TEST 4: Selective bitmap — only predict_pc (3'b010)
    // ==========================================================
    reset_dut();

    bp_write(.cta_id('0), .bitmap(3'b111),
             .ucd(1'b1), .pc(32'hCCCC_0000), .ret(1'b1));
    @(posedge clk);

    bp_write(.cta_id('0), .bitmap(3'b010),
             .ucd(1'b0), .pc(32'hDDDD_0000), .ret(1'b0));
    @(posedge clk);

    assert (cta_status_o[0].predict_pc == 32'hDDDD_0000)
      else $fatal(1, "T4: predict_pc not updated");
    assert (cta_status_o[0].unresolved_control_divergence == 1'b1)
      else $fatal(1, "T4: ucd should be unchanged");
    assert (cta_status_o[0].is_return == 1'b1)
      else $fatal(1, "T4: is_return should be unchanged");

    $display("PASS: T4 – selective bitmap 010 (predict_pc only)");

    // ==========================================================
    // TEST 5: Selective bitmap — only ucd (3'b100)
    // ==========================================================
    reset_dut();

    bp_write(.cta_id('0), .bitmap(3'b111),
             .ucd(1'b0), .pc(32'hEEEE_0000), .ret(1'b1));
    @(posedge clk);

    bp_write(.cta_id('0), .bitmap(3'b100),
             .ucd(1'b1), .pc(32'hFFFF_0000), .ret(1'b0));
    @(posedge clk);

    assert (cta_status_o[0].unresolved_control_divergence == 1'b1)
      else $fatal(1, "T5: ucd not updated");
    assert (cta_status_o[0].predict_pc == 32'hEEEE_0000)
      else $fatal(1, "T5: predict_pc should be unchanged");
    assert (cta_status_o[0].is_return == 1'b1)
      else $fatal(1, "T5: is_return should be unchanged");

    $display("PASS: T5 – selective bitmap 100 (ucd only)");

    // ==========================================================
    $display("ALL TESTS PASSED");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_cta_status_table.vcd");
    $dumpvars(0, tb_cta_status_table);
  end
`endif

endmodule
