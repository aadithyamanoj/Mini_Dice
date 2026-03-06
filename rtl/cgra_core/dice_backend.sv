
module dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // FDR interface (from frontend)
    fdr_if.slave fdr_if_i,

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

    // Block commit table outputs
    output logic                                    eblock_commit_valid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0]         eblock_commit_id_o,
    input  logic                                    eblock_commit_ready_i,
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     hw_cta_pending_o
);

  // Dispatcher
  logic dispatch_busy;
  logic dispatcher_done;
  logic dispatch_fifo_empty;
  logic [NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic [NUM_LANES-1:0] rd_tid_valid;
  logic [`DICE_GPR_NUM-1:0] gpr_bitmap;

  // Register File Control
  logic rf_rd_valid_lo;
  logic rf_rd_ready_lo;

  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] rd_data_lo;
  logic [DICE_NUM_PRED-1:0] pred_lo;


  // LDST write interface — pack module inputs into cache_wr_cmd
  cache_wr_cmd                    ldst_cmd;
  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_lo;
  logic                           ldst_valid_lo;
  logic                           ldst_ready_lo;


  logic [DICE_TID_WIDTH-1:0] cgra_tid_li; // out of rf, in to shift reg and cgra

  logic [DICE_TOTAL_REGS-1:0] wb_map_li; // shifted form metadata, goes to rf


  // CGRA write-back wires (undriven for now)
  logic                                          cgra_v_lo;
  logic [DICE_TOTAL_REGS*DICE_REG_DATA_WIDTH-1:0] cgra_data_lo;
  logic [DICE_TID_WIDTH-1:0]                     cgra_tid_lo;

  // TMCU input-side wires (from CGRA)
  logic                              tmcu_incmd_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]   tmcu_incmd_block_id;
  logic [DICE_TID_WIDTH-1:0]         tmcu_incmd_tid;
  logic                              tmcu_incmd_write_enable;
  logic [DICE_DATA_WIDTH-1:0]        tmcu_incmd_write_data;
  logic [DICE_DATA_WIDTH/8-1:0]      tmcu_incmd_write_mask;
  logic [DICE_ADDR_WIDTH-1:0]        tmcu_incmd_address;
  logic [1:0]                        tmcu_incmd_size;
  logic [DICE_MAX_REG_WIDTH-1:0]     tmcu_incmd_ld_dest_reg;
  logic                              tmcu_incmd_ready;

  // Block Commit Table
  logic                                    bct_insert_valid;
  logic [DICE_HW_CTA_ID_WIDTH-1:0]        bct_insert_hw_cta_id;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]         bct_insert_e_block_id;
  logic [13:0]                             bct_insert_pending_reads;
  logic [13:0]                             bct_insert_pending_writes;

  logic                                    bct_update_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]         bct_update_e_block_id;
  logic                                    bct_update_is_write;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     bct_update_reduce_count;

  assign fdr_if_i.ready = ~dispatch_busy;

  assign ldst_cmd.outcmd_base_tid    = mem_rsp_base_tid_i;
  assign ldst_cmd.outcmd_tid_bitmap  = mem_rsp_tid_bitmap_i;
  assign ldst_cmd.outcmd_ld_dest_reg = mem_rsp_ld_dest_reg_i;
  assign ldst_cmd.outcmd_address_map = mem_rsp_address_map_i;
  assign ldst_cmd.core_rsp_data      = mem_rsp_data_i;

  assign ldst_wr_lo    = ldst_cmd;
  assign ldst_valid_lo = mem_rsp_valid_i;

  // =========================================================================
  // Dispatcher
  // =========================================================================

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .ld_dest_regs(fdr_if_i.data.metadata.ld_dest_regs),
      .input_register_bitmap(fdr_if_i.data.metadata.in_regs_bitmap),
      .active_mask(fdr_if_i.data.real_active_mask),
      .fetch_done(fdr_if_i.valid),
      .wb_valid(),              // comes from cgra
      .wb_tid_bitmap(),         // comes from cgra
      .dispatch_fifo_pop('1),   // cgra ready
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(rd_tid_valid),
      .gpr_bitmap_o(gpr_bitmap),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done(dispatcher_done)
  );

  // =========================================================================
  // Register File Control
  // =========================================================================

  dice_rf_ctrl u_dice_rf_ctrl (
      .clk_i(clk_i),
      .reset_i(rst_i),

      // Read Interface
      .rd_tid_valid_i(rd_tid_valid),
      .rd_tid_ready_o(rf_rd_ready_lo),
      .rd_en_i(rd_tid_valid),
      .rd_tid_i(rd_tid),
      .rd_bitmap_i(gpr_bitmap),
      .rd_data_o(rd_data_lo),
      .rf_rd_valid_o(rf_rd_valid_lo),
      .tid_o        (cgra_tid_li)

      // Predicate output
      .pred_o(pred_lo),

      // Write Interface — CGRA
      .cgra_tid_i(cgra_tid_lo),
      .cgra_data_i(cgra_data_lo),
      .wr_bitmap_i(wb_map_li),
      .cgra_valid_i(cgra_v_lo),

      // Write Interface — LDST
      .ldst_wr_i(ldst_wr_lo),
      .ldst_valid_i(ldst_valid_lo),
      .ldst_ready_o(ldst_ready_lo)
  );

    shift_reg
        #(.WIDTH          (DICE_TID_WIDTH)
         ,.MAX_PIPE_STAGE (128) // 
        )
        TID_SHIFT
        (.clk_i(clk_i)
        ,.reset_i(reset_i)   
        
        ,.latency (fdr_if_i.data.metadata.lat) // 

        ,.in_data (cgra_tid_li) // as if it comes out of the cgra
        ,.out_data (cgra_tid_lo)
        );
    
    shif_reg
        #(.WIDTH          (DICE_TOTAL_REGS)
         ,.MAX_PIPE_STAGE (128+1) // 
        )
        TID_SHIFT
        (.clk_i(clk_i)
        ,.reset_i(reset_i)   
        
        ,.latency (fdr_if_i.data.metadata.lat+1) // 

        ,.in_data (fdr_if_i.data.metadata.out_regs_bitmap) //straight from metadata
        ,.out_data (wb_map_li) //
        );

  // =========================================================================
  // Temporal Coalescing Unit (TMCU)
  // =========================================================================

  temporal_coalescing_unit u_temporal_coalescing_unit (
      .clk(clk_i),
      .rst(rst_i),

      // Input memory commands (from CGRA)
      .incmd_valid       (tmcu_incmd_valid),
      .incmd_block_id    (tmcu_incmd_block_id),
      .incmd_tid         (tmcu_incmd_tid),
      .incmd_write_enable(tmcu_incmd_write_enable),
      .incmd_write_data  (tmcu_incmd_write_data),
      .incmd_write_mask  (tmcu_incmd_write_mask),
      .incmd_address     (tmcu_incmd_address),
      .incmd_size        (tmcu_incmd_size),
      .incmd_ld_dest_reg (tmcu_incmd_ld_dest_reg),
      .incmd_ready       (tmcu_incmd_ready),

      // Output memory commands (to external memory)
      .outcmd_valid       (tmcu_valid_o),
      .outcmd_block_id    (tmcu_block_id_o),
      .outcmd_base_tid    (tmcu_base_tid_o),
      .outcmd_tid_bitmap  (tmcu_tid_bitmap_o),
      .outcmd_write_enable(tmcu_write_enable_o),
      .outcmd_write_data  (tmcu_write_data_o),
      .outcmd_write_mask  (tmcu_write_mask_o),
      .outcmd_address     (tmcu_address_o),
      .outcmd_size        (tmcu_size_o),
      .outcmd_ld_dest_reg (tmcu_ld_dest_reg_o),
      .outcmd_address_map (tmcu_address_map_o),
      .outcmd_ready       (tmcu_ready_i)
  );

  // =========================================================================
  // Block Commit Table
  // =========================================================================

  block_commit_table u_block_commit_table (
      .clk                 (clk_i),
      .rst                 (rst_i),

      // Insert interface
      .insert_valid        (bct_insert_valid),
      .insert_hw_cta_id    (bct_insert_hw_cta_id),
      .insert_e_block_id   (bct_insert_e_block_id),
      .insert_pending_reads(bct_insert_pending_reads),
      .insert_pending_writes(bct_insert_pending_writes),

      // Update interface
      .update_valid        (bct_update_valid),
      .update_e_block_id   (bct_update_e_block_id),
      .update_is_write     (bct_update_is_write),
      .update_reduce_count (bct_update_reduce_count),

      // Commit interface
      .pop_valid           (eblock_commit_valid_o),
      .pop_e_block_id      (eblock_commit_id_o),
      .pop_ready           (eblock_commit_ready_i),

      // Status
      .hw_cta_pending      (hw_cta_pending_o)
  );

endmodule
