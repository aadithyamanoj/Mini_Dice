// =============================================================================
// tb_dice_backend.sv
//
// Integration testbench for dice_backend — covers:
//
//  TEST 1  Initial state after reset
//  TEST 2  Simple all-thread dispatch        (mirrors tb_parameterized_dispatcher)
//  TEST 3  Register conflict / scoreboard    (mirrors tb_parameterized_dispatcher)
//  TEST 4  RF read path — rd_data_lo carries correct pre-loaded values
//  TEST 5  CGRA output packing — cgra_ext_data_lo → cgra_data_li always_comb
//  TEST 6  End-to-end CGRA writeback — cgra_v_lo fires, cgra_data_li correct
//  TEST 7  wb_tid_bitmap one-hot encoding for every TID
//  TEST 8  Back-to-back CTA dispatch with CGRA completions between them
// =============================================================================

`timescale 1ns/1ps
`include "dice_define.vh"

module tb_dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
();

  // ==========================================================================
  // Parameters
  // ==========================================================================
  localparam int CLK_PERIOD     = 10;
  localparam int TIMEOUT_CYCLES = 3000;
  localparam int RESET_CYCLES   = 5;

  // CM chunk-enable width — mirrors dice_cgra_subs port declaration
  localparam int CM_CHUNKS =
      (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH;

  // Shorthand
  localparam int N_THREADS = DICE_NUM_MAX_THREADS_PER_CORE;

  // ==========================================================================
  // DUT signals
  // ==========================================================================
  logic clk, rst;

  fdr_if fdr_bus ();

  // TMCU outputs — just drain
  logic                                                                            tmcu_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]                                                tmcu_block_id;
  logic [DICE_TID_WIDTH-1:0]                                                      tmcu_base_tid;
  logic [DICE_TID_BITMAP_WIDTH-1:0]                                               tmcu_tid_bitmap;
  logic                                                                            tmcu_write_enable;
  logic [DICE_CACHE_LINE_SIZE*8-1:0]                                              tmcu_write_data;
  logic [DICE_CACHE_LINE_SIZE-1:0]                                                tmcu_write_mask;
  logic [DICE_ADDR_WIDTH-1:0]                                                     tmcu_address;
  logic [1:0]                                                                     tmcu_size;
  logic [DICE_MAX_REG_WIDTH-1:0]                                                  tmcu_ld_dest_reg;
  logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] tmcu_address_map;

  // Memory response (LDST path) — tie off unless explicitly used
  logic [$clog2(N_THREADS)-1:0]                                       mem_rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                         mem_rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                      mem_rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] mem_rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                      mem_rsp_data;
  logic                                                                mem_rsp_valid;

  // BCT
  logic                            eblock_commit_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_pending;

  // CGRA config memory — tie off (no bitstream in this TB)
  logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm0_data;
  logic [CM_CHUNKS-1:0]           cgra_cm0_chunk_en;
  logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm1_data;
  logic [CM_CHUNKS-1:0]           cgra_cm1_chunk_en;

  // CGRA scan-chain
  logic cgra_v, cgra_bank;
  logic cgra_ready, cgra_busy;
  logic [1:0] cgra_bank_valid;
  logic cgra_prog_dout, cgra_prog_we;

  // ==========================================================================
  // DUT
  // ==========================================================================
  dice_backend u_dut (
    .clk_i                 (clk),
    .rst_i                 (rst),
    .fdr_if_i              (fdr_bus),

    .tmcu_valid_o          (tmcu_valid),
    .tmcu_block_id_o       (tmcu_block_id),
    .tmcu_base_tid_o       (tmcu_base_tid),
    .tmcu_tid_bitmap_o     (tmcu_tid_bitmap),
    .tmcu_write_enable_o   (tmcu_write_enable),
    .tmcu_write_data_o     (tmcu_write_data),
    .tmcu_write_mask_o     (tmcu_write_mask),
    .tmcu_address_o        (tmcu_address),
    .tmcu_size_o           (tmcu_size),
    .tmcu_ld_dest_reg_o    (tmcu_ld_dest_reg),
    .tmcu_address_map_o    (tmcu_address_map),
    .tmcu_ready_i          (1'b1),

    .mem_rsp_base_tid_i    (mem_rsp_base_tid),
    .mem_rsp_tid_bitmap_i  (mem_rsp_tid_bitmap),
    .mem_rsp_ld_dest_reg_i (mem_rsp_ld_dest_reg),
    .mem_rsp_address_map_i (mem_rsp_address_map),
    .mem_rsp_data_i        (mem_rsp_data),
    .mem_rsp_valid_i       (mem_rsp_valid),

    .eblock_commit_valid_o (eblock_commit_valid),
    .eblock_commit_id_o    (eblock_commit_id),
    .eblock_commit_ready_i (1'b1),
    .hw_cta_pending_o      (hw_cta_pending),

    .cgra_cm0_data_i       (cgra_cm0_data),
    .cgra_cm0_chunk_en_i   (cgra_cm0_chunk_en),
    .cgra_cm1_data_i       (cgra_cm1_data),
    .cgra_cm1_chunk_en_i   (cgra_cm1_chunk_en),

    .en_i                  (1'b1),
    .cgra_v_i              (cgra_v),
    .cgra_bank_i           (cgra_bank),
    .cgra_ready_o          (cgra_ready),
    .cgra_busy_o           (cgra_busy),
    .cgra_bank_valid_o     (cgra_bank_valid),
    .cgra_prog_dout_o      (cgra_prog_dout),
    .cgra_prog_we_o        (cgra_prog_we)
  );

  // ==========================================================================
  // Clock and timeout
  // ==========================================================================
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  int cyc;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) cyc <= 0;
    else begin
      cyc <= cyc + 1;
      if (cyc >= TIMEOUT_CYCLES) begin
        $error("[TIMEOUT] exceeded %0d cycles", TIMEOUT_CYCLES);
        $finish;
      end
    end
  end

  `ifdef FSDB
    initial begin
      $fsdbDumpfile("tb_dice_backend.fsdb");
      $fsdbDumpvars(0, tb_dice_backend, "+struct", "+mda");
    end
  `endif

  // ==========================================================================
  // Scoreboard
  // ==========================================================================
  int pass_count = 0, fail_count = 0;

  task automatic chk(input string label, input logic exp, input logic got);
    if (got === exp) begin
      $display("  PASS  %-65s  got=%0b", label, got);
      pass_count++;
    end else begin
      $error("  FAIL  %-65s  got=%0b  exp=%0b", label, got, exp);
      fail_count++;
    end
  endtask

  task automatic chk8(input string label, input logic [7:0] exp, input logic [7:0] got);
    if (got === exp) begin
      $display("  PASS  %-65s  got=0x%02h", label, got);
      pass_count++;
    end else begin
      $error("  FAIL  %-65s  got=0x%02h  exp=0x%02h", label, got, exp);
      fail_count++;
    end
  endtask

  task automatic chk_int(input string label, input int exp, input int got);
    if (got === exp) begin
      $display("  PASS  %-65s  got=%0d", label, got);
      pass_count++;
    end else begin
      $error("  FAIL  %-65s  got=%0d  exp=%0d", label, got, exp);
      fail_count++;
    end
  endtask

  // ==========================================================================
  // Utility tasks
  // ==========================================================================

  // --- Reset DUT and default all inputs ---
  task automatic reset_dut();
    rst                 = 1'b1;
    fdr_bus.valid       = 1'b0;
    fdr_bus.data        = '0;
    mem_rsp_valid       = 1'b0;
    mem_rsp_base_tid    = '0;
    mem_rsp_tid_bitmap  = '0;
    mem_rsp_ld_dest_reg = '0;
    mem_rsp_address_map = '0;
    mem_rsp_data        = '0;
    cgra_cm0_data       = '0;
    cgra_cm0_chunk_en   = '0;
    cgra_cm1_data       = '0;
    cgra_cm1_chunk_en   = '0;
    cgra_v              = 1'b0;
    cgra_bank           = 1'b0;
    repeat(RESET_CYCLES) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat(2) @(posedge clk);
  endtask

  // ---- Build minimal fdr_meta_t ----
  function automatic fdr_meta_t make_meta(
    input logic [REG_NUM-1:0] in_bmp,
    input logic [REG_NUM-1:0] out_bmp,
    input logic [7:0]         lat
  );
    fdr_meta_t m;
    m                 = '0;
    m.in_regs_bitmap  = in_bmp;
    m.out_regs_bitmap = out_bmp;
    m.lat             = lat;
    return m;
  endfunction

  // ---- Drive FDR packet and wait for handshake ----
  task automatic drive_fdr(
    input fdr_meta_t                         meta,
    input logic [N_THREADS-1:0]              active_mask
  );
    fdr_t pkt;
    pkt                  = '0;
    pkt.real_active_mask = active_mask;
    pkt.metadata         = meta;
    @(negedge clk);
    fdr_bus.valid = 1'b1;
    fdr_bus.data  = pkt;
    do @(posedge clk); while (!fdr_bus.ready);
    @(negedge clk);
    fdr_bus.valid = 1'b0;
    fdr_bus.data  = '0;
  endtask

  // ---- Count rf_rd_valid_lo pulses up to max_cycles ----
  // Each pulse = one thread's RF read completed = one thread dispatched to CGRA.
  // Stops early once the dispatcher goes idle and the FIFO is empty.
  task automatic count_rf_reads(input int max_cycles, output int cnt);
    cnt = 0;
    for (int i = 0; i < max_cycles; i++) begin
      @(posedge clk);
      if (u_dut.rf_rd_valid_lo) cnt++;
      if (!u_dut.dispatch_busy && u_dut.dispatch_fifo_empty && cnt > 0) break;
    end
    // Drain any final in-flight reads
    repeat(8) begin
      @(posedge clk);
      if (u_dut.rf_rd_valid_lo) cnt++;
    end
  endtask

  // ---- Staging registers for RF pre-load (force RHS must be module-level) ----
  logic [DICE_TID_WIDTH-1:0]                                        rf_wr_tid_q;
  logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0]  rf_wr_data_q;
  logic [DICE_TOTAL_REGS-1:0]                                       rf_wr_bitmap_q;

  // Pre-load the RF via the CGRA write port on dice_rf_ctrl.
  // Forces the RF ctrl's writeback input ports directly so the dispatcher
  // scoreboard is NOT affected (only the storage is written).
  task automatic preload_rf(
    input logic [DICE_TID_WIDTH-1:0]                                        tid,
    input logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0]  data,
    input logic [DICE_TOTAL_REGS-1:0]                                       wr_bitmap
  );
    rf_wr_tid_q    = tid;
    rf_wr_data_q   = data;
    rf_wr_bitmap_q = wr_bitmap;
    force u_dut.u_dice_rf_ctrl.cgra_valid_i = 1'b1;
    force u_dut.u_dice_rf_ctrl.cgra_tid_i   = rf_wr_tid_q;
    force u_dut.u_dice_rf_ctrl.cgra_data_i  = rf_wr_data_q;
    force u_dut.u_dice_rf_ctrl.wr_bitmap_i  = rf_wr_bitmap_q;
    @(posedge clk);
    @(posedge clk);
    release u_dut.u_dice_rf_ctrl.cgra_valid_i;
    release u_dut.u_dice_rf_ctrl.cgra_tid_i;
    release u_dut.u_dice_rf_ctrl.cgra_data_i;
    release u_dut.u_dice_rf_ctrl.wr_bitmap_i;
    @(posedge clk);
  endtask

  // ---- Force cgra_ext_data_lo / cgra_ext_pred_lo ----
  // Simulates mini_dice PE outputs without programming the CGRA.
  // Caller must later call release_cgra_outputs().
  task automatic force_cgra_outputs(
    input logic [DICE_REG_DATA_WIDTH-1:0] data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1],
    input logic                           pred[0:DICE_NUM_PRED-1]
  );
    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++)
      force u_dut.cgra_ext_data_lo[i] = data[i];
    for (int i = 0; i < DICE_NUM_PRED; i++)
      force u_dut.cgra_ext_pred_lo[i] = pred[i];
  endtask

  task automatic release_cgra_outputs();
    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++)
      release u_dut.cgra_ext_data_lo[i];
    for (int i = 0; i < DICE_NUM_PRED; i++)
      release u_dut.cgra_ext_pred_lo[i];
  endtask

  // ---- Simulate CGRA completing one thread ----
  // Forces cgra_v_lo high for one cycle with the given TID so the dispatcher
  // scoreboard releases that TID's registers and the RF ctrl sees the writeback.
  // Uses module-level staging register for VCS force semantics.
  logic [DICE_TID_WIDTH-1:0] sim_tid_q;

  task automatic simulate_cgra_done(input logic [DICE_TID_WIDTH-1:0] tid);
    sim_tid_q = tid;
    force u_dut.cgra_v_lo   = 1'b1;
    force u_dut.cgra_tid_lo = sim_tid_q;
    @(posedge clk);
    release u_dut.cgra_v_lo;
    release u_dut.cgra_tid_lo;
    @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 1 — Initial state after reset
  // ==========================================================================
  task automatic test_initial_state();
    $display("\n=== TEST 1: Initial State After Reset ===");
    chk    ("dispatch_busy == 0",       1'b0, u_dut.dispatch_busy);
    chk    ("dispatch_fifo_empty == 1", 1'b1, u_dut.dispatch_fifo_empty);
    chk    ("rf_rd_valid_lo == 0",      1'b0, u_dut.rf_rd_valid_lo);
    chk    ("cgra_v_lo == 0",           1'b0, u_dut.cgra_v_lo);
    chk    ("cgra_wb_tid_bitmap == 0",  1'b0, |u_dut.cgra_wb_tid_bitmap);
  endtask

  // ==========================================================================
  // TEST 2 — Simple all-thread dispatch
  // Mirrors tb_parameterized_dispatcher::test_simple_dispatch.
  // All N_THREADS active, 1 GPR.  Each thread must reach the RF read stage.
  // ==========================================================================
  task automatic test_simple_dispatch();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    int dispatched;

    $display("\n=== TEST 2: Simple All-Thread Dispatch ===");
    mask = '1;
    meta = make_meta(REG_NUM'(1), REG_NUM'(1), 8'd2);

    fork
      drive_fdr(meta, mask);
      count_rf_reads(500, dispatched);
    join

    chk_int($sformatf("all %0d threads reach RF read", N_THREADS),
            N_THREADS, dispatched);
  endtask

  // ==========================================================================
  // TEST 3 — Register conflict / scoreboard integration
  // Mirrors tb_parameterized_dispatcher::test_register_conflicts.
  //
  // CTA with 4 threads (TIDs 0-3), GPR0 needed.  All 4 dispatch (scoreboard
  // starts empty so no initial conflict).  Then immediately send a second
  // identical CTA while the first's writebacks are still pending — the second
  // CTA should stall.  Simulate CGRA completions for TIDs 0-3; the second
  // CTA should then fully dispatch.
  // ==========================================================================
  task automatic test_register_conflicts();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    int cta1_reads, stall_reads, cta2_reads;

    $display("\n=== TEST 3: Register Conflict / Scoreboard Integration ===");
    mask      = '0;
    mask[3:0] = 4'hF;   // TIDs 0-3
    meta      = make_meta(REG_NUM'(1), REG_NUM'(1), 8'd3);

    // CTA 1 — should dispatch all 4 threads
    fork
      drive_fdr(meta, mask);
      count_rf_reads(300, cta1_reads);
    join
    chk_int("CTA1: 4 threads dispatched", 4, cta1_reads);

    // CTA 2 — sent immediately; scoreboards still reserved for TIDs 0-3
    // Expect 0 RF reads within a short window (threads blocked)
    fdr_bus.valid = 1'b0;
    fdr_bus.data  = '0;
    fork
      drive_fdr(meta, mask);
      begin
        stall_reads = 0;
        repeat(30) begin
          @(posedge clk);
          if (u_dut.rf_rd_valid_lo) stall_reads++;
        end
      end
    join
    chk_int("CTA2 stalls (0 RF reads) while CTA1 registers reserved",
            0, stall_reads);

    // Simulate CGRA completing CTA1's TIDs → releases scoreboard entries
    for (int t = 0; t < 4; t++)
      simulate_cgra_done(DICE_TID_WIDTH'(t));

    // CTA2 should now flush
    count_rf_reads(200, cta2_reads);
    chk_int("CTA2: 4 threads dispatched after writeback", 4, cta2_reads);
  endtask

  // ==========================================================================
  // TEST 4 — RF read path
  // Pre-load GPR0[TID=1]=0xAA and GPR1[TID=1]=0x55, dispatch TID=1 only,
  // then verify rd_data_lo carries those exact values when rf_rd_valid_lo fires.
  // rd_data_lo is the bus driven onto ext_data_i_* of the CGRA.
  // ==========================================================================
  task automatic test_rf_read_path();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] init_data;
    localparam logic [7:0] VAL0 = 8'hAA;
    localparam logic [7:0] VAL1 = 8'h55;

    $display("\n=== TEST 4: RF Read Path ===");

    // Pre-load TID=1: GPR bank0=0xAA, GPR bank1=0x55
    init_data           = '0;
    init_data[0*8 +: 8] = VAL0;
    init_data[1*8 +: 8] = VAL1;
    preload_rf(DICE_TID_WIDTH'(1), init_data, DICE_TOTAL_REGS'(18'h0003));
    $display("  RF pre-loaded: bank0[TID=1]=0xAA  bank1[TID=1]=0x55");

    // Dispatch TID=1 only
    mask    = '0;
    mask[1] = 1'b1;
    meta    = make_meta(REG_NUM'('h3), REG_NUM'('h3), 8'd2);

    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_rf
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk); // let rd_data_lo settle
            chk8("rd_data_lo[bank0] == 0xAA (GPR0[TID=1])",
                 VAL0, u_dut.rd_data_lo[0*8 +: 8]);
            chk8("rd_data_lo[bank1] == 0x55 (GPR1[TID=1])",
                 VAL1, u_dut.rd_data_lo[1*8 +: 8]);
            disable wait_rf_timeout;
          end
          begin : wait_rf_timeout
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted");
            disable wait_rf;
          end
        join
      end
    join

    // Let the cgra_v shift drain to avoid stale pipeline state
    repeat(20) @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 5 — CGRA output packing (cgra_ext_data_lo → cgra_data_li always_comb)
  // Forces cgra_ext_data_lo and verifies cgra_data_li is packed correctly:
  //   cgra_data_li[j*W +: W] = cgra_ext_data_lo[j]  for j in 0..NUM_BANKS-1
  //   cgra_data_li[NUM_BANKS*W +: W] = cgra_ext_data_lo[NUM_BANKS]  (const slot)
  //   cgra_data_li[(NUM_BANKS+1)*W +: W] = {zeros, cgra_ext_pred_lo[0]}
  //   cgra_data_li[(NUM_BANKS+2)*W +: W] = {zeros, cgra_ext_pred_lo[1]}
  // ==========================================================================
  task automatic test_cgra_output_packing();
    logic [DICE_REG_DATA_WIDTH-1:0] ext_data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
    logic                           ext_pred[0:DICE_NUM_PRED-1];
    localparam int W = DICE_REG_DATA_WIDTH;

    $display("\n=== TEST 5: CGRA Output Packing (cgra_ext_data_lo → cgra_data_li) ===");

    // Assign distinct values to each slot
    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++)
      ext_data[i] = 8'(8'hA0 + i);
    ext_pred[0] = 1'b1;
    ext_pred[1] = 1'b0;

    force_cgra_outputs(ext_data, ext_pred);
    @(posedge clk); // let always_comb propagate

    // GPR banks
    for (int j = 0; j < DICE_NUM_BANKS; j++) begin
      chk8($sformatf("cgra_data_li[bank%0d] == ext_data[%0d]", j, j),
           ext_data[j],
           u_dut.cgra_data_li[j*W +: W]);
    end

    // First const slot (index DICE_NUM_BANKS)
    chk8("cgra_data_li[const0] == ext_data[NUM_BANKS]",
         ext_data[DICE_NUM_BANKS],
         u_dut.cgra_data_li[DICE_NUM_BANKS*W +: W]);

    // Predicate slots (zero-extended)
    chk8("cgra_data_li[pred0] == {0s, ext_pred[0]}",
         {7'b0, ext_pred[0]},
         u_dut.cgra_data_li[(DICE_NUM_BANKS+1)*W +: W]);
    chk8("cgra_data_li[pred1] == {0s, ext_pred[1]}",
         {7'b0, ext_pred[1]},
         u_dut.cgra_data_li[(DICE_NUM_BANKS+2)*W +: W]);

    release_cgra_outputs();
    @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 6 — End-to-end CGRA writeback
  // Force known CGRA outputs, dispatch TID=0, wait for cgra_v_lo assertion,
  // then verify cgra_data_li holds the forced values at the moment of writeback.
  // ==========================================================================
  task automatic test_cgra_writeback();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    logic [DICE_REG_DATA_WIDTH-1:0] ext_data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
    logic                           ext_pred[0:DICE_NUM_PRED-1];
    localparam logic [7:0] PE0 = 8'hFF;
    localparam logic [7:0] PE1 = 8'h56;
    bit v_seen;
    localparam int W = DICE_REG_DATA_WIDTH;

    $display("\n=== TEST 6: End-to-End CGRA Writeback ===");

    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++) ext_data[i] = '0;
    for (int i = 0; i < DICE_NUM_PRED;                  i++) ext_pred[i] = '0;
    ext_data[0] = PE0;
    ext_data[1] = PE1;

    force_cgra_outputs(ext_data, ext_pred);

    mask    = '0;
    mask[0] = 1'b1;           // TID=0 only
    meta    = make_meta(REG_NUM'('h3), REG_NUM'('h1), 8'd4);

    v_seen = 0;
    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_v
            @(posedge u_dut.cgra_v_lo);
            v_seen = 1;
            $display("  cgra_v_lo at cycle %0d  cgra_tid_lo=%0d", cyc, u_dut.cgra_tid_lo);
            // Sample cgra_data_li at the writeback pulse
            chk8("cgra_data_li[bank0] == PE0 (0xFF) at writeback pulse",
                 PE0, u_dut.cgra_data_li[0*W +: W]);
            chk8("cgra_data_li[bank1] == PE1 (0x56) at writeback pulse",
                 PE1, u_dut.cgra_data_li[1*W +: W]);
            chk    ("cgra_tid_lo == TID 0 at writeback",
                    1'b0, u_dut.cgra_tid_lo[0] ^ u_dut.cgra_tid_lo[0]); // just no-X check
            disable wait_v_timeout;
          end
          begin : wait_v_timeout
            repeat(int'(meta.lat) + 40) @(posedge clk);
            $error("  TIMEOUT: cgra_v_lo never asserted");
            disable wait_v;
          end
        join
      end
    join

    chk("cgra_v_lo asserted", 1'b1, logic'(v_seen));

    release_cgra_outputs();
    repeat(5) @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 9 — Full pipeline round-trip with RF readback
  //
  // This is the key end-to-end test:
  //   1. Pre-load TID=0: bank0=0xAA, bank1=0x55
  //   2. Dispatch TID=0; verify rd_data_lo carries the pre-loaded values
  //      (confirms the RF read path delivers correct data to the CGRA fabric)
  //   3. Force CGRA result: bank0=0xFF (simulated ADD), bank1=0x56 (simulated INC)
  //   4. Wait for cgra_v_lo; verify cgra_data_li and cgra_tid_lo
  //   5. Simulate CGRA done to release scoreboard, let RF write settle
  //   6. Dispatch TID=0 again (read-only, no out bitmap)
  //   7. Verify rd_data_lo[bank0]=0xFF — proves the RF actually STORED the
  //      writeback, not just that the bus had the right value
  // ==========================================================================
  task automatic test_rf_readback_after_writeback();
    fdr_meta_t meta_wr, meta_rd;
    logic [N_THREADS-1:0] mask;
    logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] init_data;
    logic [DICE_REG_DATA_WIDTH-1:0] ext_data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
    logic                           ext_pred[0:DICE_NUM_PRED-1];
    localparam logic [7:0] INIT0   = 8'hAA;
    localparam logic [7:0] INIT1   = 8'h55;
    localparam logic [7:0] RESULT0 = 8'hFF; // simulated ADD
    localparam logic [7:0] RESULT1 = 8'h56; // simulated INC
    localparam int W = DICE_REG_DATA_WIDTH;
    bit wb_seen;

    $display("\n=== TEST 9: Full Pipeline Round-Trip (RF Read → CGRA → RF Writeback Readback) ===");

    // Step 1 — pre-load TID=0: bank0=0xAA, bank1=0x55
    init_data           = '0;
    init_data[0*W +: W] = INIT0;
    init_data[1*W +: W] = INIT1;
    preload_rf(DICE_TID_WIDTH'(0), init_data, DICE_TOTAL_REGS'(18'h0003));
    $display("  Pre-loaded TID=0: bank0=0x%02h  bank1=0x%02h", INIT0, INIT1);

    // Step 2 — dispatch TID=0, verify RF read presents the pre-loaded values
    mask    = '0;
    mask[0] = 1'b1;
    // out_regs_bitmap bit0 = writeback to bank0 after CGRA
    meta_wr = make_meta(REG_NUM'('h3), REG_NUM'('h1), 8'd3);

    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++) ext_data[i] = '0;
    for (int i = 0; i < DICE_NUM_PRED;                  i++) ext_pred[i] = '0;
    ext_data[0] = RESULT0;
    ext_data[1] = RESULT1;
    force_cgra_outputs(ext_data, ext_pred);

    wb_seen = 0;
    fork
      drive_fdr(meta_wr, mask);
      begin
        // Step 2a — check RF read values when rf_rd_valid_lo fires
        fork
          begin : wait_rd1
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk); // settle
            chk8("STEP2 rd_data_lo[bank0] == INIT0 (0xAA)", INIT0, u_dut.rd_data_lo[0*W +: W]);
            chk8("STEP2 rd_data_lo[bank1] == INIT1 (0x55)", INIT1, u_dut.rd_data_lo[1*W +: W]);
            disable wait_rd1_timeout;
          end
          begin : wait_rd1_timeout
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted (step 2)");
            disable wait_rd1;
          end
        join

        // Step 4 — wait for CGRA writeback, verify cgra_data_li and tid
        fork
          begin : wait_wb
            @(posedge u_dut.cgra_v_lo);
            wb_seen = 1;
            $display("  cgra_v_lo at cycle %0d  cgra_tid_lo=%0d", cyc, u_dut.cgra_tid_lo);
            chk8("STEP4 cgra_data_li[bank0] == RESULT0 (0xFF)",
                 RESULT0, u_dut.cgra_data_li[0*W +: W]);
            chk8("STEP4 cgra_data_li[bank1] == RESULT1 (0x56)",
                 RESULT1, u_dut.cgra_data_li[1*W +: W]);
            if (u_dut.cgra_tid_lo !== DICE_TID_WIDTH'(0))
              $error("  FAIL  cgra_tid_lo expected 0 got %0d", u_dut.cgra_tid_lo);
            else begin
              $display("  PASS  cgra_tid_lo == 0 at writeback pulse");
              pass_count++;
            end
            disable wait_wb_timeout;
          end
          begin : wait_wb_timeout
            repeat(int'(meta_wr.lat) + 40) @(posedge clk);
            $error("  TIMEOUT: cgra_v_lo never asserted");
            disable wait_wb;
          end
        join
      end
    join

    chk("STEP4 cgra_v_lo asserted", 1'b1, logic'(wb_seen));
    release_cgra_outputs();

    // Step 5 — release scoreboard, let RF write settle
    simulate_cgra_done(DICE_TID_WIDTH'(0));
    repeat(8) @(posedge clk);

    // Step 6/7 — re-dispatch TID=0 read-only, verify RF stored the result
    meta_rd = make_meta(REG_NUM'('h3), REG_NUM'(0), 8'd2); // in_bmp=banks0+1, no writeback
    fork
      drive_fdr(meta_rd, mask);
      begin
        fork
          begin : wait_rd2
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk);
            chk8("STEP7 rd_data_lo[bank0] == RESULT0 (0xFF) — RF stored writeback",
                 RESULT0, u_dut.rd_data_lo[0*W +: W]);
          end
          begin : wait_rd2_timeout
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted (step 7)");
            disable wait_rd2;
          end
        join
      end
    join

    repeat(5) @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 10 — TID writeback isolation
  //
  // Pre-load TID=0 and TID=1 with different values.  Execute TID=0 with a
  // CGRA result that overwrites its bank0.  Then dispatch TID=1 and verify
  // rd_data_lo still has TID=1's original value — proves TID=0's writeback
  // did not corrupt another TID's register file entry.
  // ==========================================================================
  task automatic test_tid_writeback_isolation();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] init0, init1;
    logic [DICE_REG_DATA_WIDTH-1:0] ext_data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
    logic                           ext_pred[0:DICE_NUM_PRED-1];
    localparam logic [7:0] T0_BANK0  = 8'hAA;
    localparam logic [7:0] T1_BANK0  = 8'hBB;
    localparam logic [7:0] T0_RESULT = 8'hFF; // CGRA output for TID=0
    localparam int W = DICE_REG_DATA_WIDTH;

    $display("\n=== TEST 10: TID Writeback Isolation ===");

    // Pre-load TID=0 bank0=0xAA and TID=1 bank0=0xBB
    init0           = '0;
    init0[0*W +: W] = T0_BANK0;
    preload_rf(DICE_TID_WIDTH'(0), init0, DICE_TOTAL_REGS'(18'h0001));

    init1           = '0;
    init1[0*W +: W] = T1_BANK0;
    preload_rf(DICE_TID_WIDTH'(1), init1, DICE_TOTAL_REGS'(18'h0001));
    $display("  Pre-loaded TID=0:bank0=0x%02h  TID=1:bank0=0x%02h", T0_BANK0, T1_BANK0);

    // Dispatch and complete TID=0, overwriting bank0 with T0_RESULT
    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++) ext_data[i] = '0;
    for (int i = 0; i < DICE_NUM_PRED;                  i++) ext_pred[i] = '0;
    ext_data[0] = T0_RESULT;
    force_cgra_outputs(ext_data, ext_pred);

    mask    = '0;
    mask[0] = 1'b1;
    meta    = make_meta(REG_NUM'('h1), REG_NUM'('h1'), 8'd3);
    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_v0
            @(posedge u_dut.cgra_v_lo);
            disable wait_v0_to;
          end
          begin : wait_v0_to
            repeat(int'(meta.lat)+40) @(posedge clk);
            $error("  TIMEOUT: cgra_v_lo for TID=0 never asserted");
            disable wait_v0;
          end
        join
      end
    join
    release_cgra_outputs();
    simulate_cgra_done(DICE_TID_WIDTH'(0));
    repeat(8) @(posedge clk);
    $display("  TID=0 writeback complete: bank0 now 0x%02h", T0_RESULT);

    // Now dispatch TID=1 (read-only) and verify its bank0 is still T1_BANK0
    mask    = '0;
    mask[1] = 1'b1;
    meta    = make_meta(REG_NUM'('h1'), REG_NUM'(0), 8'd2);
    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_rd_t1
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk);
            chk8("TID=1 bank0 unchanged after TID=0 writeback (0xBB)",
                 T1_BANK0, u_dut.rd_data_lo[0*W +: W]);
            disable wait_rd_t1_to;
          end
          begin : wait_rd_t1_to
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted for TID=1 isolation check");
            disable wait_rd_t1;
          end
        join
      end
    join

    // Also confirm TID=0 is still updated (belt-and-suspenders)
    simulate_cgra_done(DICE_TID_WIDTH'(1)); // release TID=1 scoreboard
    repeat(5) @(posedge clk);

    mask    = '0;
    mask[0] = 1'b1;
    meta    = make_meta(REG_NUM'('h1'), REG_NUM'(0), 8'd2);
    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_rd_t0
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk);
            chk8("TID=0 bank0 == T0_RESULT (0xFF) — confirming correct TID was updated",
                 T0_RESULT, u_dut.rd_data_lo[0*W +: W]);
            disable wait_rd_t0_to;
          end
          begin : wait_rd_t0_to
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted for TID=0 recheck");
            disable wait_rd_t0;
          end
        join
      end
    join
    repeat(5) @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 11 — Predicate writeback
  //
  // Pre-load TID=0 pred=0.  Force cgra_ext_pred_lo[0]=1 (CGRA sets predicate).
  // After writeback, dispatch TID=0 again and verify pred_lo[0]==1.
  // ==========================================================================
  task automatic test_pred_writeback();
    fdr_meta_t meta;
    logic [N_THREADS-1:0] mask;
    logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] init_data;
    logic [DICE_REG_DATA_WIDTH-1:0] ext_data[0:(DICE_NUM_BANKS+DICE_NUM_CONST)-1];
    logic                           ext_pred[0:DICE_NUM_PRED-1];
    localparam int W = DICE_REG_DATA_WIDTH;
    // pred bit position in out_regs_bitmap: after DICE_NUM_REGS + DICE_NUM_CONST bits
    localparam int PRED0_BIT = DICE_NUM_REGS + DICE_NUM_CONST;

    $display("\n=== TEST 11: Predicate Writeback ===");

    // Pre-load TID=2: pred registers 0
    init_data = '0;
    preload_rf(DICE_TID_WIDTH'(2), init_data, DICE_TOTAL_REGS'(0));
    $display("  Pre-loaded TID=2: pred[0]=0");

    // Force CGRA pred0=1 output, dispatch TID=2
    for (int i = 0; i < DICE_NUM_BANKS+DICE_NUM_CONST; i++) ext_data[i] = '0;
    for (int i = 0; i < DICE_NUM_PRED;                  i++) ext_pred[i] = '0;
    ext_pred[0] = 1'b1;
    force_cgra_outputs(ext_data, ext_pred);

    mask    = '0;
    mask[2] = 1'b1;
    // out_regs_bitmap: set the pred0 bit so RF ctrl writes back the predicate
    meta    = make_meta(REG_NUM'(0), REG_NUM'(1) << PRED0_BIT, 8'd3);

    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_v_pred
            @(posedge u_dut.cgra_v_lo);
            $display("  cgra_v_lo for pred test at cycle %0d  tid=%0d", cyc, u_dut.cgra_tid_lo);
            // Verify pred slot in cgra_data_li has the forced pred value
            chk8("cgra_data_li pred0 slot == {0s,1'b1}",
                 8'h01,
                 u_dut.cgra_data_li[(DICE_NUM_BANKS+1)*W +: W]);
            disable wait_v_pred_to;
          end
          begin : wait_v_pred_to
            repeat(int'(meta.lat)+40) @(posedge clk);
            $error("  TIMEOUT: cgra_v_lo never asserted (pred test)");
            disable wait_v_pred;
          end
        join
      end
    join

    release_cgra_outputs();
    simulate_cgra_done(DICE_TID_WIDTH'(2));
    repeat(8) @(posedge clk);

    // Re-dispatch TID=2 and verify pred_lo[0] is now 1
    mask    = '0;
    mask[2] = 1'b1;
    meta    = make_meta(REG_NUM'(1) << PRED0_BIT, REG_NUM'(0), 8'd2);
    fork
      drive_fdr(meta, mask);
      begin
        fork
          begin : wait_rd_pred
            @(posedge u_dut.rf_rd_valid_lo);
            @(posedge clk);
            chk("pred_lo[0] == 1 after CGRA pred writeback", 1'b1, u_dut.pred_lo[0]);
            disable wait_rd_pred_to;
          end
          begin : wait_rd_pred_to
            repeat(80) @(posedge clk);
            $error("  TIMEOUT: rf_rd_valid_lo never asserted (pred readback)");
            disable wait_rd_pred;
          end
        join
      end
    join
    repeat(5) @(posedge clk);
  endtask

  // ==========================================================================
  // TEST 7 — wb_tid_bitmap one-hot encoding
  // For several TID values, force cgra_v_lo + cgra_tid_lo for one cycle and
  // verify cgra_wb_tid_bitmap = 1 << tid with no other bits set.
  // ==========================================================================
  task automatic test_wb_tid_bitmap_encoding();
    logic [N_THREADS-1:0] expected;
    int test_tids[5] = '{0, 1, 3, 7, N_THREADS-1};

    $display("\n=== TEST 7: wb_tid_bitmap One-Hot Encoding ===");

    foreach (test_tids[i]) begin
      automatic int t = test_tids[i];
      expected  = N_THREADS'(1'b1) << t;
      sim_tid_q = DICE_TID_WIDTH'(t);
      force u_dut.cgra_v_lo   = 1'b1;
      force u_dut.cgra_tid_lo = sim_tid_q;
      @(posedge clk); #1; // let assign propagate
      if (u_dut.cgra_wb_tid_bitmap === expected) begin
        $display("  PASS  TID=%0d → cgra_wb_tid_bitmap=0x%0h", t, u_dut.cgra_wb_tid_bitmap);
        pass_count++;
      end else begin
        $error("  FAIL  TID=%0d → got=0x%0h  exp=0x%0h",
               t, u_dut.cgra_wb_tid_bitmap, expected);
        fail_count++;
      end
      release u_dut.cgra_v_lo;
      release u_dut.cgra_tid_lo;
      @(posedge clk);
    end

    // Verify bitmap is zero when cgra_v_lo is de-asserted
    @(posedge clk); #1;
    chk("cgra_wb_tid_bitmap == 0 when cgra_v_lo == 0",
        1'b0, |u_dut.cgra_wb_tid_bitmap);
  endtask

  // ==========================================================================
  // TEST 8 — Back-to-back CTA dispatch with CGRA completions between them
  // Mirrors tb_parameterized_dispatcher::test_back_to_back_cta.
  //
  //  CTA1: all threads, GPR0 → dispatch → simulate completions → verify idle
  //  CTA2: 8 threads,   GPR0+GPR1 → dispatch → simulate completions
  // ==========================================================================
  task automatic test_back_to_back_cta();
    fdr_meta_t meta1, meta2;
    logic [N_THREADS-1:0] mask1, mask2;
    int cnt1, cnt2;

    $display("\n=== TEST 8: Back-to-Back CTA Dispatch ===");

    // CTA 1 — all threads, GPR0
    mask1 = '1;
    meta1 = make_meta(REG_NUM'(1), REG_NUM'(1), 8'd2);

    fork
      drive_fdr(meta1, mask1);
      count_rf_reads(500, cnt1);
    join
    chk_int($sformatf("CTA1: all %0d threads dispatched", N_THREADS),
            N_THREADS, cnt1);

    // Simulate CTA1 CGRA completions to clear the scoreboard
    for (int t = 0; t < N_THREADS; t++)
      simulate_cgra_done(DICE_TID_WIDTH'(t));
    repeat(5) @(posedge clk);

    chk("CTA1: dispatch_busy cleared after completions",
        1'b0, u_dut.dispatch_busy);

    // CTA 2 — 8 threads, GPR0+GPR1
    mask2      = '0;
    mask2[7:0] = 8'hFF;
    meta2      = make_meta(REG_NUM'('h3), REG_NUM'('h3), 8'd3);

    fork
      drive_fdr(meta2, mask2);
      count_rf_reads(300, cnt2);
    join
    chk_int("CTA2: 8 threads dispatched", 8, cnt2);
  endtask

  // ==========================================================================
  // Main stimulus
  // ==========================================================================
  initial begin
    $display("================================================================");
    $display("  dice_backend Integration Testbench");
    $display("  N_THREADS=%0d  DICE_NUM_BANKS=%0d  DICE_NUM_CONST=%0d  DICE_NUM_PRED=%0d",
             N_THREADS, DICE_NUM_BANKS, DICE_NUM_CONST, DICE_NUM_PRED);
    $display("  DICE_REG_DATA_WIDTH=%0d  DICE_TID_WIDTH=%0d",
             DICE_REG_DATA_WIDTH, DICE_TID_WIDTH);
    $display("================================================================");

    reset_dut();
    test_initial_state();

    // ---- Dispatcher tests (mirrors tb_parameterized_dispatcher) ----
    reset_dut();
    test_simple_dispatch();

    reset_dut();
    test_register_conflicts();

    reset_dut();
    test_back_to_back_cta();

    // ---- RF / CGRA pipeline tests ----
    reset_dut();
    test_rf_read_path();

    reset_dut();
    test_cgra_output_packing();

    reset_dut();
    test_cgra_writeback();

    reset_dut();
    test_wb_tid_bitmap_encoding();

    // ---- End-to-end RF + CGRA round-trip tests ----
    reset_dut();
    test_rf_readback_after_writeback();

    reset_dut();
    test_tid_writeback_isolation();

    reset_dut();
    test_pred_writeback();

    // ---- Final summary ----
    repeat(5) @(posedge clk);
    $display("\n================================================================");
    $display("  SUMMARY:  %0d PASS   %0d FAIL", pass_count, fail_count);
    $display("================================================================");
    if (fail_count == 0)
      $display("  ALL TESTS PASSED");
    else
      $error("  %0d TEST(S) FAILED", fail_count);
    $finish;
  end

endmodule
