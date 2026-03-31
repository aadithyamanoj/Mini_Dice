`timescale 1ns/1ps
import "DPI-C" context function void dice_vector_mul_bitstream_init(
    input string bitstream_file
);
import "DPI-C" context function void dice_vector_mul_bitstream_get_chunk(
    input int unsigned chunk_idx,
    output int unsigned w0,
    output int unsigned w1,
    output int unsigned w2,
    output int unsigned w3,
    output int unsigned w4,
    output int unsigned w5,
    output int unsigned w6,
    output int unsigned w7,
    output int unsigned w8,
    output int unsigned w9,
    output int unsigned w10,
    output int unsigned w11,
    output int unsigned w12,
    output int unsigned w13,
    output int unsigned w14,
    output int unsigned w15
);

module tb_dice_cgra_rf_vector_mul;
  import dice_pkg::*;
  import DE_pkg::*;
  import dice_frontend_pkg::*;
  import cgra_test_pkg::*;

  localparam time CLK_PERIOD = 20000;
  localparam int RESET_CYCLES      = 10;
  localparam int POST_RESET_CYCLES = 10;
  localparam int TIMEOUT_CYCLES    = 30000;
  localparam int CHUNK_COUNT       = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                     / DICE_MEM_DATA_WIDTH;
  localparam int WORDS_PER_CHUNK   = DICE_MEM_DATA_WIDTH / 32;
  localparam int RF_WRITE_SETTLE   = 3;
  localparam int CGRA_LATENCY      = 15;
  localparam int WRITEBACK_SETTLE  = 3;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/home/jami3jun/Desktop/minidice/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

  logic clk_i;
  logic rst_i;

  // FDR interface — drives the dispatcher inside dice_backend.
  // Replaces the old rd_tid_valid_i / rd_tid_i signals: the dispatcher now
  // generates TIDs from active_mask and delivers them to the RF controller.
  fdr_if fdr_bus ();

  // CGRA configuration memory (renamed from cm0/cm1 to cgra_cm0/cm1)
  logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm0_data_i;
  logic [CHUNK_COUNT-1:0]         cgra_cm0_chunk_en_i;
  logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm1_data_i;
  logic [CHUNK_COUNT-1:0]         cgra_cm1_chunk_en_i;

  // CGRA scan-chain / programming interface (same signals, renamed prefix)
  logic                           cgra_v_i;
  logic                           cgra_bank_i;
  logic                           cgra_ready_o;
  logic                           cgra_busy_o;
  logic [1:0]                     cgra_bank_valid_o;
  logic                           cgra_prog_dout_o;
  logic                           cgra_prog_we_o;

  // Memory response interface: replaces the old ldst_wr_i / ldst_valid_i path.
  // Used to preload the RF with test data before dispatching.
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                    mem_rsp_base_tid_i;
  logic [TID_BITMAP_WIDTH-1:0]                                          mem_rsp_tid_bitmap_i;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                       mem_rsp_ld_dest_reg_i;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] mem_rsp_address_map_i;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                       mem_rsp_data_i;
  logic                                                                  mem_rsp_valid_i;

  // BCT outputs (drain only)
  logic                               eblock_commit_valid_o;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]    eblock_commit_id_o;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_pending_o;

  integer cycle_count;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_cgra_rf_vector_mul, "+struct", "+mda");  // DUT: dice_backend
  end

  // DUT: dice_backend — contains dispatcher + RF ctrl + CGRA.
  // TIDs are now generated internally by the dispatcher via fdr_if.
  dice_backend dut (
      .clk_i                 (clk_i),
      .rst_i                 (rst_i),
      .fdr_if_i              (fdr_bus),

      // TMCU: outputs left open, ready tied high
      .tmcu_valid_o          (),
      .tmcu_block_id_o       (),
      .tmcu_base_tid_o       (),
      .tmcu_tid_bitmap_o     (),
      .tmcu_write_enable_o   (),
      .tmcu_write_data_o     (),
      .tmcu_write_mask_o     (),
      .tmcu_address_o        (),
      .tmcu_size_o           (),
      .tmcu_ld_dest_reg_o    (),
      .tmcu_address_map_o    (),
      .tmcu_ready_i          (1'b1),

      // Memory response: preload RF before dispatch
      .mem_rsp_base_tid_i    (mem_rsp_base_tid_i),
      .mem_rsp_tid_bitmap_i  (mem_rsp_tid_bitmap_i),
      .mem_rsp_ld_dest_reg_i (mem_rsp_ld_dest_reg_i),
      .mem_rsp_address_map_i (mem_rsp_address_map_i),
      .mem_rsp_data_i        (mem_rsp_data_i),
      .mem_rsp_valid_i       (mem_rsp_valid_i),

      // BCT
      .eblock_commit_valid_o (eblock_commit_valid_o),
      .eblock_commit_id_o    (eblock_commit_id_o),
      .eblock_commit_ready_i (1'b1),
      .hw_cta_pending_o      (hw_cta_pending_o),

      // CGRA config memory
      .cgra_cm0_data_i       (cgra_cm0_data_i),
      .cgra_cm0_chunk_en_i   (cgra_cm0_chunk_en_i),
      .cgra_cm1_data_i       (cgra_cm1_data_i),
      .cgra_cm1_chunk_en_i   (cgra_cm1_chunk_en_i),

      // CGRA scan-chain
      .en_i                  (1'b1),
      .cgra_v_i              (cgra_v_i),
      .cgra_bank_i           (cgra_bank_i),
      .cgra_ready_o          (cgra_ready_o),
      .cgra_busy_o           (cgra_busy_o),
      .cgra_bank_valid_o     (cgra_bank_valid_o),
      .cgra_prog_dout_o      (cgra_prog_dout_o),
      .cgra_prog_we_o        (cgra_prog_we_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > TIMEOUT_CYCLES) begin
        $fatal(1, "TIMEOUT after %0d cycles", TIMEOUT_CYCLES);
      end
    end
  end

  task automatic clear_stream_inputs();
    begin
      cgra_cm0_data_i     = '0;
      cgra_cm0_chunk_en_i = '0;
      cgra_cm1_data_i     = '0;
      cgra_cm1_chunk_en_i = '0;
      cgra_v_i            = 1'b0;
      cgra_bank_i         = 1'b0;
    end
  endtask

  // Replaces clear_rf_inputs: the dispatcher now owns the RF control path.
  // We clear the fdr_bus and the mem_rsp inputs instead.
  task automatic clear_dispatcher_inputs();
    begin
      fdr_bus.valid         = 1'b0;
      fdr_bus.data          = '0;
      mem_rsp_valid_i       = 1'b0;
      mem_rsp_base_tid_i    = '0;
      mem_rsp_tid_bitmap_i  = '0;
      mem_rsp_ld_dest_reg_i = '0;
      mem_rsp_address_map_i = '0;
      mem_rsp_data_i        = '0;
    end
  endtask

  task automatic get_bitstream_chunk(
      input int unsigned chunk_idx,
      output logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data
  );
    int unsigned w [0:WORDS_PER_CHUNK-1];
    int word_idx;
    begin
      dice_vector_mul_bitstream_get_chunk(
          chunk_idx,
          w[0],  w[1],  w[2],  w[3],
          w[4],  w[5],  w[6],  w[7],
          w[8],  w[9],  w[10], w[11],
          w[12], w[13], w[14], w[15]
      );

      chunk_data = '0;
      for (word_idx = 0; word_idx < WORDS_PER_CHUNK; word_idx++) begin
        chunk_data[word_idx*32 +: 32] = w[word_idx];
      end
    end
  endtask

  task automatic stream_bitstream_to_bank(input logic target_bank);
    logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data;
    logic [CHUNK_COUNT-1:0]         chunk_mask;
    int unsigned chunk_idx;
    begin
      for (chunk_idx = 0; chunk_idx < CHUNK_COUNT; chunk_idx++) begin
        get_bitstream_chunk(chunk_idx, chunk_data);
        chunk_mask = '0;
        chunk_mask[chunk_idx] = 1'b1;

        @(negedge clk_i);
        if (target_bank == 1'b0) begin
          cgra_cm0_data_i     = chunk_data;
          cgra_cm0_chunk_en_i = chunk_mask;
          cgra_cm1_data_i     = '0;
          cgra_cm1_chunk_en_i = '0;
        end else begin
          cgra_cm0_data_i     = '0;
          cgra_cm0_chunk_en_i = '0;
          cgra_cm1_data_i     = chunk_data;
          cgra_cm1_chunk_en_i = chunk_mask;
        end

        @(posedge clk_i);
        @(negedge clk_i);
        clear_stream_inputs();
      end

      repeat (2) @(posedge clk_i);
      if (cgra_bank_valid_o[target_bank] !== 1'b1) begin
        $fatal(1, "Bank %0d did not become valid after chunk streaming", target_bank);
      end
    end
  endtask

  task automatic program_bank(input logic target_bank);
    begin
      cgra_bank_i = target_bank;
      wait (cgra_ready_o === 1'b1);

      @(negedge clk_i);
      cgra_v_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      cgra_v_i = 1'b0;

      wait (cgra_busy_o === 1'b1);
      wait (cgra_busy_o === 1'b0);
      repeat (CGRA_LATENCY) @(posedge clk_i);
    end
  endtask

  // Replaces build_ldst_write + send_ldst_write.
  // Writes GPR register reg_idx for TID=tid via dice_backend's mem_rsp interface.
  // Uses slot 0 of the coalesced command (tid_bitmap[0]=1, address_map[0]=0)
  // so the effective TID = base_tid + 0 = tid.  The assemble_ldst_wr function
  // inside dice_backend routes this to bank bank_select(tid, reg_idx) = reg_idx
  // (for small reg_idx values and TID=0).
  task automatic send_mem_rsp_write(
      input logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid,
      input int                                               reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0]                  data
  );
    begin
      wait (dut.ldst_ready_lo === 1'b1);
      @(negedge clk_i);
      mem_rsp_base_tid_i                        = tid;
      mem_rsp_ld_dest_reg_i                     = DICE_REG_ADDR_WIDTH'(reg_idx);
      mem_rsp_tid_bitmap_i                      = TID_BITMAP_WIDTH'(1);  // slot 0 active
      mem_rsp_address_map_i                     = '0;                    // TID offset = 0
      mem_rsp_data_i                            = '0;
      mem_rsp_data_i[DICE_REG_DATA_WIDTH-1:0]   = data;                  // slot 0 payload
      mem_rsp_valid_i                           = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_rsp_valid_i       = 1'b0;
      mem_rsp_base_tid_i    = '0;
      mem_rsp_ld_dest_reg_i = '0;
      mem_rsp_tid_bitmap_i  = '0;
      mem_rsp_address_map_i = '0;
      mem_rsp_data_i        = '0;
    end
  endtask

  // Replaces issue_rf_read.
  // Instead of manually driving rd_tid_i with a hardcoded TID, we drive the
  // fdr_if so the dispatcher generates TIDs from active_mask.
  //
  // fdr_bus.data (including metadata.lat) is kept alive after deasserting
  // valid so that CGRA_V_SHIFT and WB_MAP_SHIFT inside dice_backend see the
  // correct latency for the full duration of the pipeline.  The caller must
  // clear fdr_bus.data after the computation drains (post-writeback settle).
  task automatic issue_fdr_dispatch(
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,
      input logic [REG_NUM-1:0]                       in_regs,
      input logic [REG_NUM-1:0]                       out_regs
  );
    fdr_t pkt;
    begin
      pkt                          = '0;
      pkt.real_active_mask         = active_mask;
      pkt.metadata.in_regs_bitmap  = in_regs;
      pkt.metadata.out_regs_bitmap = out_regs;
      pkt.metadata.lat             = CGRA_LATENCY[7:0];

      @(negedge clk_i);
      fdr_bus.valid = 1'b1;
      fdr_bus.data  = pkt;
      // Hold valid until dice_backend asserts ready (dispatcher not busy)
      do @(posedge clk_i); while (!fdr_bus.ready);
      @(negedge clk_i);
      fdr_bus.valid = 1'b0;
      // data intentionally kept — see task comment above
    end
  endtask

  task automatic check_rf_read_data(
      input string test_name,
      input logic [7:0] expected[],
      input int count
  );
    begin
      // rf_rd_valid_o is a registered output that changes on posedge together
      // with rd_data_o.  @(posedge iff cond) evaluates the pre-edge value, so
      // it would trigger one cycle late (after data has gone X).  Use wait()
      // instead — it unblocks the moment the signal goes high — then sample at
      // the negedge (mid-cycle) while data is still held valid.
      wait (dut.u_dice_cgra_rf.rf_rd_valid_o === 1'b1);
      @(negedge clk_i);
      #1;
      for (int i = 0; i < count; i++) begin
        if (dut.u_dice_cgra_rf.rf_rd_data_lo[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] !== expected[i]) begin
          $fatal(1, "%s: RF read bank %0d expected %0d got %0d",
                 test_name, i, expected[i],
                 dut.u_dice_cgra_rf.rf_rd_data_lo[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
        end
        $display("%s: RF read bank %0d matched expected %0d",
                 test_name, i,
                 dut.u_dice_cgra_rf.rf_rd_data_lo[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
      end
    end
  endtask

  // Wait for one cgra_v_lo pulse then block until it clears.
  // Call twice in sequence to catch two distinct CGRA completions.
  task automatic wait_cgra_wb_pulse();
    wait (dut.cgra_v_lo === 1'b1);
    @(posedge clk_i);
    wait (dut.cgra_v_lo !== 1'b1);
  endtask

  task automatic check_cgra_outputs(
      input logic [7:0] expected [0:3]
  );
    begin
      // cgra_valid_lo renamed to cgra_v_lo in dice_backend;
      // cgra_ext_data_o renamed to cgra_ext_data_lo (internal wire, not a port)
      wait (dut.cgra_v_lo === 1'b1);
      for (int i = 0; i < 4; i++) begin
        if (^dut.u_dice_cgra_rf.cgra_ext_data_o[i] === 1'bX) begin
          $fatal(1, "CGRA output %0d contains X/Z (%b)", i, dut.u_dice_cgra_rf.cgra_ext_data_o[i]);
        end
        if (dut.u_dice_cgra_rf.cgra_ext_data_o[i] !== expected[i]) begin
          $fatal(1, "CGRA output %0d expected %0d got %0d",
                 i, expected[i], dut.u_dice_cgra_rf.cgra_ext_data_o[i]);
        end
      end
    end
  endtask

  task automatic reset_dut();
    begin
      rst_i = 1'b1;
      // latency is now carried per-dispatch in fdr_bus.data.metadata.lat
      clear_stream_inputs();
      clear_dispatcher_inputs();
      repeat (RESET_CYCLES) @(posedge clk_i);
      @(negedge clk_i);
      rst_i = 1'b0;
      repeat (POST_RESET_CYCLES) @(posedge clk_i);
    end
  endtask

  initial begin
    string bitstream_file;
    logic [7:0] a_values        [0:3];
    logic [7:0] b_values        [0:3];
    logic [7:0] expected_values [0:3];
    logic [7:0] rf_input_values [0:7];
    // After a compute dispatch: regs 0-3 hold expected_values, regs 4-7 still
    // hold b_values (not touched by writeback whose dst covers only regs 0-3).
    logic [7:0] wb_expected     [0:7];
    // Bitmaps are REG_NUM wide (not DICE_TOTAL_REGS) because they go through
    // the fdr_if metadata.  GPR bits occupy the same low positions in both.
    logic [REG_NUM-1:0]                       src_bitmap;
    logic [REG_NUM-1:0]                       dst_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;

    bitstream_file = DEFAULT_BITSTREAM_FILE;
    void'($value$plusargs("bitstream_bin=%s", bitstream_file));

    reset_dut();
    dice_vector_mul_bitstream_init(bitstream_file);

    stream_bitstream_to_bank(1'b0);
    stream_bitstream_to_bank(1'b1);
    program_bank(1'b0);

    load_directed_case(a_values, b_values, expected_values);
    for (int i = 0; i < 4; i++) begin
      rf_input_values[i]   = a_values[i];
      rf_input_values[i+4] = b_values[i];
    end

    // Permanent bitmap setup
    src_bitmap = '0;
    dst_bitmap = '0;
    for (int i = 0; i < 8; i++) src_bitmap[i] = 1'b1;  // read regs 0-7
    for (int i = 0; i < 4; i++) dst_bitmap[i] = 1'b1;  // write back regs 0-3

    // 8-bank expected for any "full readback after compute":
    //   banks 0-3 = CGRA result, banks 4-7 = b_values (untouched by writeback)
    for (int i = 0; i < 4; i++) wb_expected[i]   = expected_values[i];
    for (int i = 0; i < 4; i++) wb_expected[i+4] = b_values[i];

    // =====================================================================
    // Test 1: Single TID=0, directed case
    //   - verify source read (all 8 banks) and CGRA outputs
    //   - verify all 8 banks after writeback (fix: was only checking 4)
    // =====================================================================
    for (int i = 0; i < 8; i++) send_mem_rsp_write('0, i, rf_input_values[i]);
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    active_mask    = '0;
    active_mask[0] = 1'b1;

    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);
    check_rf_read_data("t1 source read", rf_input_values, 8);
    check_cgra_outputs(expected_values);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    // Read-only re-dispatch: verify all 8 banks (0-3=result, 4-7=b_values)
    issue_fdr_dispatch(active_mask, src_bitmap, '0);
    check_rf_read_data("t1 writeback read", wb_expected, 8);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    $display("[TB] Test 1 PASS: single-TID directed-case roundtrip (8-bank writeback verify)");

    // =====================================================================
    // Test 2: Multi-TID wave — active_mask[1:0]=2'b11
    //   Dispatcher must sequence TID=0 and TID=1 from one FDR packet.
    //   Both TIDs loaded with the same input data; both should produce the
    //   same expected output.
    // =====================================================================
    for (int i = 0; i < 8; i++) send_mem_rsp_write('0, i, rf_input_values[i]);
    for (int i = 0; i < 8; i++) send_mem_rsp_write('1, i, rf_input_values[i]);
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    active_mask    = '0;
    active_mask[0] = 1'b1;
    active_mask[1] = 1'b1;

    // issue_fdr_dispatch returns when the dispatcher FIFO is empty, meaning
    // both TIDs have been popped by the RF ctrl and are in the CGRA pipeline.
    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);
    wait_cgra_wb_pulse();  // first TID writeback
    wait_cgra_wb_pulse();  // second TID writeback
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    active_mask = '0; active_mask[0] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, '0);
    check_rf_read_data("t2 TID0 readback", wb_expected, 8);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    active_mask = '0; active_mask[1] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, '0);
    check_rf_read_data("t2 TID1 readback", wb_expected, 8);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    $display("[TB] Test 2 PASS: multi-TID wave (TID0+TID1 in one FDR packet) both computed and verified");

    // =====================================================================
    // Test 3: Scoreboard stall
    //   Wave B re-dispatches TID=0 with overlapping registers while wave A
    //   is still in-flight in the CGRA pipeline.  The dispatcher detects a
    //   collision and stalls TID=0 in the thread FIFO until wave A's
    //   cgra_v_lo writeback pulse clears the scoreboard entry.
    //   issue_fdr_dispatch naturally covers the stall: it loops on
    //   fdr_bus.ready (= ~dispatch_busy) which stays low until the
    //   dispatcher reaches DONE — which only happens after the scoreboard
    //   releases and the FIFO empties.
    // =====================================================================
    for (int i = 0; i < 8; i++) send_mem_rsp_write('0, i, rf_input_values[i]);
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    active_mask    = '0;
    active_mask[0] = 1'b1;

    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);  // wave A
    // Wave A's TID=0 is now in the CGRA pipeline; scoreboard has regs 0-7
    // reserved for TID=0.  Dispatching wave B immediately triggers a collision.
    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);  // wave B — stalls
    // issue_fdr_dispatch for wave B returned, meaning the stall resolved:
    // wave A's writeback fired, scoreboard released, wave B was dispatched.
    // Wave B's TID=0 is now in the CGRA pipeline.
    wait_cgra_wb_pulse();  // wave B CGRA completion
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    $display("[TB] Test 3 PASS: scoreboard stall on TID=0 re-dispatch correctly resolved after wave A writeback");

    // =====================================================================
    // Test 4: Back-to-back non-conflicting dispatches
    //   Wave A dispatches TID=0; wave B dispatches TID=1 immediately after
    //   wave A's dispatcher reaches DONE (TID=0 in CGRA pipeline).
    //   TID=1 has no scoreboard entry so it proceeds without collision;
    //   both TIDs are in-flight in the CGRA simultaneously.
    // =====================================================================
    for (int i = 0; i < 8; i++) send_mem_rsp_write('0, i, rf_input_values[i]);
    for (int i = 0; i < 8; i++) send_mem_rsp_write('1, i, rf_input_values[i]);
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    active_mask = '0; active_mask[0] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);  // wave A: TID=0
    // TID=0 is in the CGRA pipeline; scoreboard has TID=0's regs reserved.
    // TID=1 has no scoreboard entry — should pass collision check immediately.
    active_mask = '0; active_mask[1] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, dst_bitmap);  // wave B: TID=1
    // Both TID=0 and TID=1 are in-flight; wait for both writebacks.
    wait_cgra_wb_pulse();
    wait_cgra_wb_pulse();
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    active_mask = '0; active_mask[0] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, '0);
    check_rf_read_data("t4 TID0 readback", wb_expected, 8);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    active_mask = '0; active_mask[1] = 1'b1;
    issue_fdr_dispatch(active_mask, src_bitmap, '0);
    check_rf_read_data("t4 TID1 readback", wb_expected, 8);
    repeat (WRITEBACK_SETTLE) @(posedge clk_i);
    fdr_bus.data = '0;

    $display("[TB] Test 4 PASS: back-to-back non-conflicting dispatches (TID0 then TID1) verified");

    $display("[TB] ALL TESTS PASSED");
    $finish;
  end

endmodule
