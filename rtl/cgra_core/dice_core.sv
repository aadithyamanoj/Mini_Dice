
module dice_core
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    // AXI4 read master ports to the fetch memory system
    output slv_req_t  mfetch_req_o,
    input  slv_resp_t mfetch_resp_i,
    output slv_req_t  bsfetch_req_o,
    input  slv_resp_t bsfetch_resp_i,

    // TMCU -> External Memory Interface
    output logic                                                                        tmcu_valid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0]                                             tmcu_block_id_o,
    output logic [DICE_TID_WIDTH-1:0]                                                   tmcu_base_tid_o,
    output logic [DICE_TID_BITMAP_WIDTH-1:0]                                            tmcu_tid_bitmap_o,
    output logic                                                                        tmcu_write_enable_o,
    output logic [DICE_CACHE_LINE_SIZE*8-1:0]                                           tmcu_write_data_o,
    output logic [DICE_CACHE_LINE_SIZE-1:0]                                             tmcu_write_mask_o,
    output logic [DICE_ADDR_WIDTH-1:0]                                                  tmcu_address_o,
    output logic [1:0]                                                                  tmcu_size_o,
    output logic [DICE_MAX_REG_WIDTH-1:0]                                               tmcu_ld_dest_reg_o,
    output logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] tmcu_address_map_o,
    input  logic                                                                        tmcu_ready_i,

    // Memory Response Input (cache_wr_cmd fields)
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                            mem_rsp_base_tid_i,
    input  logic [TID_BITMAP_WIDTH-1:0]                                                 mem_rsp_tid_bitmap_i,
    input  logic [DICE_REG_ADDR_WIDTH-1:0]                                              mem_rsp_ld_dest_reg_i,
    input  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]        mem_rsp_address_map_i,
    input  logic [(CACHE_LINE_SIZE*8)-1:0]                                              mem_rsp_data_i,
    input  logic                                                                        mem_rsp_valid_i,

    // Direct write interface to configuration memory DFFs
    output logic                              cm_wr_buffer_o,
    output logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_o,
    output logic [AxiDataWidth-1:0]           cm_wr_data_o,
    output logic                              cm_wr_valid_o

);

  // =========================================================================
  // Internal interfaces
  // =========================================================================
  fdr_if     fdr_out_if ();

  // Backend -> Frontend commit feedback
  logic                            bct_pop_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] bct_pop_e_block_id;
  logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] frontend_pred_regs;
  block_retire_status_t            frontend_brt_info;
  logic                            frontend_brt_info_write_enable;

  assign frontend_pred_regs = '0; //CONNECT TO BACKEND
  assign frontend_brt_info = '0;
  assign frontend_brt_info_write_enable = 1'b0;

  // =========================================================================
  // Frontend — CTA scheduler + FDR
  // =========================================================================
  dice_frontend u_dice_frontend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .cta_if_inst          (cta_if_inst),
      .mfetch_req_o         (mfetch_req_o),
      .mfetch_resp_i        (mfetch_resp_i),
      .bsfetch_req_o        (bsfetch_req_o),
      .bsfetch_resp_i       (bsfetch_resp_i),

      .fdr_if_o             (fdr_out_if),
      .cm_wr_buffer_o       (cm_wr_buffer_o),
      .cm_wr_addr_o         (cm_wr_addr_o),
      .cm_wr_data_o         (cm_wr_data_o),
      .cm_wr_valid_o        (cm_wr_valid_o),
      .pred_regs_i          (frontend_pred_regs),

      .eblock_commit_valid_i(bct_pop_valid),
      .eblock_commit_id_i   (bct_pop_e_block_id),
      .brt_info_i           (frontend_brt_info),
      .brt_info_write_enable_i(frontend_brt_info_write_enable)
  );

  // =========================================================================
  // Backend — dispatcher, register file, TMCU, block commit table
  // =========================================================================
  dice_backend u_dice_backend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // FDR interface
      .fdr_if_i(fdr_out_if),

      // TMCU -> External Memory
      .tmcu_valid_o       (tmcu_valid_o),
      .tmcu_block_id_o    (tmcu_block_id_o),
      .tmcu_base_tid_o    (tmcu_base_tid_o),
      .tmcu_tid_bitmap_o  (tmcu_tid_bitmap_o),
      .tmcu_write_enable_o(tmcu_write_enable_o),
      .tmcu_write_data_o  (tmcu_write_data_o),
      .tmcu_write_mask_o  (tmcu_write_mask_o),
      .tmcu_address_o     (tmcu_address_o),
      .tmcu_size_o        (tmcu_size_o),
      .tmcu_ld_dest_reg_o (tmcu_ld_dest_reg_o),
      .tmcu_address_map_o (tmcu_address_map_o),
      .tmcu_ready_i       (tmcu_ready_i),

      // Memory Response
      .mem_rsp_base_tid_i   (mem_rsp_base_tid_i),
      .mem_rsp_tid_bitmap_i (mem_rsp_tid_bitmap_i),
      .mem_rsp_ld_dest_reg_i(mem_rsp_ld_dest_reg_i),
      .mem_rsp_address_map_i(mem_rsp_address_map_i),
      .mem_rsp_data_i       (mem_rsp_data_i),
      .mem_rsp_valid_i      (mem_rsp_valid_i),

      // Block commit table outputs
      .eblock_commit_valid_o(bct_pop_valid),
      .eblock_commit_id_o   (bct_pop_e_block_id),
      .eblock_commit_ready_i(1'b1),
      .hw_cta_pending_o     ()
  );

endmodule
