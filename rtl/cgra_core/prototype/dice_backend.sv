
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
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     hw_cta_pending_o,

    // CGRA Configuration Memory
    input  logic [DICE_MEM_DATA_WIDTH-1:0]                                                         cgra_cm0_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm0_chunk_en_i,
    input  logic [DICE_MEM_DATA_WIDTH-1:0]                                                         cgra_cm1_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm1_chunk_en_i,

    // CGRA Scan chain / bitstream interface
    input  logic        en_i; 
    input  logic        cgra_v_i,
    input  logic        cgra_bank_i,
    output logic        cgra_ready_o,
    output logic        cgra_busy_o,
    output logic [1:0]  cgra_bank_valid_o,
    output logic        cgra_prog_dout_o,
    output logic        cgra_prog_we_o
);

  // Dispatcher
  logic dispatch_busy;
  logic dispatcher_done;
  logic dispatch_fifo_empty;
  logic [NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic [NUM_LANES-1:0] rd_tid_valid;
  logic [DICE_TOTAL_REGS-1:0] full_reg_bitmap_lo;

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

  // CGRA write-back wires
  logic cgra_v_lo; // asserted lat cycles after RF read valid
  logic [DICE_TID_WIDTH-1:0] cgra_tid_lo;
  // One-hot TID bitmap for scoreboard writeback release
  logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] cgra_wb_tid_bitmap;
  assign cgra_wb_tid_bitmap = cgra_v_lo ? (DICE_NUM_MAX_THREADS_PER_CORE'(1'b1) << cgra_tid_lo) : '0;

  // CGRA output arrays (mirrors dice_cgra_rf pattern)
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_ext_data_lo [0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
  logic                           cgra_ext_pred_lo [0:DICE_NUM_PRED-1];

  // Packed writeback bus for dice_rf_ctrl (layout matches dice_cgra_rf)
  logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] cgra_data_li;

  always_comb begin
    cgra_data_li = '0;
    for (int j = 0; j < DICE_NUM_BANKS; j++) begin
      cgra_data_li[j*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] = cgra_ext_data_lo[j];
    end
    cgra_data_li[DICE_NUM_BANKS*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]       = cgra_ext_data_lo[DICE_NUM_BANKS];
    cgra_data_li[(DICE_NUM_BANKS+1)*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]   = {{(DICE_REG_DATA_WIDTH-1){1'b0}}, cgra_ext_pred_lo[0]};
    cgra_data_li[(DICE_NUM_BANKS+2)*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]   = {{(DICE_REG_DATA_WIDTH-1){1'b0}}, cgra_ext_pred_lo[1]};
  end

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
      .wb_valid(cgra_v_lo),                    // CGRA writeback pulse (lat-shifted RF read valid)
      .wb_tid_bitmap(cgra_wb_tid_bitmap),      // one-hot TID that just completed
      .dispatch_fifo_pop(rf_rd_ready_lo),      // advance FIFO when RF ctrl can accept next TID
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(rd_tid_valid),
      .full_reg_bitmap_o(full_reg_bitmap_lo),
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
      .rd_bitmap_i(full_reg_bitmap_lo),
      .rd_data_o(rd_data_lo),
      .rf_rd_valid_o(rf_rd_valid_lo),
      .tid_o        (cgra_tid_li),

      // Predicate output
      .pred_o(pred_lo),

      // Write Interface — CGRA
      .cgra_tid_i(cgra_tid_lo),
      .cgra_data_i(cgra_data_li),
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
        ,.reset_i(rst_i)   
        
        ,.latency (fdr_if_i.data.metadata.lat) // 

        ,.in_data (cgra_tid_li) // as if it comes out of the cgra
        ,.out_data (cgra_tid_lo)
        );

    shift_reg
        #(.WIDTH          (DICE_TOTAL_REGS)
            ,.MAX_PIPE_STAGE (128+1) //
        )
        WB_MAP_SHIFT
        (.clk_i(clk_i)
        ,.reset_i(rst_i)

        ,.latency (fdr_if_i.data.metadata.lat+1) //

        ,.in_data (fdr_if_i.data.metadata.out_regs_bitmap) //straight from metadata
        ,.out_data (wb_map_li) //
        );

  // CGRA valid: asserted `lat` cycles after the RF read produces valid data.
  // Replaces a direct ready signal from mini_dice (which has no such output).
  shift_reg
      #(.WIDTH          (1)
       ,.MAX_PIPE_STAGE (128)
      )
      CGRA_V_SHIFT
      (.clk_i   (clk_i)
      ,.reset_i (rst_i)
      ,.latency (fdr_if_i.data.metadata.lat)
      ,.in_data (rf_rd_valid_lo)   // pulse when RF read data is presented to CGRA
      ,.out_data(cgra_v_lo)        // pulse to RF ctrl to trigger write-back
      );

  
  // =========================================================================
  // CGRA Instantiation
  // =========================================================================
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo; // TODO: Connect to MSHR
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo;

  dice_cgra_subs u_dice_cgra_subs (
      .clk_i   (clk_i),
      .reset_i (rst_i),
      .en_i    (1'b1),   // TODO: connect to top-level enable when available

      // Configuration memory — driven from external IOs
      .cm0_data_i      (cgra_cm0_data_i),
      .cm0_chunk_en_i  (cgra_cm0_chunk_en_i),
      .cm1_data_i      (cgra_cm1_data_i),
      .cm1_chunk_en_i  (cgra_cm1_chunk_en_i),

      // Scan-chain / bitstream interface — driven from external IOs
      .v_i          (cgra_v_i),
      .bank_i       (cgra_bank_i),
      .ready_o      (cgra_ready_o),
      .busy_o       (cgra_busy_o),
      .bank_valid_o (cgra_bank_valid_o),
      .prog_dout_o  (cgra_prog_dout_o),
      .prog_we_o    (cgra_prog_we_o),

      // Register file reads → CGRA data inputs (unpacked from rd_data_lo)
      .ext_data_i_0  (rd_data_lo[ 0*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_1  (rd_data_lo[ 1*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_2  (rd_data_lo[ 2*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_3  (rd_data_lo[ 3*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_4  (rd_data_lo[ 4*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_5  (rd_data_lo[ 5*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_6  (rd_data_lo[ 6*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_7  (rd_data_lo[ 7*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_8  (rd_data_lo[ 8*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_9  (rd_data_lo[ 9*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_10 (rd_data_lo[10*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_11 (rd_data_lo[11*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_12 (rd_data_lo[12*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_13 (rd_data_lo[13*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_14 (rd_data_lo[14*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .ext_data_i_15 (rd_data_lo[15*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),

      // CGRA data outputs → register file writeback
      .ext_data_o_0  (cgra_ext_data_lo[0]),
      .ext_data_o_1  (cgra_ext_data_lo[1]),
      .ext_data_o_2  (cgra_ext_data_lo[2]),
      .ext_data_o_3  (cgra_ext_data_lo[3]),
      .ext_data_o_4  (cgra_ext_data_lo[4]),
      .ext_data_o_5  (cgra_ext_data_lo[5]),
      .ext_data_o_6  (cgra_ext_data_lo[6]),
      .ext_data_o_7  (cgra_ext_data_lo[7]),
      .ext_data_o_8  (cgra_ext_data_lo[8]),
      .ext_data_o_9  (cgra_ext_data_lo[9]),
      .ext_data_o_10 (cgra_ext_data_lo[10]),
      .ext_data_o_11 (cgra_ext_data_lo[11]),
      .ext_data_o_12 (cgra_ext_data_lo[12]),
      .ext_data_o_13 (cgra_ext_data_lo[13]),
      .ext_data_o_14 (cgra_ext_data_lo[14]),
      .ext_data_o_15 (cgra_ext_data_lo[15]),

      // Predicate register reads → CGRA predicate inputs
      .ext_pred_i_0 (pred_lo[0]),
      .ext_pred_i_1 (pred_lo[1]),

      // CGRA predicate outputs → predicate register writeback
      .ext_pred_o_0 (cgra_ext_pred_lo[0]),
      .ext_pred_o_1 (cgra_ext_pred_lo[1]),

      // Memory outputs — internal, to be connected when mem interface is added
      .mem_data_o (cgra_mem_data_lo),
      .mem_addr_o (cgra_mem_addr_lo)
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
