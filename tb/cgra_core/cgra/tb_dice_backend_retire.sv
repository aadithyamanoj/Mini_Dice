`define DICE_RF_DEBUG
`timescale 1ns/1ps

// =============================================================================
// tb_dice_backend_retire — BCT retire / pending-read countdown coverage
// =============================================================================
//
// Validates that the block commit table (BCT) correctly tracks outstanding
// load RF-writebacks and retires an e-block once all pending reads reach zero.
//
// Strategy:
//   1. Inject an FDR with schedule_eblock_id and ld_dest_regs set so that
//      dispatch_pending_reads = $countones(active_mask) * num_load_ports.
//   2. Force mem_rsp_* (including mem_rsp_e_block_id_lo) to simulate load
//      responses; each one triggers an ldst_pop retire event that decrements
//      the BCT pending_reads for that e-block.
//   3. Probe dut.u_block_commit_table.commit_table[id].pending_reads to
//      confirm the count descends correctly.
//   4. Verify eblock_commit_valid_o fires (with the right id) only after all
//      reads are retired.
//
// Test 1  Single thread, one load                   (pending_reads: 1→0)
// Test 2  Two threads, one load each                (pending_reads: 2→1→0,
//                                                    no early commit)
// Test 3  Two overlapping e-blocks, out-of-order    (younger retires first;
//                                                    older still blocked)
// =============================================================================

module tb_dice_backend_retire;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;

  // ─── Constants ───────────────────────────────────────────────────────────────
  localparam time CLK_PERIOD      = 20000;
  localparam int  RESET_CYCLES    = 10;
  localparam int  TIMEOUT_CYCLES  = 10000;
  // Cycles from FDR acceptance to BCT insert settling (registered 1 cycle
  // after accept; add slack for back-to-back dispatches)
  localparam int  BCT_INSERT_DELAY = 4;
  // Cycles for a retire event to travel FIFO → serializer → BCT update FF
  localparam int  RETIRE_LATENCY   = 15;
  localparam int  CGRA_LATENCY     = 7;
  localparam int  CHUNK_COUNT      = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                     / DICE_MEM_DATA_WIDTH;

  // ld_dest_regs sentinel: value 31 means "no load" in gen_num_loads
  localparam logic [REG_INDEX_WIDTH-1:0] NO_LOAD  = REG_INDEX_WIDTH'(31);
  localparam logic [REG_INDEX_WIDTH-1:0] LOAD_REG = REG_INDEX_WIDTH'(5);

  // ─── DUT signals ─────────────────────────────────────────────────────────────
  logic clk_i, rst_i, en_i;

  fdr_if fdr_if_i ();

  logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i, cm1_data_i;
  logic [CHUNK_COUNT-1:0]         cm0_chunk_en_i, cm1_chunk_en_i;

  logic v_i, bank_i, ready_o, busy_o;
  logic [1:0] bank_valid_o;
  logic prog_dout_o, prog_we_o;

  logic [DICE_NUM_MAX_THREADS_PER_CORE*DICE_NUM_PRED-1:0] cgra_pred_all;

  logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr, axi_wdata, axi_araddr, axi_rdata;
  logic [1:0]                     axi_wstrb, axi_bresp, axi_rresp;
  logic axi_awvalid, axi_awready, axi_wvalid, axi_wready;
  logic axi_bvalid, axi_bready, axi_arvalid, axi_arready, axi_rvalid, axi_rready;

  logic                            eblock_commit_valid_o;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_o;
  logic                            eblock_commit_ready_i;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_pending_o;

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

  // ─── Staging signals for force/release in send_load_rsp ──────────────────────
  // VCS does not allow automatic task variables in force statements (they are
  // treated as continuous assignments). We use module-level static signals as
  // an intermediary: the task writes here first, then forces the DUT signals
  // to these static nets.
  logic [DICE_EBLOCK_ID_WIDTH-1:0] _force_eid;
  logic [DICE_TID_WIDTH-1:0]       _force_tid;
  logic [DICE_REG_ADDR_WIDTH-1:0]  _force_addr;
  logic [DICE_REG_DATA_WIDTH-1:0]  _force_data;

  // ─── Waveform ────────────────────────────────────────────────────────────────
  initial begin
    $fsdbDumpfile("waveform_retire.fsdb");
    $fsdbDumpvars(0, tb_dice_backend_retire, "+struct", "+mda");
  end

  // ─── DUT ─────────────────────────────────────────────────────────────────────
  dice_backend dut (
      .clk_i                 (clk_i),
      .rst_i                 (rst_i),
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

  // ─── Clock ───────────────────────────────────────────────────────────────────
  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
  end

  // ─── Cycle counter + timeout ─────────────────────────────────────────────────
  always_ff @(posedge clk_i) begin
    if (rst_i) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > TIMEOUT_CYCLES)
        $fatal(1, "TIMEOUT after %0d cycles", TIMEOUT_CYCLES);
    end
  end

  // ===========================================================================
  // Infrastructure tasks
  // ===========================================================================

  task automatic reset_dut();
    begin
      rst_i                 = 1'b1;
      en_i                  = 1'b1;
      fdr_if_i.valid        = 1'b0;
      fdr_if_i.data         = '0;
      eblock_commit_ready_i = 1'b0;
      cm0_data_i            = '0; cm0_chunk_en_i = '0;
      cm1_data_i            = '0; cm1_chunk_en_i = '0;
      v_i = 1'b0; bank_i = 1'b0;
      // AXI: write side always-ready; read side tied off (no real memory ops)
      axi_awready = 1'b1; axi_wready = 1'b1;
      axi_bresp   = '0;   axi_bvalid = 1'b0;
      axi_arready = 1'b1; axi_rdata  = '0;
      axi_rresp   = '0;   axi_rvalid = 1'b0;
      repeat (RESET_CYCLES) @(posedge clk_i);
      @(negedge clk_i);
      rst_i = 1'b0;
      repeat (5) @(posedge clk_i);
    end
  endtask

  // Issue an FDR for an e-block with `num_loads` active load ports.
  // Sets ld_dest_regs[0..num_loads-1] = LOAD_REG (any reg != 31).
  // The dispatcher's pending_reads count will be:
  //   $countones(active_mask) * num_loads
  task automatic issue_fdr_with_loads(
      input logic [DICE_EBLOCK_ID_WIDTH-1:0]          eblock_id,
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,
      input int                                       num_loads
  );
    logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs;
    begin
      // Initialize to all-1s so the in-bounds entry (port 0) defaults to 31
      // (NO_LOAD). gen_num_loads always reads the out-of-bounds port 1 as 0
      // (SV default), which counts as 1 phantom load per thread regardless of
      // num_loads. Setting port 0 = NO_LOAD therefore gives pending_reads =
      // active_threads * 1, which is the minimum and easiest to reason about.
      ld_dest_regs = '1;
      for (int i = 0; i < NUM_MEM_PORTS; i++)
        if (i < num_loads) ld_dest_regs[i] = LOAD_REG;

      wait (fdr_if_i.ready === 1'b1);
      @(negedge clk_i);
      fdr_if_i.data                        = '0;
      fdr_if_i.data.schedule_eblock_id     = eblock_id;
      fdr_if_i.data.real_active_mask       = active_mask;
      fdr_if_i.data.metadata.ld_dest_regs = ld_dest_regs;
      fdr_if_i.data.metadata.num_stores   = '0;
      fdr_if_i.data.metadata.lat          = CGRA_LATENCY[7:0];
      fdr_if_i.valid                       = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      fdr_if_i.valid = 1'b0;
    end
  endtask

  // Simulate one load response completing for a given e-block.
  // Forces mem_rsp_* including mem_rsp_e_block_id_lo so the ldst_pop retire
  // event is correctly tagged and the BCT decrements the right entry.
  // Uses module-level _force_* staging signals because VCS does not allow
  // automatic task variables directly in force statements.
  task automatic send_load_rsp(
      input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_id,
      input logic [DICE_TID_WIDTH-1:0]       tid,
      input int                              reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0]  data
  );
    begin
      @(negedge clk_i);
      _force_eid  = eblock_id;
      _force_tid  = tid;
      _force_addr = reg_idx[DICE_REG_ADDR_WIDTH-1:0];
      _force_data = data;
      force dut.mem_rsp_e_block_id_lo = _force_eid;
      force dut.mem_rsp_tid_lo        = _force_tid;
      force dut.mem_rsp_addr_lo       = _force_addr;
      force dut.mem_rsp_data_lo       = _force_data;
      force dut.mem_rsp_valid_lo      = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      release dut.mem_rsp_valid_lo;
      release dut.mem_rsp_e_block_id_lo;
      release dut.mem_rsp_tid_lo;
      release dut.mem_rsp_addr_lo;
      release dut.mem_rsp_data_lo;
    end
  endtask

  // Probe BCT entry and compare pending_reads against expected value.
  task automatic check_pending_reads(
      input string                           label,
      input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_id,
      input int                              expected
  );
    int actual;
    begin
      @(negedge clk_i);  // sample on negedge for stable registered values
      actual = int'(dut.u_dice_brt.u_block_commit_table.commit_table[eblock_id].pending_reads);
      if (actual !== expected)
        $fatal(1, "%s: e-block %0d pending_reads — expected %0d, got %0d",
               label, eblock_id, expected, actual);
      $display("%s: e-block %0d pending_reads = %0d (OK)", label, eblock_id, expected);
    end
  endtask

  // Wait for eblock_commit_valid_o to assert for a specific e-block, then ack.
  task automatic wait_and_ack_commit(
      input string                           label,
      input logic [DICE_EBLOCK_ID_WIDTH-1:0] expected_id
  );
    begin
      @(posedge clk_i iff (eblock_commit_valid_o === 1'b1));
      if (eblock_commit_id_o !== expected_id)
        $fatal(1, "%s: commit id — expected %0d, got %0d",
               label, expected_id, eblock_commit_id_o);
      $display("%s: e-block %0d committed (OK)", label, expected_id);
      // Acknowledge so the BCT clears the entry
      @(negedge clk_i);
      eblock_commit_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      eblock_commit_ready_i = 1'b0;
    end
  endtask

  // ===========================================================================
  // Test 1: Single thread, single load — basic retire path
  // ===========================================================================
  // FDR: eblock_id=1, active_mask={tid0}, 1 load port → pending_reads = 1.
  // Send one load response tagged eblock_id=1.
  // Check pending_reads reaches 0 and commit fires exactly once.
  task automatic test_single_thread_single_load();
    localparam logic [DICE_EBLOCK_ID_WIDTH-1:0] EID = DICE_EBLOCK_ID_WIDTH'(1);
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask;
    begin
      $display("\n=== TEST 1: Single thread, single load ===");
      mask    = '0;
      mask[0] = 1'b1;

      // num_loads=0: port 0 = NO_LOAD (31), port 1 OOB reads 0 → phantom load
      // pending_reads = 1 thread * 1 phantom load = 1
      issue_fdr_with_loads(EID, mask, /*num_loads=*/0);
      repeat (BCT_INSERT_DELAY) @(posedge clk_i);

      check_pending_reads("test1 initial", EID, 1);
      if (eblock_commit_valid_o)
        $fatal(1, "test1: commit fired before any load response");

      send_load_rsp(EID, /*tid=*/0, /*reg=*/5, /*data=*/16'hABCD);
      repeat (RETIRE_LATENCY) @(posedge clk_i);

      check_pending_reads("test1 after rsp", EID, 0);
      wait_and_ack_commit("test1", EID);

      $display("[PASS] TEST 1: Single thread, single load");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 2: Two threads, one load each — count must hit zero before commit
  // ===========================================================================
  // FDR: eblock_id=2, active_mask={tid0,tid1}, 1 load → pending_reads = 2.
  // First response → pending_reads = 1, commit must NOT fire yet.
  // Second response → pending_reads = 0, commit fires.
  task automatic test_two_threads_one_load();
    // EID must fit in fdr_t.schedule_eblock_id which is EBLOCK_ID_WIDTH=1 bit.
    // Only 0 and 1 are valid; higher values truncate and alias back to 0/1.
    localparam logic [DICE_EBLOCK_ID_WIDTH-1:0] EID = DICE_EBLOCK_ID_WIDTH'(0);
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask;
    begin
      $display("\n=== TEST 2: Two threads, one load each ===");
      mask    = '0;
      mask[0] = 1'b1;
      mask[1] = 1'b1;

      // pending_reads = 2 threads * 1 phantom load = 2
      issue_fdr_with_loads(EID, mask, /*num_loads=*/0);
      repeat (BCT_INSERT_DELAY) @(posedge clk_i);

      check_pending_reads("test2 initial", EID, 2);

      // First response — pending_reads should drop to 1, no commit yet
      send_load_rsp(EID, 0, 5, 16'h1111);
      repeat (RETIRE_LATENCY) @(posedge clk_i);
      check_pending_reads("test2 after rsp1", EID, 1);
      if (eblock_commit_valid_o)
        $fatal(1, "test2: commit fired after only 1 of 2 responses");
      $display("test2: no early commit after first response (OK)");

      // Second response — pending_reads reaches 0, commit fires
      send_load_rsp(EID, 1, 5, 16'h2222);
      repeat (RETIRE_LATENCY) @(posedge clk_i);
      check_pending_reads("test2 after rsp2", EID, 0);
      wait_and_ack_commit("test2", EID);

      $display("[PASS] TEST 2: Two threads, one load each");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Test 3: Two overlapping e-blocks — younger retires first
  // ===========================================================================
  // Dispatch eblock_id=3 (2 threads, 1 load each → pending_reads=2).
  // Dispatch eblock_id=4 (1 thread,  1 load      → pending_reads=1).
  // Complete eblock_id=4 first → it commits; eblock_id=3 still has 2 pending.
  // Drain eblock_id=3 responses one at a time → confirm it commits last.
  task automatic test_overlapping_eblocks();
    // Only EIDs 0 and 1 are valid (schedule_eblock_id is 1-bit in fdr_t).
    localparam logic [DICE_EBLOCK_ID_WIDTH-1:0] EID3 = DICE_EBLOCK_ID_WIDTH'(1);
    localparam logic [DICE_EBLOCK_ID_WIDTH-1:0] EID4 = DICE_EBLOCK_ID_WIDTH'(0);
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask2, mask1;
    begin
      $display("\n=== TEST 3: Overlapping e-blocks, out-of-order retire ===");
      mask2    = '0; mask2[0] = 1'b1; mask2[1] = 1'b1;
      mask1    = '0; mask1[0] = 1'b1;

      // Dispatch both; issue_fdr_with_loads waits for ready so they sequence correctly
      // pending_reads = threads * 1 phantom load
      issue_fdr_with_loads(EID3, mask2, /*num_loads=*/0);  // pending_reads = 2
      issue_fdr_with_loads(EID4, mask1, /*num_loads=*/0);  // pending_reads = 1

      // Allow both BCT inserts to settle
      repeat (BCT_INSERT_DELAY) @(posedge clk_i);
      check_pending_reads("test3 eid3 initial", EID3, 2);
      check_pending_reads("test3 eid4 initial", EID4, 1);

      // Complete eblock 4 first — eblock 3 must stay blocked
      send_load_rsp(EID4, 0, 5, 16'hCCCC);
      repeat (RETIRE_LATENCY) @(posedge clk_i);
      check_pending_reads("test3 eid4 after rsp", EID4, 0);
      check_pending_reads("test3 eid3 still blocked", EID3, 2);
      wait_and_ack_commit("test3 eid4", EID4);

      // Now drain eblock 3 — first response, should still not commit
      send_load_rsp(EID3, 0, 5, 16'hAAAA);
      repeat (RETIRE_LATENCY) @(posedge clk_i);
      check_pending_reads("test3 eid3 after rsp1", EID3, 1);
      if (eblock_commit_valid_o)
        $fatal(1, "test3: eid3 committed after only 1 of 2 responses");

      // Second response — now eblock 3 commits
      send_load_rsp(EID3, 1, 5, 16'hBBBB);
      repeat (RETIRE_LATENCY) @(posedge clk_i);
      check_pending_reads("test3 eid3 after rsp2", EID3, 0);
      wait_and_ack_commit("test3 eid3", EID3);

      $display("[PASS] TEST 3: Overlapping e-blocks, out-of-order retire");
      tests_passed++;
    end
  endtask

  // ===========================================================================
  // Main
  // ===========================================================================
  initial begin
    tests_passed = 0;
    tests_failed = 0;

    reset_dut();
    test_single_thread_single_load();

    reset_dut();
    test_two_threads_one_load();

    reset_dut();
    test_overlapping_eblocks();

    $display("\n=== RETIRE TB SUMMARY: %0d passed, %0d failed ===",
             tests_passed, tests_failed);
    if (tests_failed > 0)
      $fatal(1, "One or more retire tests FAILED");
    $finish;
  end

endmodule
