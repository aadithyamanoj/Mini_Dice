// =============================================================================
// Testbench: tb_cta_schedule_stage.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_cta_schedule_stage;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 2000;

  logic clk;
  logic rst;

  // Interface Instances
  cta_if               cta_if_inst();
  cta_sched_if         schedule_if();
  simt_stack_status_entry_t simt_status;

  // Additional inputs (not in interfaces)
  logic                       eblock_commit_valid_i;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i;
  logic                       eblock_flush_valid_i;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i;
  branch_predict_interface_t  bh_branch_predict_info_i;
  logic                       bh_branch_predict_info_we_i;
  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_data_o;
  block_retire_status_t       brt_info_i;
  logic                       brt_info_write_enable_i;
  logic                       simt_update_valid_i;
  logic                       simt_update_ready_o;
  simt_stack_update_t         simt_update_stack_data_i;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] simt_update_hw_cta_id_i;
  cta_size_e                  simt_update_hw_cta_size_i;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  // DUT Instantiation
  cta_schedule_stage u_dut (
      .clk_i                  (clk),
      .rst_i                  (rst),
      .cta_if_inst            (cta_if_inst),
      .schedule_if            (schedule_if),
      .eblock_commit_valid_i  (eblock_commit_valid_i),
      .eblock_commit_id_i     (eblock_commit_id_i),
      .eblock_flush_valid_i   (eblock_flush_valid_i),
      .eblock_flush_id_i      (eblock_flush_id_i),
      .bh_branch_predict_info_i(bh_branch_predict_info_i),
      .bh_branch_predict_info_we_i(bh_branch_predict_info_we_i),
      .cta_status_data_o      (cta_status_data_o),
      .brt_info_i             (brt_info_i),
      .brt_info_write_enable_i(brt_info_write_enable_i),
      .simt_update_valid_i    (simt_update_valid_i),
      .simt_update_ready_o    (simt_update_ready_o),
      .simt_update_stack_data_i(simt_update_stack_data_i),
      .simt_update_hw_cta_id_i(simt_update_hw_cta_id_i),
      .simt_update_hw_cta_size_i(simt_update_hw_cta_size_i),
      .simt_status_o          (simt_status)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst = 1'b1;

    cta_if_inst.dispatch_valid = 1'b0;
    cta_if_inst.dispatch_data  = '0;

    cta_if_inst.complete_ready = 1'b1;
    schedule_if.ready = 1'b0;

    eblock_commit_valid_i = 1'b0;
    eblock_commit_id_i    = '0;
    eblock_flush_valid_i  = 1'b0;
    eblock_flush_id_i     = '0;

    bh_branch_predict_info_we_i = 1'b0;
    bh_branch_predict_info_i    = '0;

    brt_info_i = '0;
    brt_info_write_enable_i = 1'b0;

    simt_update_valid_i       = 1'b0;
    simt_update_hw_cta_id_i   = '0;
    simt_update_hw_cta_size_i = CTA_SIZE_1;
    simt_update_stack_data_i  = '0;

    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    dice_cta_desc_t desc;
    logic [DICE_ADDR_WIDTH-1:0] start_pc;

    $display("tb_cta_schedule_stage (happy-path)");

    reset_dut();

    // Build a minimal CTA descriptor
    start_pc = 32'h0000_1000;
    desc = '0;
    desc.kernel_desc.start_pc = start_pc;
    desc.kernel_desc.cta_size.x = 1;
    desc.kernel_desc.cta_size.y = 1;
    desc.kernel_desc.cta_size.z = 1;
    desc.cta_id.x = '0;
    desc.cta_id.y = '0;
    desc.cta_id.z = '0;

    // Dispatch a single CTA when ready
    wait (cta_if_inst.dispatch_ready == 1'b1);
    cta_if_inst.dispatch_data  = desc;
    cta_if_inst.dispatch_valid = 1'b1;
    @(posedge clk);
    cta_if_inst.dispatch_valid = 1'b0;

    // Wait for SIMT stack to report valid before checking schedule output
    wait (simt_status.valid == 1'b1);

    // Wait for a scheduled eblock and check expected fields
    wait (schedule_if.valid == 1'b1);
    assert (schedule_if.data.schedule_next_pc == start_pc)
      else $fatal(1, "schedule_next_pc mismatch");
    assert (schedule_if.data.schedule_hw_cta_id == '0)
      else $fatal(1, "schedule_hw_cta_id mismatch");

    // Complete handshake
    schedule_if.ready = 1'b1;
    @(posedge clk);

    $display("PASS: scheduled one CTA");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_cta_schedule_stage.vcd");
    $dumpvars(0, tb_cta_schedule_stage);
  end
`endif

endmodule
