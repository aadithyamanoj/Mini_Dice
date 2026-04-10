`define DICE_RF_DEBUG
`timescale 1ns/1ps

import "DPI-C" context function void dice_vector_mul_bitstream_init(
    input string bitstream_file
);
import "DPI-C" context function void dice_vector_mul_bitstream_get_chunk(
    input  int unsigned chunk_idx,
    output int unsigned w0,  output int unsigned w1,  output int unsigned w2,  output int unsigned w3,
    output int unsigned w4,  output int unsigned w5,  output int unsigned w6,  output int unsigned w7,
    output int unsigned w8,  output int unsigned w9,  output int unsigned w10, output int unsigned w11,
    output int unsigned w12, output int unsigned w13, output int unsigned w14, output int unsigned w15
);

// =============================================================================
// tb_dice_backend_dispatch — extended dispatcher coverage for dice_backend
// =============================================================================
//
// Six tests built on top of the same vector-multiply infrastructure as
// tb_dice_backend_vector_mul, providing broader coverage of the dispatcher's
// TID-routing, active-mask gating, scoreboard reserve/release, and
// DONE→DISPATCHING (start_new_cta) transitions.
//
// Test 1  All-threads baseline         (all 16 threads, verifies every mul)
// Test 2  Partial mask — even TIDs     (half the threads; inactive TIDs
//                                       must keep their preloaded RF values)
// Test 3  Single-thread dispatch        (one TID, minimal dispatch path)
// Test 4  Back-to-back CTAs            (two sequential CTAs, distinct data;
//                                       exercises DONE→DISPATCHING + scoreboard
//                                       clear via start_new_cta)
// Test 5  RAW chain                    (CTA 2 reads CTA 1 RF outputs; verifies
//                                       RF write-then-read coherence across
//                                       sequential FDR dispatches)
// Test 6  ld_dest_regs nonzero         (sets ld_dest_regs[0]=bank 2 to exercise
//                                       the scoreboard ld_dest_regs_bitmap
//                                       reserve+CGRA-wb-release path; verifies
//                                       no deadlock and correct outputs)
//
// ── Note on scoreboard stall coverage ────────────────────────────────────────
// A multi-cycle scoreboard stall (collision held for >1 cycle) would require
// a thread's entry to have pending bits when that thread is *re-checked* in the
// same CTA.  Two design properties prevent this in the current backend:
//
//   (a) start_new_cta clears all scoreboard entries atomically on every
//       DONE→DISPATCHING transition, before any thread in the new CTA is
//       checked.
//   (b) NUM_SCOREBOARDS=1, CHUNK_SIZE=DICE_NUM_MAX_THREADS_PER_CORE — each TID
//       appears exactly once in the active-mask chunk and is checked exactly
//       once per CTA dispatch.
//
// To force a true stall the TB would need one of:
//   • A load-response-driven wb_valid path that can be held low independently
//     of cgra_v_lo (so the scoreboard entry stays reserved while a thread is
//     re-encountered), or
//   • An architecture that re-injects a thread into the thread FIFO within
//     the same CTA before its pending scoreboard bits are cleared.
//
// Test 6 does exercise the one-cycle rd_tid_conflict path (collision when
// cgra_wb and scoreboard read for the same TID happen in the same cycle) by
// running with a non-default ld_dest_regs value, verifying the system
// completes cleanly.
// =============================================================================

module tb_dice_backend_dispatch;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import cgra_test_pkg::*;

  // ─── Timing & size constants ───────────────────────────────────────────────
  localparam time CLK_PERIOD        = 20000;
  localparam int  RESET_CYCLES      = 10;
  localparam int  POST_RESET_CYCLES = 10;
  localparam int  TIMEOUT_CYCLES    = 80000;
  localparam int  CHUNK_COUNT       = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                      / DICE_MEM_DATA_WIDTH;
  localparam int  WORDS_PER_CHUNK   = DICE_MEM_DATA_WIDTH / 32;
  localparam int  RF_WRITE_SETTLE   = 3;
  localparam int  CGRA_LATENCY      = 7;
  localparam int  WRITEBACK_SETTLE  = 3;
  localparam int  NUM_TEST_THREADS  = DICE_NUM_MAX_THREADS_PER_CORE;
  localparam int  NUM_SRC_BANKS     = 8;
  localparam int  NUM_DST_BANKS     = 4;
  localparam bit  ENABLE_WB_TRACE   = 1'b0;
  // Cycles to drain in-flight CGRA ops (e.g. read-verify dispatches) that
  // may still be in the pipeline when one test ends and the next starts.
  localparam int  INTER_TEST_SETTLE = 2 * CGRA_LATENCY + WRITEBACK_SETTLE;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/home/jami3jun/Desktop/minidice/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

  // ─── Signals ──────────────────────────────────────────────────────────────
  logic clk_i;
  logic reset_i;
  logic en_i;
  fdr_if fdr_if_i ();

  logic [DICE_MEM_DATA_WIDTH-1:0]  cm0_data_i;
  logic [CHUNK_COUNT-1:0]          cm0_chunk_en_i;
  logic [DICE_MEM_DATA_WIDTH-1:0]  cm1_data_i;
  logic [CHUNK_COUNT-1:0]          cm1_chunk_en_i;
  logic                            v_i;
  logic                            bank_i;
  logic                            ready_o;
  logic                            busy_o;
  logic [1:0]                      bank_valid_o;
  logic                            prog_dout_o;
  logic                            prog_we_o;
  logic [DICE_NUM_MAX_THREADS_PER_CORE*DICE_NUM_PRED-1:0] cgra_pred_all;
  // AXI-Lite master interface (DUT outputs / TB slave)
  logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr;
  logic                           axi_awvalid;
  logic                           axi_awready;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_wdata;
  logic [1:0]                     axi_wstrb;
  logic                           axi_wvalid;
  logic                           axi_wready;
  logic [1:0]                     axi_bresp;
  logic                           axi_bvalid;
  logic                           axi_bready;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_araddr;
  logic                           axi_arvalid;
  logic                           axi_arready;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_rdata;
  logic [1:0]                     axi_rresp;
  logic                           axi_rvalid;
  logic                           axi_rready;
  logic                                                                 eblock_commit_valid_o;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]                                      eblock_commit_id_o;
  logic                                                                 eblock_commit_ready_i;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0]                                   hw_cta_pending_o;

`ifdef DICE_RF_DEBUG
  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0]    dbg_rf_rd_data;
  logic [DICE_NUM_PRED-1:0]                                          dbg_pred;
  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0]    dbg_rf_launch_data;
  logic [DICE_NUM_PRED-1:0]                                          dbg_pred_launch;
  logic [((DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH)-1:0] dbg_cgra_data;
  logic [DICE_TOTAL_REGS-1:0]                                        dbg_cgra_wr_bitmap;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                  dbg_cgra_tid;
  logic                                                              dbg_cgra_valid;
  logic                                                              dbg_rf_rd_valid;
`endif

  integer cycle_count;
  int     tests_passed;
  int     tests_failed;

  // ─── Waveform dump ────────────────────────────────────────────────────────
  initial begin
    $fsdbDumpfile("waveform_dispatch.fsdb");
    $fsdbDumpvars(0, tb_dice_backend_dispatch, "+struct", "+mda");
  end

  // ─── DUT ──────────────────────────────────────────────────────────────────
  dice_backend dut (
      .clk_i                 (clk_i),
      .rst_i                 (reset_i),
      .fdr_valid_i           (fdr_if_i.valid),
      .fdr_data_i            (fdr_if_i.data),
      .fdr_ready_o           (fdr_if_i.ready),
      .eblock_commit_valid_o (eblock_commit_valid_o),
      .eblock_commit_id_o    (eblock_commit_id_o),
      .eblock_commit_ready_i (eblock_commit_ready_i),
      .hw_cta_pending_o      (hw_cta_pending_o),
      .cgra_cm0_data_i       (cm0_data_i),
      .cgra_cm0_chunk_en_i   (cm0_chunk_en_i),
      .cgra_cm1_data_i       (cm1_data_i),
      .cgra_cm1_chunk_en_i   (cm1_chunk_en_i),
      .en_i                  (en_i),
      .prog_v_i              (v_i),
      .cm_bank_i             (bank_i),
      .prog_ready_o          (ready_o),
      .prog_busy_o           (busy_o),
      .cm_bank_valid_o       (bank_valid_o),
      .cgra_prog_dout_o      (prog_dout_o),
      .cgra_prog_we_o        (prog_we_o),
      .cgra_pred_all_o       (cgra_pred_all),
      .axi_awaddr_o          (axi_awaddr),
      .axi_awvalid_o         (axi_awvalid),
      .axi_awready_i         (axi_awready),
      .axi_wdata_o           (axi_wdata),
      .axi_wstrb_o           (axi_wstrb),
      .axi_wvalid_o          (axi_wvalid),
      .axi_wready_i          (axi_wready),
      .axi_bresp_i           (axi_bresp),
      .axi_bvalid_i          (axi_bvalid),
      .axi_bready_o          (axi_bready),
      .axi_araddr_o          (axi_araddr),
      .axi_arvalid_o         (axi_arvalid),
      .axi_arready_i         (axi_arready),
      .axi_rdata_i           (axi_rdata),
      .axi_rresp_i           (axi_rresp),
      .axi_rvalid_i          (axi_rvalid),
      .axi_rready_o          (axi_rready)
`ifdef DICE_RF_DEBUG
      , .dbg_rf_rd_data_o    (dbg_rf_rd_data)
      , .dbg_pred_o          (dbg_pred)
      , .dbg_rf_launch_data_o(dbg_rf_launch_data)
      , .dbg_pred_launch_o   (dbg_pred_launch)
      , .dbg_cgra_data_o     (dbg_cgra_data)
      , .dbg_cgra_wr_bitmap_o(dbg_cgra_wr_bitmap)
      , .dbg_cgra_tid_o      (dbg_cgra_tid)
      , .dbg_cgra_valid_o    (dbg_cgra_valid)
      , .dbg_rf_rd_valid_o   (dbg_rf_rd_valid)
`endif
  );

  // ─── Clock ────────────────────────────────────────────────────────────────
  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
  end

  // ─── Cycle counter + global timeout ───────────────────────────────────────
  always_ff @(posedge clk_i) begin
    if (reset_i) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > TIMEOUT_CYCLES)
        $fatal(1, "TIMEOUT after %0d cycles", TIMEOUT_CYCLES);
    end
  end

`ifdef DICE_RF_DEBUG
  // ─── Optional writeback trace ─────────────────────────────────────────────
  always_ff @(posedge clk_i) begin
    if (!reset_i && ENABLE_WB_TRACE && dbg_cgra_valid)
      $display("[WB] cyc=%0d tid=%0d wr=%b d0=%0d d1=%0d d2=%0d d3=%0d",
               cycle_count, dbg_cgra_tid,
               dbg_cgra_wr_bitmap[NUM_DST_BANKS-1:0],
               dbg_cgra_data[0*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[1*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[2*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[3*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
  end
`endif

  // ===========================================================================
  // Infrastructure tasks
  // ===========================================================================

  task automatic clear_stream_inputs();
    begin
      cm0_data_i = '0; cm0_chunk_en_i = '0;
      cm1_data_i = '0; cm1_chunk_en_i = '0;
      v_i = 1'b0; bank_i = 1'b0;
    end
  endtask

  task automatic clear_rf_inputs();
    begin
      fdr_if_i.valid        = 1'b0;
      fdr_if_i.data         = '0;
      eblock_commit_ready_i = 1'b0;
      // AXI-Lite slave defaults: accept AW/W immediately; hold off AR/R
      // (the vector-mul bitstream does not issue external memory ops, so
      //  AR/R will never be exercised by these tests)
      axi_awready           = 1'b1;
      axi_wready            = 1'b1;
      axi_bresp             = '0;
      axi_bvalid            = 1'b0;
      axi_arready           = 1'b1;
      axi_rdata             = '0;
      axi_rresp             = '0;
      axi_rvalid            = 1'b0;
    end
  endtask

  task automatic get_bitstream_chunk(
      input  int unsigned                    chunk_idx,
      output logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data
  );
    int unsigned w[0:WORDS_PER_CHUNK-1];
    int word_idx;
    begin
      dice_vector_mul_bitstream_get_chunk(
          chunk_idx,
          w[0],  w[1],  w[2],  w[3],
          w[4],  w[5],  w[6],  w[7],
          w[8],  w[9],  w[10], w[11],
          w[12], w[13], w[14], w[15]);
      chunk_data = '0;
      for (word_idx = 0; word_idx < WORDS_PER_CHUNK; word_idx++)
        chunk_data[word_idx*32 +: 32] = w[word_idx];
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
          cm0_data_i = chunk_data; cm0_chunk_en_i = chunk_mask;
          cm1_data_i = '0;         cm1_chunk_en_i = '0;
        end else begin
          cm0_data_i = '0;         cm0_chunk_en_i = '0;
          cm1_data_i = chunk_data; cm1_chunk_en_i = chunk_mask;
        end
        @(posedge clk_i);
        @(negedge clk_i);
        clear_stream_inputs();
      end
      repeat (2) @(posedge clk_i);
      if (bank_valid_o[target_bank] !== 1'b1)
        $fatal(1, "Bank %0d did not become valid after chunk streaming", target_bank);
    end
  endtask

  task automatic program_bank(input logic target_bank);
    begin
      bank_i = target_bank;
      wait (ready_o === 1'b1);
      @(negedge clk_i);
      v_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      v_i = 1'b0;
      wait (busy_o === 1'b1);
      wait (busy_o === 1'b0);
      repeat (CGRA_LATENCY) @(posedge clk_i);
    end
  endtask

  task automatic send_mem_rsp_write(
      input logic [DICE_TID_WIDTH-1:0]      tid,
      input int                             reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0] data
  );
    // Inject directly into dice_backend's internal LDST response path, bypassing
    // the AXI-Lite / mem_req_fifo.  The old mem_rsp_*_i top-level ports have been
    // absorbed into the module; this force/release achieves the same RF write.
    begin
      @(negedge clk_i);
      force dut.mem_rsp_tid_lo   = tid;
      force dut.mem_rsp_addr_lo  = reg_idx[DICE_REG_ADDR_WIDTH-1:0];
      force dut.mem_rsp_data_lo  = data;
      force dut.mem_rsp_valid_lo = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      release dut.mem_rsp_valid_lo;
      release dut.mem_rsp_tid_lo;
      release dut.mem_rsp_addr_lo;
      release dut.mem_rsp_data_lo;
    end
  endtask

  // Standard dispatch — ld_dest_regs left as all-zeros (both entries → bank 0).
  task automatic issue_backend_dispatch(
      input logic [DICE_TOTAL_REGS-1:0]                     in_bitmap,
      input logic [DICE_TOTAL_REGS-1:0]                     out_bitmap,
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0]       active_mask
  );
    logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs;
    begin
      ld_dest_regs = '0;
      wait (fdr_if_i.ready === 1'b1);
      @(negedge clk_i);
      fdr_if_i.data                          = '0;
      fdr_if_i.data.real_active_mask         = active_mask;
      fdr_if_i.data.metadata.in_regs_bitmap  = in_bitmap;
      fdr_if_i.data.metadata.out_regs_bitmap = out_bitmap;
      fdr_if_i.data.metadata.ld_dest_regs   = ld_dest_regs;
      fdr_if_i.data.metadata.lat             = CGRA_LATENCY[7:0];
      fdr_if_i.valid                         = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      fdr_if_i.valid = 1'b0;
    end
  endtask

  // Dispatch with an explicit ld_dest_regs[0] value.  Exercises the scoreboard
  // ld_dest_regs_bitmap reservation and CGRA-wb release path with a non-default
  // register index so that both bit 0 *and* ld_dest_reg are reserved per-thread.
  task automatic issue_dispatch_with_ld_dest(
      input logic [DICE_TOTAL_REGS-1:0]                     in_bitmap,
      input logic [DICE_TOTAL_REGS-1:0]                     out_bitmap,
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0]       active_mask,
      input logic [REG_INDEX_WIDTH-1:0]                     ld_dest_reg
  );
    logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs;
    begin
      ld_dest_regs    = '0;
      ld_dest_regs[0] = ld_dest_reg;
      wait (fdr_if_i.ready === 1'b1);
      @(negedge clk_i);
      fdr_if_i.data                          = '0;
      fdr_if_i.data.real_active_mask         = active_mask;
      fdr_if_i.data.metadata.in_regs_bitmap  = in_bitmap;
      fdr_if_i.data.metadata.out_regs_bitmap = out_bitmap;
      fdr_if_i.data.metadata.ld_dest_regs   = ld_dest_regs;
      fdr_if_i.data.metadata.lat             = CGRA_LATENCY[7:0];
      fdr_if_i.valid                         = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      fdr_if_i.valid = 1'b0;
    end
  endtask

  // Read and compare the RF data captured at the RF→CGRA read stage.
  // Uses DICE_REG_DATA_WIDTH-wide comparison so chain-multiply results
  // (which can exceed 8 bits) are handled correctly.
  task automatic check_rf_read_data(
      input string                            test_name,
      input logic [DICE_TID_WIDTH-1:0]        expected_tid,
      input logic [DICE_REG_DATA_WIDTH-1:0]   expected[],
      input int                               count
  );
    logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] sampled;
    logic [DICE_TID_WIDTH-1:0] sampled_tid;
    begin
`ifdef DICE_RF_DEBUG
      @(posedge clk_i iff (dbg_rf_rd_valid === 1'b1));
      sampled     = dbg_rf_rd_data;
      sampled_tid = dut.u_dice_cgra_rf.rf_ctrl_inst.tid_o;
`else
      @(posedge clk_i iff (dut.u_dice_cgra_rf.rf_rd_valid_o === 1'b1));
      sampled     = dut.u_dice_cgra_rf.rf_rd_data_lo;
      sampled_tid = dut.u_dice_cgra_rf.rf_ctrl_inst.tid_o;
`endif
      if (sampled_tid !== expected_tid)
        $fatal(1, "%s: expected tid %0d got %0d", test_name, expected_tid, sampled_tid);
      for (int i = 0; i < count; i++) begin
        if (sampled[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] !== expected[i])
          $fatal(1, "%s: bank %0d expected %0d got %0d",
                 test_name, i, expected[i],
                 sampled[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
        $display("%s: bank %0d = %0d (OK)", test_name, i,
                 sampled[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
      end
    end
  endtask

  // Build per-thread test vectors.
  //   rf_values[i]          = tid + i + 1   (A operands, banks 0..NUM_DST_BANKS-1)
  //   rf_values[i+NUM_DST]  = i + 2         (B operands, banks NUM_DST..NUM_SRC-1)
  //   expected[i]           = rf_values[i] * rf_values[i+NUM_DST]
  task automatic build_thread_case(
      input  logic [DICE_TID_WIDTH-1:0]          tid,
      output logic [DICE_REG_DATA_WIDTH-1:0]     rf_values [0:NUM_SRC_BANKS-1],
      output logic [DICE_REG_DATA_WIDTH-1:0]     expected  [0:NUM_DST_BANKS-1]
  );
    begin
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        rf_values[i]             = DICE_REG_DATA_WIDTH'(tid + i + 1);
        rf_values[i + NUM_DST_BANKS] = DICE_REG_DATA_WIDTH'(i + 2);
        expected[i]              = rf_values[i] * rf_values[i + NUM_DST_BANKS];
      end
    end
  endtask

  task automatic preload_thread_registers(
      input logic [DICE_TID_WIDTH-1:0]          tid,
      input logic [DICE_REG_DATA_WIDTH-1:0]     rf_values [0:NUM_SRC_BANKS-1]
  );
    begin
      for (int bank = 0; bank < NUM_SRC_BANKS; bank++)
        send_mem_rsp_write(tid, bank, rf_values[bank]);
    end
  endtask

  // Issue a full source+dest-bank dispatch with the given active mask.
  task automatic issue_dispatch_all_banks(
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask
  );
    logic [DICE_TOTAL_REGS-1:0] src_bitmap, dst_bitmap;
    begin
      src_bitmap = '0; dst_bitmap = '0;
      for (int i = 0; i < NUM_SRC_BANKS; i++) src_bitmap[i] = 1'b1;
      for (int i = 0; i < NUM_DST_BANKS; i++) dst_bitmap[i] = 1'b1;
      issue_backend_dispatch(src_bitmap, dst_bitmap, active_mask);
    end
  endtask

  // Issue a read-only FDR for a single thread so the RF read data can be
  // captured for verification.  out_bitmap='0 means the CGRA result is not
  // written back, leaving the RF unchanged.
  task automatic issue_read_verify(input logic [DICE_TID_WIDTH-1:0] tid);
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] one_mask;
    begin
      dst_bitmap = '0; one_mask = '0;
      for (int i = 0; i < NUM_DST_BANKS; i++) dst_bitmap[i] = 1'b1;
      one_mask[tid] = 1'b1;
      issue_backend_dispatch(dst_bitmap, '0, one_mask);
    end
  endtask

  // Wait long enough for active_count dispatched threads + CGRA pipeline to drain.
  task automatic wait_dispatch_settle(input int active_count);
    begin
      repeat (active_count + CGRA_LATENCY + WRITEBACK_SETTLE) @(posedge clk_i);
    end
  endtask

  task automatic reset_dut();
    begin
      reset_i = 1'b1;
      en_i    = 1'b1;
      clear_stream_inputs();
      clear_rf_inputs();
      repeat (RESET_CYCLES) @(posedge clk_i);
      @(negedge clk_i);
      reset_i = 1'b0;
      repeat (POST_RESET_CYCLES) @(posedge clk_i);
    end
  endtask

  // ===========================================================================
  // Test 1: All-threads baseline
  // ===========================================================================
  // All 16 threads active.  Equivalent to tb_dice_backend_vector_mul but with
  // 16-bit expected values and explicit pass/fail accounting.
  task automatic test_all_threads();
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in  [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] all_mask;
    begin
      $display("\n=== TEST 1: All-thread baseline ===");
      all_mask = '1;
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        build_thread_case(t[DICE_TID_WIDTH-1:0], rf_in[t], rf_exp[t]);
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_all_banks(all_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test1 tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp[t], NUM_DST_BANKS);
      end
      $display("[PASS] TEST 1: All-thread baseline");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 2: Partial mask — even TIDs only
  // ===========================================================================
  // Only even-numbered threads are set in active_mask.  Exercises the
  // dispatcher's ability to skip inactive TIDs entirely: those threads must
  // never reach the scoreboard reserve stage or the CGRA.  After the dispatch,
  // odd-TID RF banks 0-3 must still hold their preloaded input values (not mul
  // outputs), confirming the CGRA wrote nothing for them.
  task automatic test_partial_mask_even();
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in  [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] even_mask;
    begin
      $display("\n=== TEST 2: Partial mask — even TIDs only ===");
      even_mask = '0;
      for (int t = 0; t < NUM_TEST_THREADS; t += 2)
        even_mask[t] = 1'b1;

      for (int t = 0; t < NUM_TEST_THREADS; t++)
        build_thread_case(t[DICE_TID_WIDTH-1:0], rf_in[t], rf_exp[t]);
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_all_banks(even_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);

      // Active (even) threads: expect mul outputs in banks 0-3
      for (int t = 0; t < NUM_TEST_THREADS; t += 2) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test2 active tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp[t], NUM_DST_BANKS);
      end

      // Inactive (odd) threads: banks 0-3 must still hold the preloaded A-operands
      // rf_in[t] has NUM_SRC_BANKS entries; check_rf_read_data only inspects
      // the first NUM_DST_BANKS entries (the A-operand banks).
      for (int t = 1; t < NUM_TEST_THREADS; t += 2) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test2 inactive tid%0d (must be unchanged)", t),
                           t[DICE_TID_WIDTH-1:0], rf_in[t], NUM_DST_BANKS);
      end
      $display("[PASS] TEST 2: Partial mask even TIDs");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 3: Single-thread dispatch
  // ===========================================================================
  // Only the mid-range TID (NUM_TEST_THREADS/2) is active.  Tests the minimal
  // dispatch path: one TID through scoreboard → ready FIFO → RF read → CGRA
  // → writeback.  Confirms the dispatcher reaches DONE with no hang.
  task automatic test_single_thread();
    localparam int TARGET_TID = NUM_TEST_THREADS / 2;
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in  [0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp [0:NUM_DST_BANKS-1];
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] one_mask;
    begin
      $display("\n=== TEST 3: Single-thread dispatch (TID %0d) ===", TARGET_TID);
      one_mask = '0;
      one_mask[TARGET_TID] = 1'b1;
      build_thread_case(TARGET_TID[DICE_TID_WIDTH-1:0], rf_in, rf_exp);
      preload_thread_registers(TARGET_TID[DICE_TID_WIDTH-1:0], rf_in);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_all_banks(one_mask);
      wait_dispatch_settle(1);
      issue_read_verify(TARGET_TID[DICE_TID_WIDTH-1:0]);
      check_rf_read_data($sformatf("test3 tid%0d", TARGET_TID),
                         TARGET_TID[DICE_TID_WIDTH-1:0], rf_exp, NUM_DST_BANKS);
      $display("[PASS] TEST 3: Single-thread dispatch");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 4: Back-to-back CTAs without reset
  // ===========================================================================
  // Two sequential CTAs using the same set of TIDs but different register
  // values.  Verifies the DONE→DISPATCHING transition:
  //   • start_new_cta clears all scoreboard entries before CTA B's first
  //     thread is checked — no stale reservations from CTA A carry over.
  //   • The dispatcher re-arms and correctly latches CTA B's active_mask
  //     and in_regs_bitmap.
  //
  // CTA A uses the standard build_thread_case values.
  // CTA B seeds build_thread_case with (t + NUM_TEST_THREADS/2) so results
  // are numerically distinct, making any CTA A data leaking into CTA B visible.
  task automatic test_back_to_back_cta();
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in_a  [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp_a [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in_b  [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp_b [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] all_mask;
    begin
      $display("\n=== TEST 4: Back-to-back CTAs ===");
      all_mask = '1;

      // --- CTA A ---
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        build_thread_case(t[DICE_TID_WIDTH-1:0], rf_in_a[t], rf_exp_a[t]);
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in_a[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_all_banks(all_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test4 CTA-A tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp_a[t], NUM_DST_BANKS);
      end
      $display("[TEST 4] CTA A verified");
      // Drain any in-flight CGRA ops from the CTA A verification reads.
      repeat (CGRA_LATENCY + WRITEBACK_SETTLE) @(posedge clk_i);

      // --- CTA B: shifted tid seed → numerically distinct expected values ---
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        automatic int tid_b = t + NUM_TEST_THREADS/2;
        build_thread_case(tid_b[DICE_TID_WIDTH-1:0],
                          rf_in_b[t], rf_exp_b[t]);
      end
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in_b[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_all_banks(all_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test4 CTA-B tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp_b[t], NUM_DST_BANKS);
      end
      $display("[PASS] TEST 4: Back-to-back CTAs");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 5: RAW chain — CTA 2 reads CTA 1 outputs from the RF
  // ===========================================================================
  // CTA 1 computes vec_mul and writes results to RF banks 0-3.
  // CTA 2 dispatches with the same in/out bitmaps *without re-preloading*:
  //   A operands (banks 0-3) = CTA 1 CGRA outputs  (the RAW dependency)
  //   B operands (banks 4-7) = original preload values (unchanged by CTA 1)
  //
  //   chain_expected[i] = cta1_expected[i] * (i+2)
  //                     = (tid+i+1) * (i+2) * (i+2)
  //
  // This verifies that the RF correctly retains CGRA writebacks across
  // sequential FDR dispatches and that CTA 2's RF reads see CTA 1's outputs.
  // The inter-CTA verification pass ensures all CTA 1 CGRA writebacks have
  // landed in the RF before CTA 2 is dispatched.
  task automatic test_raw_chain();
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in     [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp    [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] chain_exp [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] all_mask;
    begin
      $display("\n=== TEST 5: RAW chain (CTA 2 reads CTA 1 outputs) ===");
      all_mask = '1;

      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        build_thread_case(t[DICE_TID_WIDTH-1:0], rf_in[t], rf_exp[t]);
        // B operand for bank i is (i+2); unchanged in banks 4-7 after CTA 1.
        for (int i = 0; i < NUM_DST_BANKS; i++)
          chain_exp[t][i] = rf_exp[t][i] * DICE_REG_DATA_WIDTH'(i + 2);
      end

      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);

      // CTA 1
      issue_dispatch_all_banks(all_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);
      // Verify CTA 1 and bring the dispatcher to DONE so CTA 1 RF writes are
      // stable before CTA 2 dispatches.
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test5 CTA1 tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp[t], NUM_DST_BANKS);
      end
      // Drain remaining in-flight CGRA ops from CTA 1 verification reads.
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      // CTA 2 — no re-preload; banks 0-3 hold CTA 1 outputs, banks 4-7 unchanged.
      issue_dispatch_all_banks(all_mask);
      wait_dispatch_settle(NUM_TEST_THREADS);
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test5 CTA2-chain tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], chain_exp[t], NUM_DST_BANKS);
      end
      $display("[PASS] TEST 5: RAW chain");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 6: Scoreboard ld_dest_regs reservation + CGRA-wb release
  // ===========================================================================
  // Sets ld_dest_regs[0] to a non-default register (bank 2) so that the
  // dispatcher builds ld_dest_regs_bitmap with bits 0 AND 2 set.  When each
  // thread is dispatched, the scoreboard reserves those bits for that thread.
  // When the CGRA completes the thread (cgra_v_lo → wb_valid), both bits are
  // cleared from that thread's entry.
  //
  // No multi-cycle stall can occur here (see module header for why), but the
  // test confirms:
  //   (a) No deadlock — the scoreboard's reserve+release cycle fully drains
  //       every thread's dispatch FIFO entry.
  //   (b) Correct results — the extra ld_dest_regs_bitmap bit does not corrupt
  //       output register values.
  //   (c) The one-cycle rd_tid_conflict path (wb_valid fires in the same cycle
  //       as a scoreboard read for the same TID) is plausible when CGRA
  //       completions of early threads overlap with dispatcher checks of later
  //       threads; this test provides timing conditions for that to occur.
  task automatic test_ld_dest_regs_path();
    localparam logic [REG_INDEX_WIDTH-1:0] LD_DEST_REG = REG_INDEX_WIDTH'(2);
    logic [DICE_REG_DATA_WIDTH-1:0] rf_in  [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [DICE_REG_DATA_WIDTH-1:0] rf_exp [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];
    logic [DICE_TOTAL_REGS-1:0] src_bitmap, dst_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] all_mask;
    begin
      $display("\n=== TEST 6: ld_dest_regs[0] = bank %0d (scoreboard reserve+release) ===",
               LD_DEST_REG);
      all_mask   = '1;
      src_bitmap = '0;
      dst_bitmap = '0;
      for (int i = 0; i < NUM_SRC_BANKS; i++) src_bitmap[i] = 1'b1;
      for (int i = 0; i < NUM_DST_BANKS; i++) dst_bitmap[i] = 1'b1;
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        build_thread_case(t[DICE_TID_WIDTH-1:0], rf_in[t], rf_exp[t]);
      for (int t = 0; t < NUM_TEST_THREADS; t++)
        preload_thread_registers(t[DICE_TID_WIDTH-1:0], rf_in[t]);
      repeat (RF_WRITE_SETTLE) @(posedge clk_i);
      issue_dispatch_with_ld_dest(src_bitmap, dst_bitmap, all_mask, LD_DEST_REG);
      wait_dispatch_settle(NUM_TEST_THREADS);
      for (int t = 0; t < NUM_TEST_THREADS; t++) begin
        issue_read_verify(t[DICE_TID_WIDTH-1:0]);
        check_rf_read_data($sformatf("test6 tid%0d", t),
                           t[DICE_TID_WIDTH-1:0], rf_exp[t], NUM_DST_BANKS);
      end
      $display("[PASS] TEST 6: ld_dest_regs path");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Main test sequence
  // ===========================================================================
  // All tests share a single bitstream load and DUT reset.  Between tests the
  // CGRA bitstream persists, the dispatcher naturally reaches DONE/IDLE, and
  // each test re-preloads the RF from scratch, so no additional resets are
  // needed.  INTER_TEST_SETTLE cycles are inserted between tests to drain any
  // still-running CGRA ops from the previous test's verification reads.
  initial begin
    string bitstream_file;
    begin
      tests_passed = 0;
      tests_failed = 0;

      bitstream_file = DEFAULT_BITSTREAM_FILE;
      void'($value$plusargs("bitstream_bin=%s", bitstream_file));

      $display("[TB] dice_backend dispatch testbench");
      $display("[TB] DICE_NUM_MAX_THREADS_PER_CORE = %0d", DICE_NUM_MAX_THREADS_PER_CORE);
      $display("[TB] CGRA_LATENCY                  = %0d", CGRA_LATENCY);
      $display("[TB] NUM_SRC_BANKS                 = %0d", NUM_SRC_BANKS);
      $display("[TB] NUM_DST_BANKS                 = %0d", NUM_DST_BANKS);

      reset_dut();
      dice_vector_mul_bitstream_init(bitstream_file);
      stream_bitstream_to_bank(1'b0);
      stream_bitstream_to_bank(1'b1);
      program_bank(1'b0);

      test_all_threads();
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      test_partial_mask_even();
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      test_single_thread();
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      test_back_to_back_cta();
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      test_raw_chain();
      repeat (INTER_TEST_SETTLE) @(posedge clk_i);

      test_ld_dest_regs_path();

      $display("\n========================================");
      $display("Backend Dispatch Tests Complete");
      $display("%0d/%0d tests PASSED, %0d FAILED",
               tests_passed, tests_passed + tests_failed, tests_failed);
      $display("========================================");
      if (tests_failed > 0)
        $fatal(1, "%0d test(s) FAILED", tests_failed);
      $finish;
    end
  end

endmodule
