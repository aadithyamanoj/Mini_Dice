
module dice_frontend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // External CTA interface
    cta_if.slave cta_if_inst,

    // AXI4 read master ports to the fetch memory system
    output slv_req_t  mfetch_req_o,
    input  slv_resp_t mfetch_resp_i,
    output slv_req_t  bsfetch_req_o,
    input  slv_resp_t bsfetch_resp_i,

    // FDR output to backend
    fdr_if.master fdr_if_o,

    // Direct write interface to configuration memory DFFs
    output logic                              cm_wr_buffer_o,
    output logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_o,
    output logic [AxiDataWidth-1:0]           cm_wr_data_o,
    output logic                              cm_wr_valid_o,
    input logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs_i,
    input logic prog_active_i,
    input logic prog_active_buffer_i,

    // Block commit table feedback (from backend)
    input logic                       eblock_commit_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,
    input block_retire_status_t       brt_info_i,
    input logic                       brt_info_write_enable_i,

    // SIMT stack observability for future CSR plumbing
    output logic        stack_overflow_o,
    output logic [15:0] stack_depth_o,
    output logic [15:0] stack_error_pc_o,
    output logic [SIMT_STACK_ENTRY_COUNT_WIDTH-1:0] simt_stack_entry_count_o
);

  // =========================================================================
  // Internal interfaces and wires
  // =========================================================================
  cta_sched_if              schedule_if ();
  simt_stack_status_entry_t simt_status;

  // FDR -> scheduler status table/branch prediction wires
  branch_predict_interface_t bh_branch_predict_info;
  logic                      bh_branch_predict_info_we;
  dice_cta_status_t          cta_status_data;

  // FDR -> scheduler SIMT update wires
  logic                            simt_update_valid;
  logic                            simt_update_ready;
  simt_stack_update_t              simt_update_stack_data;

  // Eblock flush wires (FDR -> Scheduler)
  logic                       eblock_flush_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id;

  // =========================================================================
  // CTA Schedule Stage
  // =========================================================================
  cta_schedule_stage u_cta_schedule_stage (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .cta_if_inst             (cta_if_inst),
      .schedule_if             (schedule_if),
      .eblock_commit_valid_i   (eblock_commit_valid_i),
      .eblock_commit_id_i      (eblock_commit_id_i),
      .eblock_flush_valid_i    (eblock_flush_valid),
      .eblock_flush_id_i       (eblock_flush_id),
      .bh_branch_predict_info_i(bh_branch_predict_info),
      .bh_branch_predict_info_we_i(bh_branch_predict_info_we),
      .cta_status_data_o       (cta_status_data),
      .brt_info_i              (brt_info_i),
      .brt_info_write_enable_i (brt_info_write_enable_i),
      .simt_update_valid_i     (simt_update_valid),
      .simt_update_ready_o     (simt_update_ready),
      .simt_update_stack_data_i(simt_update_stack_data),
      .simt_status_o           (simt_status),
      .stack_overflow_o        (stack_overflow_o),
      .stack_depth_o           (stack_depth_o),
      .stack_error_pc_o        (stack_error_pc_o),
      .simt_stack_entry_count_o(simt_stack_entry_count_o)
  );

  // =========================================================================
  // FDR Top
  // =========================================================================
  fdr_top u_fdr_top (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .mfetch_req_o(mfetch_req_o),
      .mfetch_resp_i(mfetch_resp_i),
      .bsfetch_req_o(bsfetch_req_o),
      .bsfetch_resp_i(bsfetch_resp_i),
      .schedule_if(schedule_if),
      .fdr_if(fdr_if_o),
      .simt_status_i(simt_status),
      .pred_regs_i(pred_regs_i),
      .prog_active_i(prog_active_i),
      .prog_active_buffer_i(prog_active_buffer_i),
      .bh_branch_predict_info_o(bh_branch_predict_info),
      .bh_branch_predict_info_we_o(bh_branch_predict_info_we),
      .cta_status_data_i(cta_status_data),
      .simt_update_valid_o(simt_update_valid),
      .simt_update_ready_i(simt_update_ready),
      .simt_update_stack_data_o(simt_update_stack_data),
      .cm_wr_buffer_o(cm_wr_buffer_o),
      .cm_wr_addr_o(cm_wr_addr_o),
      .cm_wr_data_o(cm_wr_data_o),
      .cm_wr_valid_o(cm_wr_valid_o),
      .eblock_flush_valid_o(eblock_flush_valid),
      .eblock_flush_id_o   (eblock_flush_id)
  );

endmodule
