// Synthesis wrapper for dice_core: full frontend + backend (area variant)
// All SV interfaces flattened to plain logic ports to prevent optimization.

module dice_core_syn
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
#(
    // VX_mem_bus_if derived widths (default interface params)
    parameter int MEM_BUS_DATA_SIZE  = DICE_MEM_DATA_WIDTH / 8,               // 64
    parameter int MEM_BUS_ADDR_WIDTH = DICE_MEM_ADDR_WIDTH - $clog2(MEM_BUS_DATA_SIZE), // 26
    parameter int MEM_BUS_TAG_WIDTH  = 48,
    parameter int MEM_BUS_FLAGS_WIDTH = DICE_MEM_FLAGS_WIDTH,                  // 4
    // req_data = rw(1) + addr + data + byteen + flags + tag
    parameter int MEM_BUS_REQ_WIDTH  = 1 + MEM_BUS_ADDR_WIDTH
                                       + MEM_BUS_DATA_SIZE*8
                                       + MEM_BUS_DATA_SIZE
                                       + MEM_BUS_FLAGS_WIDTH
                                       + MEM_BUS_TAG_WIDTH,
    // rsp_data = data + tag
    parameter int MEM_BUS_RSP_WIDTH  = MEM_BUS_DATA_SIZE*8 + MEM_BUS_TAG_WIDTH,
    // cgra_cm_if chunk count
    parameter int CM_CHUNK_COUNT     = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                       / DICE_MEM_DATA_WIDTH
)
(
    input  logic clk_i,
    input  logic rst_i,

    // =====================================================================
    // CTA dispatch interface (flattened cta_if)
    // =====================================================================
    input  logic                            cta_dispatch_valid_i,
    input  logic [$bits(dice_cta_desc_t)-1:0] cta_dispatch_data_i,
    output logic                            cta_dispatch_ready_o,

    output logic                            cta_complete_valid_o,
    output logic [$bits(dice_cta_id_t)-1:0] cta_complete_cta_id_o,
    input  logic                            cta_complete_ready_i,

    // =====================================================================
    // Metacache memory bus (flattened VX_mem_bus_if)
    // =====================================================================
    output logic                         meta_req_valid_o,
    output logic [MEM_BUS_REQ_WIDTH-1:0] meta_req_data_o,
    input  logic                         meta_req_ready_i,

    input  logic                         meta_rsp_valid_i,
    input  logic [MEM_BUS_RSP_WIDTH-1:0] meta_rsp_data_i,
    output logic                         meta_rsp_ready_o,

    // =====================================================================
    // Bitstream cache memory bus (flattened VX_mem_bus_if)
    // =====================================================================
    output logic                         bs_req_valid_o,
    output logic [MEM_BUS_REQ_WIDTH-1:0] bs_req_data_o,
    input  logic                         bs_req_ready_i,

    input  logic                         bs_rsp_valid_i,
    input  logic [MEM_BUS_RSP_WIDTH-1:0] bs_rsp_data_i,
    output logic                         bs_rsp_ready_o,

    // =====================================================================
    // CGRA config memory interfaces (flattened cgra_cm_if)
    // =====================================================================
    output logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_o,
    output logic [CM_CHUNK_COUNT-1:0]      cm0_chunk_en_o,
    output logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_o,
    output logic [CM_CHUNK_COUNT-1:0]      cm1_chunk_en_o,

    // =====================================================================
    // TMCU -> External Memory Interface
    // =====================================================================
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

    // =====================================================================
    // Memory Response Input
    // =====================================================================
    input  logic [$bits(cache_wr_cmd)-1:0]                                              mem_rsp_i,
    input  logic                                                                        mem_rsp_valid_i,

    // =====================================================================
    // Block commit table outputs
    // =====================================================================
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     hw_cta_pending_o,

    // =====================================================================
    // PLACEHOLDER ports — prevent dead-code elimination of CGRA-side signals
    // =====================================================================

    // Dispatcher / regfile status
    output logic                                                           dispatcher_done_o,
    output logic                                                           dispatch_fifo_empty_o,
    output logic                                                           rf_rd_valid_o,
    output logic                                                           rf_rd_ready_o,
    output logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] rd_data_o,
    output logic [DICE_NUM_PRED*DICE_NUM_MAX_THREADS_PER_CORE-1:0]         pred_o,
    output logic                                                           ldst_ready_o,
    output logic                                                           tmcu_incmd_ready_o,

    // CGRA write-back to regfile
    input  logic                                            cgra_v_i,
    input  logic [DICE_TOTAL_REGS*DICE_REG_DATA_WIDTH-1:0] cgra_data_i,
    input  logic [DICE_TID_WIDTH-1:0]                      cgra_tid_i,

    // TMCU input commands (from CGRA)
    input  logic                              tmcu_incmd_valid_i,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]   tmcu_incmd_block_id_i,
    input  logic [DICE_TID_WIDTH-1:0]         tmcu_incmd_tid_i,
    input  logic                              tmcu_incmd_write_enable_i,
    input  logic [DICE_DATA_WIDTH-1:0]        tmcu_incmd_write_data_i,
    input  logic [DICE_DATA_WIDTH/8-1:0]      tmcu_incmd_write_mask_i,
    input  logic [DICE_ADDR_WIDTH-1:0]        tmcu_incmd_address_i,
    input  logic [1:0]                        tmcu_incmd_size_i,
    input  logic [DICE_MAX_REG_WIDTH-1:0]     tmcu_incmd_ld_dest_reg_i,

    // BCT insert interface
    input  logic                              bct_insert_valid_i,
    input  logic [DICE_HW_CTA_ID_WIDTH-1:0]  bct_insert_hw_cta_id_i,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]   bct_insert_e_block_id_i,
    input  logic [13:0]                       bct_insert_pending_reads_i,
    input  logic [13:0]                       bct_insert_pending_writes_i,

    // BCT update interface
    input  logic                                bct_update_valid_i,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]     bct_update_e_block_id_i,
    input  logic                                bct_update_is_write_i,
    input  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] bct_update_reduce_count_i
);

  // =====================================================================
  // Internal SV interfaces
  // =====================================================================
  cta_if           cta_if_inst ();
  VX_mem_bus_if    metacache_mem_if ();
  VX_mem_bus_if    bitstream_cache_mem_if ();
  fdr_if           fdr_out_if ();
  cgra_cm_if       cm0_if ();
  cgra_cm_if       cm1_if ();

  // Backend -> Frontend commit feedback
  logic                            bct_pop_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] bct_pop_e_block_id;

  // =====================================================================
  // CTA interface wiring
  // =====================================================================
  assign cta_if_inst.dispatch_valid = cta_dispatch_valid_i;
  assign cta_if_inst.dispatch_data  = cta_dispatch_data_i;
  assign cta_dispatch_ready_o       = cta_if_inst.dispatch_ready;

  assign cta_complete_valid_o       = cta_if_inst.complete_valid;
  assign cta_complete_cta_id_o      = cta_if_inst.complete_cta_id;
  assign cta_if_inst.complete_ready = cta_complete_ready_i;

  // =====================================================================
  // Metacache memory bus wiring
  // =====================================================================
  assign meta_req_valid_o           = metacache_mem_if.req_valid;
  assign meta_req_data_o            = metacache_mem_if.req_data;
  assign metacache_mem_if.req_ready = meta_req_ready_i;

  assign metacache_mem_if.rsp_valid = meta_rsp_valid_i;
  assign metacache_mem_if.rsp_data  = meta_rsp_data_i;
  assign meta_rsp_ready_o           = metacache_mem_if.rsp_ready;

  // =====================================================================
  // Bitstream cache memory bus wiring
  // =====================================================================
  assign bs_req_valid_o                   = bitstream_cache_mem_if.req_valid;
  assign bs_req_data_o                    = bitstream_cache_mem_if.req_data;
  assign bitstream_cache_mem_if.req_ready = bs_req_ready_i;

  assign bitstream_cache_mem_if.rsp_valid = bs_rsp_valid_i;
  assign bitstream_cache_mem_if.rsp_data  = bs_rsp_data_i;
  assign bs_rsp_ready_o                   = bitstream_cache_mem_if.rsp_ready;

  // =====================================================================
  // CGRA config memory wiring
  // =====================================================================
  assign cm0_data_o     = cm0_if.data;
  assign cm0_chunk_en_o = cm0_if.chunk_en;
  assign cm1_data_o     = cm1_if.data;
  assign cm1_chunk_en_o = cm1_if.chunk_en;

  // =====================================================================
  // Frontend
  // =====================================================================
  (* dont_touch = "true" *) dice_frontend u_dice_frontend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .cta_if_inst            (cta_if_inst),
      .metacache_mem_if       (metacache_mem_if),
      .bitstream_cache_mem_if (bitstream_cache_mem_if),

      .fdr_if_o               (fdr_out_if),
      .cm0_if_o               (cm0_if),
      .cm1_if_o               (cm1_if),

      .eblock_commit_valid_i  (bct_pop_valid),
      .eblock_commit_id_i     (bct_pop_e_block_id)
  );

  // =====================================================================
  // Backend (area variant — placeholder ports for CGRA)
  // =====================================================================
  (* dont_touch = "true" *) dice_backend_area u_dice_backend (
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
      .hw_cta_pending_o     (hw_cta_pending_o),

      // PLACEHOLDER outputs
      .dispatcher_done_o     (dispatcher_done_o),
      .dispatch_fifo_empty_o (dispatch_fifo_empty_o),
      .rf_rd_valid_o         (rf_rd_valid_o),
      .rf_rd_ready_o         (rf_rd_ready_o),
      .rd_data_o             (rd_data_o),
      .pred_o                (pred_o),
      .ldst_ready_o          (ldst_ready_o),
      .tmcu_incmd_ready_o    (tmcu_incmd_ready_o),

      // PLACEHOLDER inputs — CGRA write-back
      .cgra_v_i              (cgra_v_i),
      .cgra_data_i           (cgra_data_i),
      .cgra_tid_i            (cgra_tid_i),

      // PLACEHOLDER inputs — TMCU input commands
      .tmcu_incmd_valid_i       (tmcu_incmd_valid_i),
      .tmcu_incmd_block_id_i    (tmcu_incmd_block_id_i),
      .tmcu_incmd_tid_i         (tmcu_incmd_tid_i),
      .tmcu_incmd_write_enable_i(tmcu_incmd_write_enable_i),
      .tmcu_incmd_write_data_i  (tmcu_incmd_write_data_i),
      .tmcu_incmd_write_mask_i  (tmcu_incmd_write_mask_i),
      .tmcu_incmd_address_i     (tmcu_incmd_address_i),
      .tmcu_incmd_size_i        (tmcu_incmd_size_i),
      .tmcu_incmd_ld_dest_reg_i (tmcu_incmd_ld_dest_reg_i),

      // PLACEHOLDER inputs — BCT insert
      .bct_insert_valid_i        (bct_insert_valid_i),
      .bct_insert_hw_cta_id_i    (bct_insert_hw_cta_id_i),
      .bct_insert_e_block_id_i   (bct_insert_e_block_id_i),
      .bct_insert_pending_reads_i(bct_insert_pending_reads_i),
      .bct_insert_pending_writes_i(bct_insert_pending_writes_i),

      // PLACEHOLDER inputs — BCT update
      .bct_update_valid_i        (bct_update_valid_i),
      .bct_update_e_block_id_i   (bct_update_e_block_id_i),
      .bct_update_is_write_i     (bct_update_is_write_i),
      .bct_update_reduce_count_i (bct_update_reduce_count_i)
  );

endmodule
