
module dice_core
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    // Memory Bus Interfaces
    VX_mem_bus_if.master metacache_mem_if,
    VX_mem_bus_if.master bitstream_cache_mem_if,

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

    // Memory Response Input
    input  logic [$bits(cache_wr_cmd)-1:0]                                              mem_rsp_i,
    input  logic                                                                        mem_rsp_valid_i

);

  // =========================================================================
  // Internal interfaces
  // =========================================================================
  fdr_if     fdr_out_if ();
  cgra_cm_if cm0_if     ();
  cgra_cm_if cm1_if     ();

  // Backend -> Frontend commit feedback
  logic                            bct_pop_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] bct_pop_e_block_id;

  // =========================================================================
  // Frontend — CTA scheduler + FDR
  // =========================================================================
  dice_frontend u_dice_frontend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .cta_if_inst          (cta_if_inst),
      .metacache_mem_if     (metacache_mem_if),
      .bitstream_cache_mem_if(bitstream_cache_mem_if),

      .fdr_if_o             (fdr_out_if),
      .cm0_if_o             (cm0_if),
      .cm1_if_o             (cm1_if),

      .eblock_commit_valid_i(bct_pop_valid),
      .eblock_commit_id_i   (bct_pop_e_block_id)
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
      .mem_rsp_i            (mem_rsp_i),
      .mem_rsp_valid_i      (mem_rsp_valid_i),

      // Block commit table outputs
      .eblock_commit_valid_o(bct_pop_valid),
      .eblock_commit_id_o   (bct_pop_e_block_id),
      .eblock_commit_ready_i(1'b1),
      .hw_cta_pending_o     ()
  );

endmodule
