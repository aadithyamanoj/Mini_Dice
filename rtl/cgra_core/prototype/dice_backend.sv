`define DICE_RF_DEBUG
module dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // FDR interface fields (flattened for synthesis friendliness)
    input  logic fdr_valid_i,
    input  logic [$bits(fdr_t)-1:0] fdr_data_i,
    output logic fdr_ready_o,

    // TMCU -> External Memory Interface
    // No more TMCU
    // output logic tmcu_valid_o,
    // output logic [DICE_EBLOCK_ID_WIDTH-1:0] tmcu_block_id_o,
    // output logic [DICE_TID_WIDTH-1:0] tmcu_base_tid_o,
    // output logic [DICE_TID_BITMAP_WIDTH-1:0] tmcu_tid_bitmap_o,
    // output logic tmcu_write_enable_o,
    // output logic [DICE_CACHE_LINE_SIZE*8-1:0] tmcu_write_data_o,
    // output logic [DICE_CACHE_LINE_SIZE-1:0] tmcu_write_mask_o,
    // output logic [DICE_ADDR_WIDTH-1:0] tmcu_address_o,
    // output logic [1:0] tmcu_size_o,
    // output logic [DICE_MAX_REG_WIDTH-1:0] tmcu_ld_dest_reg_o,
    // output logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] tmcu_address_map_o,
    // input logic tmcu_ready_i,

    // Memory Response Input (cache_wr_cmd fields)
    input logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] mem_rsp_base_tid_i,
    // input logic [TID_BITMAP_WIDTH-1:0] mem_rsp_tid_bitmap_i,
    input logic [DICE_REG_ADDR_WIDTH-1:0] mem_rsp_ld_dest_reg_i,
    // input  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]        mem_rsp_address_map_i,
    input logic [(CACHE_LINE_SIZE*8)-1:0] mem_rsp_data_i,
    input logic mem_rsp_valid_i,

    // Block commit table outputs
    output logic                               eblock_commit_valid_o,
    output logic [   DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_o,
    input  logic                               eblock_commit_ready_i,
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_pending_o,

    // CGRA Configuration Memory
    input logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm0_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm0_chunk_en_i,
    input logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm1_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm1_chunk_en_i,

    // CGRA Scan chain / bitstream interface
    input  logic       en_i,
    input  logic       cgra_v_i,
    input  logic       cgra_bank_i,
    output logic       cgra_ready_o,
    output logic       cgra_busy_o,
    output logic [1:0] cgra_bank_valid_o,
    output logic       cgra_prog_dout_o,
    output logic       cgra_prog_we_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_o_0,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_o_0,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_o_1,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_o_1,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_o_2,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_o_2,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_o_3,
    output logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_o_3
`ifdef DICE_RF_DEBUG
    , output logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_rd_data_o
    , output logic [DICE_NUM_PRED-1:0]                                        dbg_pred_o
    , output logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_launch_data_o
    , output logic [DICE_NUM_PRED-1:0]                                        dbg_pred_launch_o
    , output logic [((DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH)-1:0] dbg_cgra_data_o
    , output logic [DICE_TOTAL_REGS-1:0]                                      dbg_cgra_wr_bitmap_o
    , output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]               dbg_cgra_tid_o
    , output logic                                                            dbg_cgra_valid_o
    , output logic                                                            dbg_rf_rd_valid_o
`endif
);

  // Dispatcher
  logic                                            dispatch_busy;
  logic                                            dispatcher_done;
  logic                                            dispatch_fifo_empty;
  logic        [     NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic        [                    NUM_LANES-1:0] rd_tid_valid;
  logic        [              DICE_TOTAL_REGS-1:0] full_reg_bitmap_lo;
  fdr_t                                            fdr_data_li;

  // RF + CGRA wrapper outputs
  logic                                            rf_rd_ready_lo;
  logic                                            ldst_ready_lo;
  logic                                            cgra_v_lo;
  logic        [               DICE_TID_WIDTH-1:0] cgra_tid_lo;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_0;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_0;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_1;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_1;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_2;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_2;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_3;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_3;

  // LDST write interface — pack module inputs into cache_wr_cmd
  cache_wr_cmd                                     ldst_cmd;
  logic        [          $bits(cache_wr_cmd)-1:0] ldst_wr_lo;
  logic                                            ldst_valid_lo;

  // One-hot TID bitmap for scoreboard writeback release
  logic        [DICE_NUM_MAX_THREADS_PER_CORE-1:0] cgra_wb_tid_bitmap;
  assign cgra_wb_tid_bitmap = cgra_v_lo ? (DICE_NUM_MAX_THREADS_PER_CORE'(1'b1) << cgra_tid_lo) : '0;

  // Block Commit Table
  logic                               bct_insert_valid;
  logic [   DICE_HW_CTA_ID_WIDTH-1:0] bct_insert_hw_cta_id;
  logic [   DICE_EBLOCK_ID_WIDTH-1:0] bct_insert_e_block_id;
  logic [                       13:0] bct_insert_pending_reads;
  logic [                       13:0] bct_insert_pending_writes;

  logic                               bct_update_valid;
  logic [   DICE_EBLOCK_ID_WIDTH-1:0] bct_update_e_block_id;
  logic                               bct_update_is_write;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] bct_update_reduce_count;

  // TID → e_block_id LUT and latched dispatch metadata
  logic [DICE_EBLOCK_ID_WIDTH-1:0] tid_eblock_lut   [DICE_NUM_MAX_THREADS_PER_CORE];
  logic [DICE_EBLOCK_ID_WIDTH-1:0] dispatch_e_block_id;
  logic [                    13:0] dispatch_pending_reads;
  logic [                    13:0] dispatch_pending_writes;

  assign fdr_data_li         = fdr_data_i;
  assign fdr_ready_o        = ~dispatch_busy;

  assign ldst_cmd.tid       = mem_rsp_base_tid_i;
  assign ldst_cmd.data      = mem_rsp_data_i[DICE_REG_DATA_WIDTH-1:0];
  assign ldst_cmd.wr_bitmap = DICE_TOTAL_REGS'(1'b1) << mem_rsp_ld_dest_reg_i;

  assign ldst_wr_lo         = ldst_cmd;
  assign ldst_valid_lo      = mem_rsp_valid_i;
  assign cgra_mem_data_o_0  = cgra_mem_data_lo_0;
  assign cgra_mem_addr_o_0  = cgra_mem_addr_lo_0;
  assign cgra_mem_data_o_1  = cgra_mem_data_lo_1;
  assign cgra_mem_addr_o_1  = cgra_mem_addr_lo_1;
  assign cgra_mem_data_o_2  = cgra_mem_data_lo_2;
  assign cgra_mem_addr_o_2  = cgra_mem_addr_lo_2;
  assign cgra_mem_data_o_3  = cgra_mem_data_lo_3;
  assign cgra_mem_addr_o_3  = cgra_mem_addr_lo_3;

  // =========================================================================
  // Dispatcher → BCT Glue
  // =========================================================================
  // Latch e-block metadata and populate the TID LUT whenever the dispatcher
  // accepts a new e-block (valid handshake while not already dispatching).
  // Mirrors the dispatcher FSM's latch_inputs / start_new_cta condition.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      dispatch_e_block_id    <= '0;
      dispatch_pending_reads <= '0;
      dispatch_pending_writes <= '0;
      for (int i = 0; i < DICE_NUM_MAX_THREADS_PER_CORE; i++)
        tid_eblock_lut[i] <= '0;
    end else if (fdr_valid_i && ~dispatch_busy) begin
      dispatch_e_block_id    <= DICE_EBLOCK_ID_WIDTH'(fdr_data_li.schedule_eblock_id);
      dispatch_pending_reads <= 14'($countones(fdr_data_li.real_active_mask) *
                                    (NUM_MEM_PORTS - fdr_data_li.metadata.num_stores));
      dispatch_pending_writes <= 14'($countones(fdr_data_li.real_active_mask) *
                                     fdr_data_li.metadata.num_stores);
      for (int i = 0; i < DICE_NUM_MAX_THREADS_PER_CORE; i++) begin
        if (fdr_data_li.real_active_mask[i])
          tid_eblock_lut[i] <= DICE_EBLOCK_ID_WIDTH'(fdr_data_li.schedule_eblock_id);
      end
    end
  end

  // BCT insert: fires on dispatcher_done with the metadata latched above.
  // hw_cta_id hardwired to 0 — only one CTA in current config.
  assign bct_insert_valid          = dispatcher_done;
  assign bct_insert_e_block_id     = dispatch_e_block_id;
  assign bct_insert_hw_cta_id      = '0;
  assign bct_insert_pending_reads  = dispatch_pending_reads;
  assign bct_insert_pending_writes = dispatch_pending_writes;

  // BCT update: fires on every memory response; e_block_id resolved via LUT.
  // Each response completes one pending read (all CGRA memory responses are loads).
  assign bct_update_valid        = mem_rsp_valid_i;
  assign bct_update_e_block_id   = tid_eblock_lut[mem_rsp_base_tid_i];
  assign bct_update_is_write     = 1'b0;
  assign bct_update_reduce_count = (2**DICE_HW_CTA_ID_WIDTH)'(1);

  // =========================================================================
  // Dispatcher
  // =========================================================================

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .ld_dest_regs(fdr_data_li.metadata.ld_dest_regs),
      .input_register_bitmap(fdr_data_li.metadata.in_regs_bitmap),
      .active_mask(fdr_data_li.real_active_mask),
      .fetch_done(fdr_valid_i),
      .wb_valid(cgra_v_lo),  // CGRA writeback pulse (lat-shifted RF read valid)
      .wb_tid_bitmap(cgra_wb_tid_bitmap),  // one-hot TID that just completed
      .dispatch_fifo_pop(rf_rd_ready_lo),  // advance FIFO when RF ctrl can accept next TID
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(rd_tid_valid),
      .full_reg_bitmap_o(full_reg_bitmap_lo),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done(dispatcher_done)
  );

  // =========================================================================
  // Register File + CGRA Wrapper
  // =========================================================================

  dice_cgra_rf u_dice_cgra_rf (
      .clk_i  (clk_i),
      .reset_i(rst_i),
      .en_i   (1'b1),

      // Configuration memory
      .cm0_data_i    (cgra_cm0_data_i),
      .cm0_chunk_en_i(cgra_cm0_chunk_en_i),
      .cm1_data_i    (cgra_cm1_data_i),
      .cm1_chunk_en_i(cgra_cm1_chunk_en_i),

      // Scan chain / bitstream
      .v_i         (cgra_v_i),
      .bank_i      (cgra_bank_i),
      .ready_o     (cgra_ready_o),
      .busy_o      (cgra_busy_o),
      .bank_valid_o(cgra_bank_valid_o),
      .prog_dout_o (cgra_prog_dout_o),
      .prog_we_o   (cgra_prog_we_o),

      // Memory outputs (TODO: connect to MSHR)
      .mem_data_o_0(cgra_mem_data_lo_0),
      .mem_addr_o_0(cgra_mem_addr_lo_0),
      .mem_data_o_1(cgra_mem_data_lo_1),
      .mem_addr_o_1(cgra_mem_addr_lo_1),
      .mem_data_o_2(cgra_mem_data_lo_2),
      .mem_addr_o_2(cgra_mem_addr_lo_2),
      .mem_data_o_3(cgra_mem_data_lo_3),
      .mem_addr_o_3(cgra_mem_addr_lo_3),
      .mem_valid_o (cgra_v_lo),
      .cgra_tid_o  (cgra_tid_lo),

      // CGRA latency from instruction metadata
      .latency_i(fdr_data_li.metadata.lat),

      // RF read interface (from dispatcher)
      .rd_tid_valid_i(rd_tid_valid),
      .rd_tid_ready_o(rf_rd_ready_lo),
    //   .rd_en_i       (1'b1),
      .rd_tid_i      (rd_tid),
      .rd_bitmap_i   (full_reg_bitmap_lo),
      .wr_bitmap_i   (fdr_data_li.metadata.out_regs_bitmap),

      // LDST write interface
      .ldst_wr_i   (ldst_wr_lo),
      .ldst_valid_i(ldst_valid_lo),
      .ldst_ready_o(ldst_ready_lo)
`ifdef DICE_RF_DEBUG
      , .dbg_rf_rd_data_o(dbg_rf_rd_data_o)
      , .dbg_pred_o(dbg_pred_o)
      , .dbg_rf_launch_data_o(dbg_rf_launch_data_o)
      , .dbg_pred_launch_o(dbg_pred_launch_o)
      , .dbg_cgra_data_o(dbg_cgra_data_o)
      , .dbg_cgra_wr_bitmap_o(dbg_cgra_wr_bitmap_o)
      , .dbg_cgra_tid_o(dbg_cgra_tid_o)
      , .dbg_cgra_valid_o(dbg_cgra_valid_o)
      , .dbg_rf_rd_valid_o(dbg_rf_rd_valid_o)
`endif
  );

  // =========================================================================
  // Block Commit Table
  // =========================================================================

  block_commit_table u_block_commit_table (
      .clk_i(clk_i),
      .rst(rst_i),

      // Insert interface
      .insert_valid         (bct_insert_valid),
      .insert_hw_cta_id     (bct_insert_hw_cta_id),
      .insert_e_block_id    (bct_insert_e_block_id),
      .insert_pending_reads (bct_insert_pending_reads),
      .insert_pending_writes(bct_insert_pending_writes),

      // Update interface
      .update_valid       (bct_update_valid),
      .update_e_block_id  (bct_update_e_block_id),
      .update_is_write    (bct_update_is_write),
      .update_reduce_count(bct_update_reduce_count),

      // Commit interface
      .pop_valid     (eblock_commit_valid_o),
      .pop_e_block_id(eblock_commit_id_o),
      .pop_ready     (eblock_commit_ready_i),

      // Status
      .hw_cta_pending(hw_cta_pending_o)
  );

endmodule
