// =============================================================================
// Testbench: tb_branch_handler.sv
// =============================================================================

`timescale 1ns / 1ps

module tb_branch_handler;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 500;

  logic clk;
  logic rst;
  int cycle_count;

  branch_meta_t branch_meta;
  logic         branch_meta_valid;
  thread_mask_t real_active_thread_mask;
  cta_size_e    cta_size;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_id;
  thread_mask_t cs_active_mask;
  logic [DICE_ADDR_WIDTH-1:0] pc;

  logic update_valid;
  logic update_ready;
  simt_stack_update_t simt_stack_update;

  branch_predict_interface_t branch_predict_info;
  logic                      branch_predict_info_we;
  assign branch_predict_info_we = |branch_predict_info.valid_edits_bitmap;

  block_retire_status_t brt_info;
  logic                            clear_entry_valid;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] clear_entry_hw_id;
  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status;

  branch_handler_no_branches u_dut (
      .clk_i                    (clk),
      .rst_i                    (rst),
      .branch_predict_info_o    (branch_predict_info),
      .branch_meta_i            (branch_meta),
      .branch_meta_valid_i      (branch_meta_valid),
      .real_active_thread_mask_o(real_active_thread_mask),
      .cta_size_i               (cta_size),
      .hw_cta_id_i              (hw_cta_id),
      .cs_active_mask_i         (cs_active_mask),
      .pc_i                     (pc),
      .update_valid_o           (update_valid),
      .update_ready_i           (update_ready),
      .simt_stack_update_o      (simt_stack_update)
  );

  cta_status_table u_cta_status_table (
      .clk_i                   (clk),
      .rst_i                   (rst),
      .branch_predict_info_i   (branch_predict_info),
      .branch_predict_info_we_i(branch_predict_info_we),
      .brt_info_i              (brt_info),
      .clear_entry_valid_i     (clear_entry_valid),
      .clear_entry_hw_id_i     (clear_entry_hw_id),
      .cta_status_o            (cta_status)
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

  task automatic reset_dut();
    rst               = 1'b1;
    branch_meta       = '0;
    branch_meta_valid = 1'b0;
    cta_size          = CTA_SIZE_1;
    hw_cta_id         = '0;
    cs_active_mask    = {DICE_NUM_MAX_THREADS_PER_CORE{1'b1}};
    pc                = 32'h0000_1000;
    update_ready      = 1'b1;
    brt_info          = '0;
    clear_entry_valid = 1'b0;
    clear_entry_hw_id = '0;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic send_branch_meta(input logic is_return_i, input logic branch_ena_i);
    branch_meta = '0;
    branch_meta.is_return = is_return_i;
    branch_meta.branch_ena = branch_ena_i;
    branch_meta_valid = 1'b0;
    @(posedge clk);
    branch_meta_valid = 1'b1;
    @(posedge clk);
    branch_meta_valid = 1'b0;
  endtask

  task automatic expect_non_return_flow();
    int update_valid_count;
    int status_we_count;
    update_valid_count = 0;
    status_we_count = 0;

    fork
      begin
        repeat (12) begin
          @(posedge clk);
          if (update_valid) update_valid_count++;
          if (branch_predict_info_we) status_we_count++;
        end
      end
      begin
        send_branch_meta(1'b0, 1'b0);
      end
    join

    assert (update_valid_count == 1)
      else $fatal(1, "Expected one SIMT update for non-return, got %0d", update_valid_count);
    assert (status_we_count == 0)
      else $fatal(1, "Expected zero status writes for non-return, got %0d", status_we_count);
    assert (cta_status[hw_cta_id].is_return == 1'b0)
      else $fatal(1, "CTA status unexpectedly marked return for non-return");
  endtask

  task automatic expect_return_flow();
    int status_we_count;
    status_we_count = 0;

    fork
      begin
        repeat (12) begin
          @(posedge clk);
          if (branch_predict_info_we) begin
            status_we_count++;
            assert (branch_predict_info.valid_edits_bitmap == 3'b001)
              else $fatal(1, "Unexpected valid_edits_bitmap: %b", branch_predict_info.valid_edits_bitmap);
            assert (branch_predict_info.is_return == 1'b1)
              else $fatal(1, "is_return was not asserted during status write");
          end
        end
      end
      begin
        send_branch_meta(1'b1, 1'b0);
      end
    join

    assert (status_we_count == 1)
      else $fatal(1, "Expected one status write for return, got %0d", status_we_count);
    assert (cta_status[hw_cta_id].is_return == 1'b1)
      else $fatal(1, "CTA status table did not capture return bit");
  endtask

  task automatic trigger_illegal_branch_assertion();
    $display("Driving illegal branch_ena=1. DUT assertion is expected to fire.");
    send_branch_meta(1'b0, 1'b1);
  endtask

  initial begin
    $display("tb_branch_handler");

    reset_dut();
    expect_non_return_flow();
    expect_return_flow();

    if ($test$plusargs("RUN_ASSERT_NEG")) begin
      trigger_illegal_branch_assertion();
      repeat (6) @(posedge clk);
      $fatal(1, "Expected DUT assertion to fire for illegal branch_ena stimulus");
    end

    $display("PASS: branch_handler_no_branches directed checks completed");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_branch_handler.vcd");
    $dumpvars(0, tb_branch_handler);
  end
`endif

endmodule
