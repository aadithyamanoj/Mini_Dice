// =============================================================================
// Testbench: tb_cta_controller.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_cta_controller;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 500;

  logic clk;
  logic rst;

  // Interfaces
  cta_dispatch_if dispatch_if();
  cta_complete_if complete_if();

  // Active CTA table interface
  logic                                             pop_valid_o;
  logic             [     DICE_HW_CTA_ID_WIDTH-1:0] pop_hw_cta_id_o;
  logic                                             pop_ready_i;
  logic                                             add_ready_i;
  logic                                             add_valid_o;
  dice_cta_desc_t                                   add_cta_info_o;
  cta_size_e                                        add_hw_cta_size_o;
  logic             [          DICE_TID_WIDTH:0]    add_cta_thread_count_o;
  logic             [     DICE_HW_CTA_ID_WIDTH-1:0] next_empty_cta_index_i;
  logic             [DICE_NUM_MAX_CTA_PER_CORE-1:0] active_cta_status_i;
  logic                                             pop_out_valid_i;
  dice_cta_id_t                                     pop_out_cta_id_i;

  // SIMT Stack Controller interface
  logic                                             init_valid_o;
  logic                                             init_ready_i;
  logic             [     DICE_HW_CTA_ID_WIDTH-1:0] init_hw_cta_id_o;
  cta_size_e                                        init_hw_cta_size_o;
  logic             [          DICE_ADDR_WIDTH-1:0] init_pc_o;
  logic             [          DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_o;

  // CTA Status Table interface
  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_table_i;
  logic                                             clear_entry_valid_o;
  logic             [     DICE_HW_CTA_ID_WIDTH-1:0] clear_entry_hw_id_o;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  // DUT Instantiation
  cta_controller u_dut (
      .clk_i                  (clk),
      .rst_i                  (rst),
      .dispatch_if            (dispatch_if.slave),
      .complete_if            (complete_if.master),
      .pop_valid_o            (pop_valid_o),
      .pop_hw_cta_id_o        (pop_hw_cta_id_o),
      .pop_ready_i            (pop_ready_i),
      .add_ready_i            (add_ready_i),
      .add_valid_o            (add_valid_o),
      .add_cta_info_o         (add_cta_info_o),
      .add_hw_cta_size_o      (add_hw_cta_size_o),
      .add_cta_thread_count_o (add_cta_thread_count_o),
      .next_empty_cta_index_i (next_empty_cta_index_i),
      .active_cta_status_i    (active_cta_status_i),
      .pop_out_valid_i        (pop_out_valid_i),
      .pop_out_cta_id_i       (pop_out_cta_id_i),
      .init_valid_o           (init_valid_o),
      .init_ready_i           (init_ready_i),
      .init_hw_cta_id_o       (init_hw_cta_id_o),
      .init_hw_cta_size_o     (init_hw_cta_size_o),
      .init_pc_o              (init_pc_o),
      .init_reconvergence_pc_o(init_reconvergence_pc_o),
      .cta_status_table_i     (cta_status_table_i),
      .clear_entry_valid_o    (clear_entry_valid_o),
      .clear_entry_hw_id_o    (clear_entry_hw_id_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst                    = 1'b1;
    dispatch_if.valid      = 1'b0;
    dispatch_if.data       = '0;
    complete_if.ready      = 1'b1;
    pop_ready_i            = 1'b1;
    add_ready_i            = 1'b1;
    next_empty_cta_index_i = '0;
    active_cta_status_i    = '0;
    pop_out_valid_i        = 1'b0;
    pop_out_cta_id_i       = '0;
    init_ready_i           = 1'b1;
    cta_status_table_i     = '0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    dice_cta_desc_t desc;
    logic [DICE_ADDR_WIDTH-1:0] start_pc;

    $display("tb_cta_controller (happy-path)");

    reset_dut();

    start_pc = 32'h0000_1000;
    desc = '0;
    desc.kernel_desc.start_pc = start_pc;
    desc.kernel_desc.cta_size.x = 1;
    desc.kernel_desc.cta_size.y = 1;
    desc.kernel_desc.cta_size.z = 1;
    desc.cta_id.x = '0;
    desc.cta_id.y = '0;
    desc.cta_id.z = '0;

    next_empty_cta_index_i = '0;

    wait (dispatch_if.ready == 1'b1);
    dispatch_if.data  = desc;
    dispatch_if.valid = 1'b1;
    @(posedge clk);

    assert (dispatch_if.ready == 1'b1)
      else $fatal(1, "dispatch_if.ready not high");
    assert (add_valid_o == 1'b1)
      else $fatal(1, "add_valid_o not asserted");
    assert (init_valid_o == 1'b1)
      else $fatal(1, "init_valid_o not asserted");
    assert (init_pc_o == start_pc)
      else $fatal(1, "init_pc_o mismatch");
    assert (init_hw_cta_id_o == next_empty_cta_index_i)
      else $fatal(1, "init_hw_cta_id_o mismatch");

    dispatch_if.valid = 1'b0;

    $display("PASS: dispatch -> add/init handshake");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_cta_controller.vcd");
    $dumpvars(0, tb_cta_controller);
  end
`endif

endmodule
