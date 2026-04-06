module dice_frontend_top
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    dice_mem_bus_if.master metacache_mem_if,
    dice_mem_bus_if.master bitstream_cache_mem_if,

    fdr_if.master fdr_if_inst,
    output logic                              cm_wr_buffer_o,
    output logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_o,
    output logic [AxiDataWidth-1:0]           cm_wr_data_o,
    output logic                              cm_wr_valid_o,
    input logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs_i,

    input logic                       eblock_commit_valid_i,
    input logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,
    input block_retire_status_t       brt_info_i,
    input logic                       brt_info_write_enable_i
);

  cta_sched_if               schedule_if_inst ();
  simt_stack_status_entry_t  simt_status;
  dice_cta_status_t          cta_status_data;
  branch_predict_interface_t bh_branch_predict_info;
  logic                      bh_branch_predict_info_we;

  logic               simt_update_valid;
  logic               simt_update_ready;
  simt_stack_update_t simt_update_stack_data;

  logic                       eblock_flush_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id;

  cta_schedule_stage u_cta_schedule_stage (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .cta_if_inst             (cta_if_inst),
      .schedule_if             (schedule_if_inst),
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
      .simt_status_o           (simt_status)
  );

  fdr_top u_fdr_top (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .metacache_mem_if        (metacache_mem_if),
      .bitstream_cache_mem_if  (bitstream_cache_mem_if),
      .schedule_if             (schedule_if_inst),
      .fdr_if                  (fdr_if_inst),
      .simt_status_i           (simt_status),
      .pred_regs_i             (pred_regs_i),
      .bh_branch_predict_info_o(bh_branch_predict_info),
      .bh_branch_predict_info_we_o(bh_branch_predict_info_we),
      .cta_status_data_i       (cta_status_data),
      .simt_update_valid_o     (simt_update_valid),
      .simt_update_ready_i     (simt_update_ready),
      .simt_update_stack_data_o(simt_update_stack_data),
      .cm_wr_buffer_o          (cm_wr_buffer_o),
      .cm_wr_addr_o            (cm_wr_addr_o),
      .cm_wr_data_o            (cm_wr_data_o),
      .cm_wr_valid_o           (cm_wr_valid_o),
      .eblock_flush_valid_o    (eblock_flush_valid),
      .eblock_flush_id_o       (eblock_flush_id)
  );

endmodule
