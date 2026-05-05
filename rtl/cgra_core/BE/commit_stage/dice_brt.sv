module dice_brt
  import dice_pkg::*;
  import DE_pkg::*;
(
  input  logic clk_i,
  input  logic rst_i,

  // Dispatcher handshake — latch insert metadata and generate BCT insert
  input  logic                               fdr_valid_i,
  input  logic                               dispatch_busy_i,
  input  logic [DICE_EBLOCK_ID_WIDTH-1:0]    fdr_e_block_id_i,
  input  logic [PENDING_MEM_COUNT_WIDTH-1:0] fdr_pending_reads_i,
  input  logic [PENDING_MEM_COUNT_WIDTH-1:0] fdr_pending_stores_i,

  // Latched dispatch e_block_id — exposed for use by dice_cgra_rf
  output logic [DICE_EBLOCK_ID_WIDTH-1:0]    dispatch_e_block_id_o,

  // Retire signals from dice_cgra_rf (load completions)
  input  logic [DICE_NUM_BANKS-1:0]                           ldst_pop_i,
  input  logic [DICE_NUM_BANKS-1:0][DICE_EBLOCK_ID_WIDTH-1:0] ldst_pop_e_block_id_i,
  input  logic                                                 ldst_special_pop_i,
  input  logic [DICE_EBLOCK_ID_WIDTH-1:0]                     ldst_special_pop_e_block_id_i,

  // Store retire signals from mem_req_fifo
  input  logic                               store_retire_valid_i,
  input  logic [DICE_EBLOCK_ID_WIDTH-1:0]    store_retire_e_block_id_i,
  input  logic                               exec_retire_valid_i,
  input  logic [DICE_EBLOCK_ID_WIDTH-1:0]    exec_retire_e_block_id_i,

  // Commit interface
  output logic                               eblock_commit_valid_o,
  output logic [DICE_EBLOCK_ID_WIDTH-1:0]    eblock_commit_id_o,
  input  logic                               eblock_commit_ready_i,
  output logic                               hw_cta_pending_o
);

  // =========================================================================
  // BCT Insert Pipeline
  // =========================================================================

  logic [DICE_EBLOCK_ID_WIDTH-1:0] dispatch_e_block_id;
  logic [PENDING_MEM_COUNT_WIDTH-1:0] dispatch_pending_reads;
  logic [PENDING_MEM_COUNT_WIDTH-1:0] dispatch_pending_stores;
  logic                               bct_insert_valid_r;

  // Latch e-block metadata whenever the dispatcher accepts a new e-block.
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      dispatch_e_block_id    <= '0;
      dispatch_pending_reads <= '0;
      dispatch_pending_stores <= '0;
    end else if (fdr_valid_i && ~dispatch_busy_i) begin
      dispatch_e_block_id    <= fdr_e_block_id_i;
      dispatch_pending_reads <= fdr_pending_reads_i;
      dispatch_pending_stores <= fdr_pending_stores_i;
    end
  end

  // BCT insert fires one cycle after the dispatcher accepts, when the latched
  // values are stable.  This still guarantees the BCT entry exists before any
  // load can complete.
  always_ff @(posedge clk_i) begin
    if (rst_i) bct_insert_valid_r <= 1'b0;
    else       bct_insert_valid_r <= fdr_valid_i && ~dispatch_busy_i;
  end

  assign dispatch_e_block_id_o = dispatch_e_block_id;

  // =========================================================================
  // Retire Bundle Assembly + FIFO
  // =========================================================================

  localparam int RETIRE_EVT_W    = 1 + DICE_EBLOCK_ID_WIDTH;
  localparam int RETIRE_EVT_CNT  = DICE_NUM_BANKS + 1;
  localparam int RETIRE_BUNDLE_W = RETIRE_EVT_CNT * RETIRE_EVT_W;
  localparam int RETIRE_REDUCE_COUNT_W = 2**DICE_HW_CTA_ID_WIDTH;

  logic [RETIRE_EVT_CNT-1:0][RETIRE_EVT_W-1:0] retire_bundle_li;
  logic [RETIRE_EVT_CNT-1:0][RETIRE_EVT_W-1:0] retire_bundle_words_lo;
  logic [RETIRE_BUNDLE_W-1:0] retire_bundle_bits_li, retire_bundle_bits_lo;
  logic retire_bundle_valid_li, retire_bundle_v_lo, retire_bundle_yumi_li;

  always_comb begin
    retire_bundle_li = '0;
    for (int i = 0; i < DICE_NUM_BANKS; i++) begin
      retire_bundle_li[i] = {ldst_pop_i[i], ldst_pop_e_block_id_i[i]};
    end
    retire_bundle_li[DICE_NUM_BANKS] = {ldst_special_pop_i, ldst_special_pop_e_block_id_i};
  end

  assign retire_bundle_bits_li  = retire_bundle_li;
  assign retire_bundle_words_lo = retire_bundle_bits_lo;
  assign retire_bundle_valid_li = |ldst_pop_i | ldst_special_pop_i;

  localparam int RETIRE_BUDLE_DEPTH = NUM_MEM_PORTS * DICE_NUM_MAX_THREADS_PER_CORE;

  bsg_fifo_1r1w_small #(
    .width_p(RETIRE_BUNDLE_W),
    .els_p  (RETIRE_BUDLE_DEPTH)
  ) retire_bundle_fifo (
    .clk_i  (clk_i),
    .reset_i(rst_i),
    .v_i    (retire_bundle_valid_li),
    .ready_o(),
    .data_i (retire_bundle_bits_li),
    .v_o    (retire_bundle_v_lo),
    .data_o (retire_bundle_bits_lo),
    .yumi_i (retire_bundle_yumi_li)
  );

  // =========================================================================
  // Retire Event Serializer
  // =========================================================================

  logic retire_ser_ready_lo, retire_ser_v_lo, retire_ser_yumi_li;
  logic [RETIRE_EVT_W-1:0] retire_ser_data_lo;
  logic retire_evt_valid_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] retire_evt_e_block_id_lo;
  logic [RETIRE_REDUCE_COUNT_W-1:0] retire_evt_reduce_count_li;

  bsg_parallel_in_serial_out #(
    .width_p(RETIRE_EVT_W),
    .els_p  (RETIRE_EVT_CNT)
  ) retire_evt_serializer (
    .clk_i      (clk_i),
    .reset_i    (rst_i),
    .valid_i    (retire_bundle_v_lo),
    .data_i     (retire_bundle_words_lo),
    .ready_and_o(retire_ser_ready_lo),
    .valid_o    (retire_ser_v_lo),
    .data_o     (retire_ser_data_lo),
    .yumi_i     (retire_ser_yumi_li)
  );

  assign retire_bundle_yumi_li    = retire_bundle_v_lo & retire_ser_ready_lo;
  assign retire_ser_yumi_li       = retire_ser_v_lo;
  assign retire_evt_valid_lo      = retire_ser_v_lo & retire_ser_data_lo[RETIRE_EVT_W-1];
  assign retire_evt_e_block_id_lo = retire_ser_data_lo[DICE_EBLOCK_ID_WIDTH-1:0];
  assign retire_evt_reduce_count_li = RETIRE_REDUCE_COUNT_W'(1);

  // =========================================================================
  // Block Commit Table
  // =========================================================================

  block_commit_table #(
    .R_W(PENDING_MEM_COUNT_WIDTH),
    .S_W(PENDING_MEM_COUNT_WIDTH)
  ) u_block_commit_table (
    .clk_i(clk_i),
    .rst_i(rst_i),

    // Insert interface
    .insert_valid_i         (bct_insert_valid_r),
    .insert_e_block_id_i    (dispatch_e_block_id),
    .insert_pending_reads_i (dispatch_pending_reads),
    .insert_pending_stores_i(dispatch_pending_stores),

    // Read update interface — one retire event per serializer output
    .update_valid_i       (retire_evt_valid_lo),
    .update_e_block_id_i  (retire_evt_e_block_id_lo),
    .update_reduce_count_i(retire_evt_reduce_count_li),

    // Store update interface — direct from mem_req_fifo.
    .store_update_valid_i      (store_retire_valid_i),
    .store_update_e_block_id_i (store_retire_e_block_id_i),
    .exec_update_valid_i       (exec_retire_valid_i),
    .exec_update_e_block_id_i  (exec_retire_e_block_id_i),

    // Commit interface
    .pop_valid_o     (eblock_commit_valid_o),
    .pop_e_block_id_o(eblock_commit_id_o),
    .pop_ready_i     (eblock_commit_ready_i),

    // Status
    .hw_cta_pending_o(hw_cta_pending_o)
  );

endmodule
