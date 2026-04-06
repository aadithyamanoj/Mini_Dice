`include "dice_define.vh"

module cta_schedule_stage
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    cta_sched_if.master schedule_if,

    input logic                       eblock_commit_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,

    input logic                       eblock_flush_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i,

    input branch_predict_interface_t bh_branch_predict_info_i,
    input logic                      bh_branch_predict_info_we_i,
    output dice_cta_status_t cta_status_data_o,

    // BRT
    input block_retire_status_t   brt_info_i,
    input logic                   brt_info_write_enable_i,

    // Branch Handler
    input logic                            simt_update_valid_i,
    output logic                           simt_update_ready_o,
    input simt_stack_update_t              simt_update_stack_data_i,

    output simt_stack_status_entry_t simt_status_o
);


   dice_cta_id_t pop_cta_id, out_cta_id;

  // ---- SIMT stack top signals ----
  logic                        stack_top_valid;
  logic [DICE_ADDR_WIDTH-1:0]  stack_top_next_pc;
  logic [DICE_ADDR_WIDTH-1:0]  stack_top_reconvergence_pc;
  thread_mask_t                stack_top_active_mask;
  logic                        stack_empty;
  logic                        stack_full;

  assign simt_status_o.valid            = stack_top_valid;
  assign simt_status_o.next_pc          = stack_top_next_pc;
  assign simt_status_o.reconvergence_pc = stack_top_reconvergence_pc;
  assign simt_status_o.active_mask      = stack_top_active_mask;
  assign simt_status_o.empty            = stack_empty;
  assign simt_status_o.full             = stack_full;

  // ---- Active CTA table wiring ----
  logic active_table_add_ready;
  logic active_table_add_valid;
  dice_cta_desc_t active_table_cta_desc;

  logic active_table_pop_valid;
  logic active_table_pop_ready;
  logic active_table_out_valid;
  logic active_table_out_ready;
  logic active_table_full;
  active_cta_t active_cta_entry;

  // ---- SIMT init and misc control ----
  logic                                         simt_init_valid;
  logic [DICE_ADDR_WIDTH-1:0]                   simt_init_pc;
  logic [DICE_ADDR_WIDTH-1:0]                   simt_init_reconvergence_pc;
  logic [DICE_TID_WIDTH:0]                      simt_init_thread_count;
  logic                                         simt_init_ready;

  logic simt_stack_update_ready;
  assign simt_update_ready_o = simt_stack_update_ready;

  logic clear_entry_valid;

  // ---- CTA status ----
  dice_cta_status_t cta_status_real;
  assign cta_status_data_o = cta_status_real;

  // ---- CTA Controller ----
  cta_controller cta_controller_inst (
      .clk_i                  (clk_i),
      .rst_i                  (rst_i),
      .cta_if_inst            (cta_if_inst),
      .add_valid_o            (active_table_add_valid),
      .add_ready_i            (active_table_add_ready),
      .add_cta_info_o         (active_table_cta_desc),
      .pop_valid_o            (active_table_pop_valid),
      .pop_ready_i            (active_table_pop_ready),
      .active_cta_valid_i     (active_cta_entry.cta_valid),
      .pop_out_valid_i        (active_table_out_valid),
      .pop_out_cta_id_i       (pop_cta_id),
      .init_valid_o           (simt_init_valid),
      .init_pc_o              (simt_init_pc),
      .init_reconvergence_pc_o(simt_init_reconvergence_pc),
      .init_thread_count_o    (simt_init_thread_count),
      .init_ready_i           (simt_init_ready),
      .cta_status_i           (cta_status_real),
      .clear_entry_valid_o    (clear_entry_valid)
  );

  // ---- Active CTA Table ----
  active_cta_table active_cta_table_inst (
      .clk_i                 (clk_i),
      .rst_i                 (rst_i),
      .add_ready_o           (active_table_add_ready),
      .add_valid_i           (active_table_add_valid),
      .add_cta_info_i        (active_table_cta_desc),
      .pop_valid_i           (active_table_pop_valid),
      .pop_ready_o           (active_table_pop_ready),
      .out_cta_id_o          (out_cta_id),
      .out_valid_o           (active_table_out_valid),
      .out_ready_i           (active_table_out_ready),
      .active_cta_entry_o    (active_cta_entry),
      .full_o                (active_table_full)
  );

  // ---- CTA Scheduler ----
  cta_scheduler cta_scheduler_inst (
      .clk_i                  (clk_i),
      .rst_i                  (rst_i),
      .enable_i               (1'b1),
      .active_cta_entry_i     (active_cta_entry),
      .is_prefetch_i          (cta_status_real.unresolved_control_divergence),
      .predict_pc_i           (cta_status_real.predict_pc),
      .stack_top_valid_i      (stack_top_valid),
      .cta_next_pc_i          (stack_top_next_pc),
      .stack_top_active_mask_i(stack_top_active_mask),
      .eblock_commit_valid_i  (eblock_commit_valid_i),
      .eblock_commit_id_i     (eblock_commit_id_i),
      .eblock_flush_valid_i   (eblock_flush_valid_i),
      .eblock_flush_id_i      (eblock_flush_id_i),
      .scheduled_eblock       (schedule_if)
  );

  // ---- CTA Status Table ----
  cta_status_table cta_status_table_inst (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .branch_predict_info_i   (bh_branch_predict_info_i),
      .branch_predict_info_we_i(bh_branch_predict_info_we_i),
      .brt_info_i              (brt_info_i),
      .clear_entry_valid_i     (clear_entry_valid),
      .cta_status_o            (cta_status_real)
  );

  // ---- SIMT Stack Controller ----
  simt_stack_controller simt_stack_controller_inst (
      .clk_i                        (clk_i),
      .rst_i                        (rst_i),
      .update_valid_i               (simt_update_valid_i),
      .update_with_divergence_i     (simt_update_stack_data_i.update_with_divergence),
      .update_next_pc_i             (simt_update_stack_data_i.update_next_pc),
      .predicate_regs_value_i       (simt_update_stack_data_i.predicate_regs_value),
      .branch_not_taken_pc_i        (simt_update_stack_data_i.branch_not_taken_pc),
      .branch_reconvergence_pc_i    (simt_update_stack_data_i.branch_reconvergence_pc),
      .update_ready_o               (simt_stack_update_ready),
      .init_valid_i                 (simt_init_valid),
      .init_pc_i                    (simt_init_pc),
      .init_reconvergence_pc_i      (simt_init_reconvergence_pc),
      .init_thread_count_i          (simt_init_thread_count),
      .init_ready_o                 (simt_init_ready),
      .stack_top_valid_o            (stack_top_valid),
      .stack_top_next_pc_o          (stack_top_next_pc),
      .stack_top_reconvergence_pc_o (stack_top_reconvergence_pc),
      .stack_top_active_mask_o      (stack_top_active_mask),
      .stack_empty_o                (stack_empty),
      .stack_full_o                 (stack_full)
  );

endmodule
