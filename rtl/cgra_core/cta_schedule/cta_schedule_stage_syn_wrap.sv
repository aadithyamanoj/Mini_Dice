module cta_schedule_stage_syn_wrap
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
  input logic clk_i,
  input logic rst_i,

  // Host/dispatcher -> scheduler
  input  logic          cta_dispatch_valid_i,
  input  dice_cta_desc_t cta_dispatch_data_i,
  output logic          cta_dispatch_ready_o,

  // Scheduler -> host/dispatcher completion
  output logic         cta_complete_valid_o,
  output dice_cta_id_t cta_complete_cta_id_o,
  input  logic         cta_complete_ready_i,

  // Scheduler -> FDR dispatch
  output logic             schedule_valid_o,
  output schedule_eblock_t schedule_data_o,
  input  logic             schedule_ready_i,

  // E-block commit interface (from execution/retire)
  input logic                       eblock_commit_valid_i,
  input logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,

  // E-block flush interface (from FDR predict-miss)
  input logic                       eblock_flush_valid_i,
  input logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i,

  // Branch predictor/status-table update interface
  input  branch_predict_interface_t bh_branch_predict_info_i,
  input  logic                      bh_branch_predict_info_we_i,
  output dice_cta_status_t          [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_data_o,

  // Block retire table interface
  input block_retire_status_t brt_info_i,
  input logic                 brt_info_write_enable_i,

  // SIMT stack updates (from FDR branch handler)
  input  logic                            simt_update_valid_i,
  output logic                            simt_update_ready_o,
  input  simt_stack_update_t              simt_update_stack_data_i,
  input  logic [DICE_HW_CTA_ID_WIDTH-1:0] simt_update_hw_cta_id_i,
  input  cta_size_e                       simt_update_hw_cta_size_i,

  // SIMT stack status (to FDR)
  output simt_stack_status_entry_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] simt_status_o
);

  cta_dispatch_if     cta_dispatch_if_inst ();
  cta_complete_if     cta_complete_if_inst ();
  cta_sched_if        schedule_if_inst ();
  simt_stack_status_if simt_status_if_inst ();

  assign cta_dispatch_if_inst.valid = cta_dispatch_valid_i;
  assign cta_dispatch_if_inst.data  = cta_dispatch_data_i;
  assign cta_dispatch_ready_o       = cta_dispatch_if_inst.ready;

  assign cta_complete_valid_o       = cta_complete_if_inst.valid;
  assign cta_complete_cta_id_o      = cta_complete_if_inst.cta_id;
  assign cta_complete_if_inst.ready = cta_complete_ready_i;

  assign schedule_valid_o      = schedule_if_inst.valid;
  assign schedule_data_o       = schedule_if_inst.data;
  assign schedule_if_inst.ready = schedule_ready_i;

  assign simt_status_o = simt_status_if_inst.status;

  cta_schedule_stage u_cta_schedule_stage (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .cta_dispatch_if(cta_dispatch_if_inst),
    .cta_complete_if(cta_complete_if_inst),
    .schedule_if(schedule_if_inst),
    .eblock_commit_valid_i(eblock_commit_valid_i),
    .eblock_commit_id_i(eblock_commit_id_i),
    .eblock_flush_valid_i(eblock_flush_valid_i),
    .eblock_flush_id_i(eblock_flush_id_i),
    .bh_branch_predict_info_i(bh_branch_predict_info_i),
    .bh_branch_predict_info_we_i(bh_branch_predict_info_we_i),
    .cta_status_data_o(cta_status_data_o),
    .brt_info_i(brt_info_i),
    .brt_info_write_enable_i(brt_info_write_enable_i),
    .simt_update_valid_i(simt_update_valid_i),
    .simt_update_ready_o(simt_update_ready_o),
    .simt_update_stack_data_i(simt_update_stack_data_i),
    .simt_update_hw_cta_id_i(simt_update_hw_cta_id_i),
    .simt_update_hw_cta_size_i(simt_update_hw_cta_size_i),
    .simt_status_if(simt_status_if_inst)
  );

endmodule
