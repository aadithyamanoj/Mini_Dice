`include "dice_define.vh"


module cta_schedule_stage
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(

    input logic clk_i,
    input logic rst_i,

    // Host/Dispatcher interface for new CTA allocation
    cta_dispatch_if.slave cta_dispatch_if,

    // CTA completion output (to dispatcher)
    cta_complete_if.master cta_complete_if,

    // Scheduler output interface (to FDR stage)
    cta_sched_if.master schedule_if,

    // E-block commit interface (from execution/retire)
    input logic                       eblock_commit_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,

    // E-block flush interface (from FDR predict-miss)
    input logic                       eblock_flush_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i,

    // Branch handler / predictor signals (from FDR/execution)
    input branch_predict_interface_t bh_branch_predict_info_i,
    input logic                      bh_branch_predict_info_we_i,
    output dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_data_o,
    // Block Retire Table interface
    input block_retire_status_t   brt_info_i,
    input logic                   brt_info_write_enable_i,

    // SIMT Stack Update Signals (from FDR branch handler)
    input logic                            simt_update_valid_i,
    output logic                           simt_update_ready_o,
    input simt_stack_update_t              simt_update_stack_data_i,
    input logic [DICE_HW_CTA_ID_WIDTH-1:0] simt_update_hw_cta_id_i,
    input cta_size_e                       simt_update_hw_cta_size_i,

    // SIMT Stack Status Interface (NEW - replaces individual outputs)
    simt_stack_status_if.master simt_status_if

);

  // Local Parameters (derived from packages)
  localparam int ThreadWidth = DICE_NUM_MAX_THREADS_PER_CORE / DICE_NUM_MAX_CTA_PER_CORE;

  // Local wires - SIMT Stack outputs (internal, then assigned to interface)
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0]                      stack_top_valid;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][DICE_ADDR_WIDTH-1:0] stack_top_next_pc;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][    ThreadWidth-1:0] stack_top_active_mask;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0]                      stack_empty;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0]                      stack_full;

  // SIMT Status Interface Assignment
  generate
    for (genvar i = 0; i < DICE_NUM_MAX_CTA_PER_CORE; i++) begin : gen_simt_status
      assign simt_status_if.status[i].valid            = stack_top_valid[i];
      assign simt_status_if.status[i].next_pc          = stack_top_next_pc[i];
      assign simt_status_if.status[i].reconvergence_pc = stack_top_reconvergence_pc[i];
      assign simt_status_if.status[i].active_mask      = stack_top_active_mask[i];
      assign simt_status_if.status[i].empty            = stack_empty[i];
      assign simt_status_if.status[i].full             = stack_full[i];
    end
  endgenerate

  // Local wires
  logic active_table_add_ready;
  logic active_table_add_valid;
  dice_cta_desc_t active_table_cta_desc;
  cta_size_e active_table_hw_cta_size;
  logic [DICE_TID_WIDTH:0] active_table_cta_thread_count;

  logic active_table_pop_valid;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] active_table_pop_hw_id;
  logic active_table_pop_ready;
  logic active_table_out_valid;
  logic active_table_out_ready;
  dice_cta_id_t active_table_out_cta_id;
  logic [DICE_TID_WIDTH:0] active_table_out_cta_thread_count;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] active_table_next_empty_idx;
  active_cta_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] active_cta_entries;

  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_real;

  assign cta_status_data_o = cta_status_real;

  // ADAPTER FOR CTA SCHEDULER
  cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] scheduler_status_adapter;

  always_comb begin
    for (int i = 0; i < DICE_NUM_MAX_CTA_PER_CORE; i++) begin
      scheduler_status_adapter[i].hw_cta_id   = (DICE_CTA_ID_WIDTH)'(i);
      scheduler_status_adapter[i].is_prefetch = cta_status_real[i].unresolved_control_divergence;
      scheduler_status_adapter[i].predict_pc  = cta_status_real[i].predict_pc;
    end
  end

  // SIMT STACK UPDATE
  logic simt_stack_update_ready;
  assign simt_update_ready_o = simt_stack_update_ready;

  // SIMT STACK INITIALIZATION
  logic                                         simt_init_valid;
  logic [$clog2(DICE_NUM_MAX_CTA_PER_CORE)-1:0] simt_init_hw_cta_id;
  cta_size_e                                   simt_init_hw_cta_size;
  logic [DICE_ADDR_WIDTH-1:0]                   simt_init_pc;
  logic [DICE_ADDR_WIDTH-1:0]                   simt_init_reconvergence_pc;
  logic                                         simt_init_ready;


  // ACTIVE CTA TABLE VALIDITY BITMAP
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] active_cta_validty_bitmap;
  always_comb begin
    for (int i = 0; i < DICE_NUM_MAX_CTA_PER_CORE; i++) begin
      active_cta_validty_bitmap[i] = active_cta_entries[i].cta_valid;
    end
  end

  // ACTIVE CTA TABLE CLEAR
  logic clear_entry_valid;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] clear_entry_hw_id;

  // CTA Controller
  cta_controller cta_controller_inst (
      .clk_i                  (clk_i),
      .rst_i                  (rst_i),
      .dispatch_if            (cta_dispatch_if),
      .complete_if            (cta_complete_if),
      .add_valid_o            (active_table_add_valid),
      .add_ready_i            (active_table_add_ready),
      .add_cta_info_o         (active_table_cta_desc),
      .add_hw_cta_size_o      (active_table_hw_cta_size),
      .add_cta_thread_count_o (active_table_cta_thread_count),
      .next_empty_cta_index_i (active_table_next_empty_idx),
      .pop_valid_o            (active_table_pop_valid),
      .pop_hw_cta_id_o        (active_table_pop_hw_id),
      .pop_ready_i            (active_table_pop_ready),
      .active_cta_status_i    (active_cta_validty_bitmap),
      .pop_out_valid_i        (active_table_out_valid),
      .pop_out_cta_id_i       (active_table_out_cta_id),
      .init_valid_o           (simt_init_valid),
      .init_hw_cta_id_o       (simt_init_hw_cta_id),
      .init_hw_cta_size_o     (simt_init_hw_cta_size),
      .init_pc_o              (simt_init_pc),
      .init_reconvergence_pc_o(simt_init_reconvergence_pc),
      .init_ready_i           (simt_init_ready),
      .cta_status_table_i     (cta_status_real),
      .clear_entry_valid_o    (clear_entry_valid),
      .clear_entry_hw_id_o    (clear_entry_hw_id)
  );

  // Active CTA Table
  active_cta_table active_cta_table_inst (
      .clk_i                 (clk_i),
      .rst_i                 (rst_i),
      .add_ready_o           (active_table_add_ready),
      .add_valid_i           (active_table_add_valid),
      .add_cta_info_i        (active_table_cta_desc),
      .add_hw_cta_size_i     (active_table_hw_cta_size),
      .add_cta_thread_count_i(active_table_cta_thread_count),
      .pop_valid_i           (active_table_pop_valid),
      .pop_hw_cta_id_i       (active_table_pop_hw_id),
      .pop_ready_o           (active_table_pop_ready),
      .out_valid_o           (active_table_out_valid),
      .out_ready_i           (active_table_out_ready),
      .out_cta_id_o          (active_table_out_cta_id),
      .out_cta_size_o        (), // unused
      .out_kernel_id_o       (), // unused
      .out_cta_thread_count_o(active_table_out_cta_thread_count),
      .active_cta_entries_o  (active_cta_entries),
      .full_o                (), // unused
      .next_empty_cta_index_o(active_table_next_empty_idx)
  );


  // CTA Scheduler
  cta_scheduler cta_scheduler_inst (
      .clk_i                  (clk_i),
      .rst_i                  (rst_i),
      .enable_i               (1'b1),
      .active_cta_entries_i   (active_cta_entries),
      .cta_status_entries_i   (scheduler_status_adapter),
      .stack_top_valid_i      (stack_top_valid),
      .cta_next_pc_i          (stack_top_next_pc),
      .stack_top_active_mask_i(stack_top_active_mask),
      .eblock_commit_valid_i  (eblock_commit_valid_i),
      .eblock_commit_id_i     (eblock_commit_id_i),
      .eblock_flush_valid_i   (eblock_flush_valid_i),
      .eblock_flush_id_i      (eblock_flush_id_i),
      .scheduled_eblock       (schedule_if)
  );



  // CTA Status Table
  cta_status_table cta_status_table_inst (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .branch_predict_info_i   (bh_branch_predict_info_i),
      .branch_predict_info_we_i(bh_branch_predict_info_we_i),
      .brt_info_i              (brt_info_i),
      .clear_entry_valid_i     (clear_entry_valid),
      .clear_entry_hw_id_i     (clear_entry_hw_id),
      .cta_status_o            (cta_status_real)
  );


  // SIMT Stack Controller
  simt_stack_controller simt_stack_controller_inst (
      .clk_i                        (clk_i),
      .rst_i                        (rst_i),
      .hw_cta_id_i                  (simt_update_hw_cta_id_i),
      .hw_cta_size_i                (simt_update_hw_cta_size_i),
      .update_valid_i               (simt_update_valid_i),
      .update_with_divergence_i     (simt_update_stack_data_i.update_with_divergence),
      .update_next_pc_i             (simt_update_stack_data_i.update_next_pc),
      .predicate_regs_value_i       (simt_update_stack_data_i.predicate_regs_value),
      .branch_not_taken_pc_i        (simt_update_stack_data_i.branch_not_taken_pc),
      .branch_reconvergence_pc_i    (simt_update_stack_data_i.branch_reconvergence_pc),
      .update_ready_o               (simt_stack_update_ready),
      .init_valid_i                 (simt_init_valid),
      .init_hw_cta_id_i             (simt_init_hw_cta_id),
      .init_hw_cta_size_i           (simt_init_hw_cta_size),
      .init_pc_i                    (simt_init_pc),
      .init_reconvergence_pc_i      (simt_init_reconvergence_pc),
      .init_ready_o                 (simt_init_ready),
      .stack_top_valid_o            (stack_top_valid),
      .stack_top_next_pc_o          (stack_top_next_pc),
      .stack_top_reconvergence_pc_o (stack_top_reconvergence_pc),
      .stack_top_active_mask_o      (stack_top_active_mask),
      .stack_empty_o                (stack_empty),
      .stack_full_o                 (stack_full)
  );



`ifndef SYNTHESIS


`endif


endmodule
