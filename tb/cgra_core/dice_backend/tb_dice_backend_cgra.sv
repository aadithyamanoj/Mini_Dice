// =============================================================================
// tb_dice_backend_cgra.sv
//
// Connectivity smoke-test for the full
//   RF → input_xbar → CGRA → output_xbar → RF
// pipeline in dice_backend.
//
// Test outline
// ────────────
//  1. Pre-load RF:  GPR0[TID=0]=0xAA, GPR1[TID=0]=0x55  (mem_rsp LDST path)
//  2. Derive fake "bitstream" crossbar config (cfg_sel values), force into
//     xbar sel_reg (see NOTE A).
//  3. Generate metadata with MetadataGenerator (matches tb_dice_core_pkg.sv),
//     override bitmaps, dispatch FDR for TID=0.
//  4. CHECK  input xbar outputs gpr_rd_xbar_lo carry the correct RF values.
//  5. Force CGRA PE output bus cgra_gpr_data_lo with known results (NOTE B).
//  6. CHECK  output xbar outputs gpr_wb_xbar_lo route data to correct banks.
//  7. cgra_v_lo is asserted automatically by CGRA_V_SHIFT (rf_rd_valid_lo
//     shifted by lat cycles) — no manual force needed.
//  8. Wait for RF write-back, then done.
//
// ─────────────────────────────────────────────────────────────────────────────
// NOTE A – Fake bitstream crossbar configuration
//   dice_backend has gpr_xbar_cfg_sel and xbar_cfg_load TODO-tied to '0 (the
//   bitstream decoder path is not yet wired).  We model what the bitstream
//   decoder would produce by computing cfg_sel locally and forcing the crossbar
//   sel_reg registers directly.  Once the decoder is connected these forces
//   become plain cfg_sel_i / cfg_load_i stimulus.
//
//   cfg_sel_i bit layout (per cgra_crossbar):
//     bits [(i+1)*SEL_W-1 : i*SEL_W] = selector for output port i
//
//   Input GPR xbar  (NUM_INPUTS=16, NUM_OUTPUTS=8, SEL_W=4, cfg_sel=32b):
//     PE0 ← bank 0 (GPR0, sel=0): cfg_sel[3:0]  = 4'h0
//     PE1 ← bank 1 (GPR1, sel=1): cfg_sel[7:4]  = 4'h1
//     PE2-7 ← bank 0 (unused):    cfg_sel[31:8] = 0
//     ──► IN_XBAR_CFG_SEL = 32'h0000_0010
//
//   Output GPR xbar (NUM_INPUTS=8, NUM_OUTPUTS=16, SEL_W=3, full cfg=48b):
//     bank0 ← PE0 (sel=0): cfg_sel[2:0] = 3'h0
//     bank1 ← PE1 (sel=1): cfg_sel[5:3] = 3'h1
//     bank2-15 ← PE0:      cfg_sel[47:6] = 0
//     ──► OUT_XBAR_CFG_SEL_LO = 32'h0000_0008  (lower 32 of 48 bits carried
//         by gpr_xbar_cfg_sel — upper 16 bits are a design TODO)
//
// NOTE B – CGRA not programmed
//   mini_dice prog_* ports are tied off so its PE outputs are X.
//   We force cgra_gpr_data_lo to inject known results representing:
//     PE0 = GPR0 + GPR1 = 0xAA + 0x55 = 0xFF  (simulated ADD)
//     PE1 = GPR1 + 1   = 0x55 + 0x01 = 0x56  (simulated INC)
//
// NOTE C – cgra_v_lo timing
//   CGRA_V_SHIFT in dice_backend shifts rf_rd_valid_lo by metadata.lat cycles.
//   No manual force is needed; the TB just waits long enough for the shift to
//   complete and the RF write-back to settle.
// =============================================================================

`timescale 1ns/1ps
`include "dice_define.vh"

module tb_dice_backend_cgra;

  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;

  // ===========================================================================
  // Parameters
  // ===========================================================================

  localparam int METADATA_ALIGN = $clog2(DICE_METADATA_WIDTH); // bits to zero for alignment

  localparam int ClkPeriod     = 10;
  localparam int TimeoutCycles = 400;

  // Mirror dice_backend crossbar localparams (post-update: full const bank)
  localparam int NUM_PE_PORTS  = 8;
  localparam int GPR_N_IN      = DICE_NUM_REGS + DICE_NUM_CONST; // 16
  localparam int GPR_N_OUT     = NUM_PE_PORTS;                    // 8
  localparam int IN_SEL_W      = $clog2(GPR_N_IN);                // 4
  localparam int OUT_SEL_W     = $clog2(GPR_N_OUT);               // 3

  // ─── Fake bitstream crossbar config ────────────────────────────────────────
  // These values represent what the bitstream decoder would write into the
  // two GPR crossbars for this p-graph:
  //   • Input  xbar: PE0 ← bank0 (GPR0),  PE1 ← bank1 (GPR1)
  //   • Output xbar: bank0 ← PE0 result,  bank1 ← PE1 result
  localparam logic [31:0] IN_XBAR_CFG_SEL  = 32'h0000_0010;
  //   sel[1]=1 at bits[7:4]  → PE1 ← bank1
  //   sel[0]=0 at bits[3:0]  → PE0 ← bank0

  localparam logic [47:0] OUT_XBAR_CFG_SEL = 48'h0000_0000_0008;
  //   sel[1]=1 at bits[5:3]  → bank1 ← PE1
  //   sel[0]=0 at bits[2:0]  → bank0 ← PE0
  //   Full 48-bit config for output xbar (16 outputs × SEL_W=3)
  // ───────────────────────────────────────────────────────────────────────────

  // Test stimulus values
  localparam logic [7:0] GPR0_INIT    = 8'hAA;
  localparam logic [7:0] GPR1_INIT    = 8'h55;
  localparam logic [7:0] CGRA_PE0_OUT = GPR0_INIT + GPR1_INIT; // 0xFF — ADD
  localparam logic [7:0] CGRA_PE1_OUT = GPR1_INIT + 8'h01;     // 0x56 — INC

  // ===========================================================================
  // Waveform dump (compile with +define+FSDB to enable)
  // ===========================================================================
  `ifdef FSDB
    initial begin
      $fsdbDumpfile("waveform.fsdb");
      $fsdbDumpvars(0, tb_dice_backend_cgra, "+struct", "+mda");
    end
  `endif

  // ===========================================================================
  // MetadataGenerator — identical structure to tb_dice_core_pkg.sv.
  // Generates pgraph_meta_t; caller extracts fdr_meta_t fields from it.
  // ===========================================================================
  class MetadataGenerator;
    rand pgraph_meta_t metadata;

    constraint base_metadata {
      metadata.bitstream_length inside {[1:255]};
      metadata.num_stores inside {[0:3]};
      metadata.lat inside {[1:10]};
      metadata.unrolling_factor == 0;
      metadata.barrier == 0;
      metadata.parameter_load == 0;
      metadata.bitstream_addr[METADATA_ALIGN-1:0] == '0;
    }

    constraint branch_metadata {
      metadata.branch_meta.branch_ena == 0;
      metadata.branch_meta.branch_uni dist {0:=50, 1:=50};
      metadata.branch_meta.branch_pred_reg inside {[0:7]};
      metadata.branch_meta.branch_jump_target_offset inside {[1:3]};
      metadata.branch_meta.branch_reconv_offset inside {[1:3]};
    }
  endclass

  // ===========================================================================
  // DUT signals
  // ===========================================================================

  logic clk, rst;

  fdr_if fdr_bus ();

  // TMCU outputs — drain
  logic                                                                           tmcu_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]                                                tmcu_block_id;
  logic [DICE_TID_WIDTH-1:0]                                                      tmcu_base_tid;
  logic [DICE_TID_BITMAP_WIDTH-1:0]                                               tmcu_tid_bitmap;
  logic                                                                           tmcu_write_enable;
  logic [DICE_CACHE_LINE_SIZE*8-1:0]                                              tmcu_write_data;
  logic [DICE_CACHE_LINE_SIZE-1:0]                                                tmcu_write_mask;
  logic [DICE_ADDR_WIDTH-1:0]                                                     tmcu_address;
  logic [1:0]                                                                     tmcu_size;
  logic [DICE_MAX_REG_WIDTH-1:0]                                                  tmcu_ld_dest_reg;
  logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] tmcu_address_map;

  // mem_rsp — LDST pre-load path
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                    mem_rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                          mem_rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                       mem_rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] mem_rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                       mem_rsp_data;
  logic                                                                 mem_rsp_valid;

  // BCT
  logic                         eblock_commit_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id;

  // ===========================================================================
  // DUT
  // ===========================================================================

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
    .hw_cta_pending_o      ()
  );

  // ===========================================================================
  // Clock & timeout
  // ===========================================================================

  initial clk = 1'b0;
  always #(ClkPeriod/2) clk = ~clk;

  int cyc;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) cyc <= 0;
    else begin
      cyc <= cyc + 1;
      if (cyc >= TimeoutCycles) begin
        $error("[TIMEOUT] exceeded %0d cycles", TimeoutCycles);
        $finish;
      end
    end
  end

  // ===========================================================================
  // Tasks
  // ===========================================================================

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
    repeat(5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  // Staging registers for CGRA write forces (force RHS cannot use automatic vars)
  logic [DICE_TID_WIDTH-1:0]                                         cgra_wr_tid_q;
  logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0]   cgra_wr_data_q;   // 88b
  logic [DICE_TOTAL_REGS-1:0]                                        cgra_wr_bitmap_q;

  // Pre-load RF via the CGRA write port on dice_rf_ctrl.
  // Mirrors write_cgra_only() from dice_rf_ctrl_tb.sv.
  //   tid      – thread ID to write
  //   data     – packed 88-bit bus: bits[i*8+:8] = GPR bank i data
  //   wr_bitmap – DICE_TOTAL_REGS-wide mask; bit i = 1 writes GPR bank i
  task automatic write_cgra_gpr(
    input logic [DICE_TID_WIDTH-1:0]                                        tid,
    input logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0]  data,
    input logic [DICE_TOTAL_REGS-1:0]                                       wr_bitmap
  );
    cgra_wr_tid_q    = tid;
    cgra_wr_data_q   = data;
    cgra_wr_bitmap_q = wr_bitmap;
    force u_dut.u_dice_rf_ctrl.cgra_valid_i = 1'b1;
    force u_dut.u_dice_rf_ctrl.cgra_tid_i   = cgra_wr_tid_q;
    force u_dut.u_dice_rf_ctrl.cgra_data_i  = cgra_wr_data_q;
    force u_dut.u_dice_rf_ctrl.wr_bitmap_i  = cgra_wr_bitmap_q;
    @(posedge clk);
    @(posedge clk);
    release u_dut.u_dice_rf_ctrl.cgra_valid_i;
    release u_dut.u_dice_rf_ctrl.cgra_tid_i;
    release u_dut.u_dice_rf_ctrl.cgra_data_i;
    release u_dut.u_dice_rf_ctrl.wr_bitmap_i;
  endtask

  // Apply a fake bitstream crossbar config.
  //
  // We force the RTL cfg_sel signals (driven by assign='0 in dice_backend) to
  // the desired values and pulse xbar_cfg_load for one cycle.  The crossbar's
  // always_ff then naturally latches sel_reg = cfg_sel_i.  Forcing a net driven
  // by a continuous assignment is reliable in VCS; forcing sel_reg directly
  // (an always_ff variable) is not, because VCS may release the force when the
  // always_ff block evaluates.
  // force RHS cannot reference automatic (task-local) variables; copy inputs
  // into module-level statics first.
  logic [31:0] xbar_in_cfg_q;
  logic [47:0] xbar_out_cfg_q;

  task automatic apply_xbar_cfg(
    input logic [31:0] in_cfg_sel,   // cfg_sel for input  xbar (8  outputs × SEL_W=4 → 32b)
    input logic [47:0] out_cfg_sel   // cfg_sel for output xbar (16 outputs × SEL_W=3 → 48b)
  );
    xbar_in_cfg_q  = in_cfg_sel;
    xbar_out_cfg_q = out_cfg_sel;
    force u_dut.gpr_rd_xbar_cfg_sel = xbar_in_cfg_q;
    force u_dut.gpr_wb_xbar_cfg_sel = xbar_out_cfg_q;
    force u_dut.xbar_cfg_load       = 1'b1;
    @(posedge clk);  // always_ff latches sel_reg in both crossbars
    release u_dut.xbar_cfg_load;       // back to 0; no further latching
    release u_dut.gpr_rd_xbar_cfg_sel; // sel_reg now holds values permanently
    release u_dut.gpr_wb_xbar_cfg_sel;
  endtask

  task automatic release_xbar_cfg();
    // Forces were released in apply_xbar_cfg after latching; nothing to do.
  endtask

  // Dispatch FDR for TID=0 using the fdr_meta_t derived from the caller's
  // MetadataGenerator output.  Hold valid until ready is asserted (handshake).
  task automatic drive_fdr(input fdr_meta_t meta);
    fdr_t pkt;
    pkt                  = '0;
    pkt.real_active_mask = {{(DICE_NUM_MAX_THREADS_PER_CORE-1){1'b0}}, 1'b1}; // TID=0
    pkt.metadata         = meta;
    @(negedge clk);
    fdr_bus.valid = 1'b1;
    fdr_bus.data  = pkt;
    // Hold valid until the receiver asserts ready (valid+ready handshake)
    do @(posedge clk); while (!fdr_bus.ready);
    @(negedge clk);
    fdr_bus.valid = 1'b0;
    fdr_bus.data  = '0;
  endtask

  // ===========================================================================
  // Scoreboard
  // ===========================================================================

  int pass_count = 0, fail_count = 0;

  task automatic check8(
    input string      label,
    input logic [7:0] got,
    input logic [7:0] exp
  );
    if (got === exp) begin
      $display("  PASS  %-50s  got=0x%02h", label, got);
      pass_count++;
    end else begin
      $error("  FAIL  %-50s  got=0x%02h  exp=0x%02h", label, got, exp);
      fail_count++;
    end
  endtask

  // ===========================================================================
  // Stimulus
  // ===========================================================================

  initial begin

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 0 — Reset
    // ─────────────────────────────────────────────────────────────────────────
    reset_dut();
    $display("[TB] Reset complete");

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 1 — Pre-load register file via CGRA write port
    //   GPR0[TID=0] = 0xAA  →  RF bank 0  (cgra_data_i[7:0])
    //   GPR1[TID=0] = 0x55  →  RF bank 1  (cgra_data_i[15:8])
    //   wr_bitmap[1:0] = 2'b11 enables writes to banks 0 and 1
    // ─────────────────────────────────────────────────────────────────────────
    begin
      // Build 88-bit data bus: bank0 at [7:0], bank1 at [15:8], rest zero
      logic [(DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH-1:0] init_data;
      init_data          = '0;
      init_data[0*8 +: 8] = GPR0_INIT;
      init_data[1*8 +: 8] = GPR1_INIT;
      write_cgra_gpr(DICE_TID_WIDTH'(0), init_data, DICE_TOTAL_REGS'(18'h0003));
    end
    repeat(2) @(posedge clk);
    $display("[TB] RF loaded:  GPR0[TID=0]=0x%02h  GPR1[TID=0]=0x%02h",
             GPR0_INIT, GPR1_INIT);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 2 — Apply fake bitstream crossbar configuration
    //
    //   IN_XBAR_CFG_SEL  = 32'h0000_0010  →  PE0←bank0, PE1←bank1
    //   OUT_XBAR_CFG_SEL = 32'h0000_0008  →  bank0←PE0, bank1←PE1
    //
    //   Decoding IN_XBAR_CFG_SEL (SEL_W=4):
    //     bits[3:0]  = 4'h0  → sel_reg[0] = 0  → PE0 gets data_i[0] = GPR0
    //     bits[7:4]  = 4'h1  → sel_reg[1] = 1  → PE1 gets data_i[1] = GPR1
    //     bits[31:8] = 0     → sel_reg[2..7] = 0
    //
    //   Decoding OUT_XBAR_CFG_SEL (SEL_W=3):
    //     bits[2:0]  = 3'h0  → sel_reg[0] = 0  → bank0 gets cgra_data[0] = PE0
    //     bits[5:3]  = 3'h1  → sel_reg[1] = 1  → bank1 gets cgra_data[1] = PE1
    //     bits[31:6] = 0     → sel_reg[2..10] = 0
    // ─────────────────────────────────────────────────────────────────────────
    apply_xbar_cfg(IN_XBAR_CFG_SEL, OUT_XBAR_CFG_SEL);
    $display("[TB] Xbar config applied:");
    $display("[TB]   Input  cfg_sel = 32'h%08h  (PE0←bank0, PE1←bank1)",
             IN_XBAR_CFG_SEL);
    $display("[TB]   Output cfg_sel = 48'h%012h  (bank0←PE0, bank1←PE1)",
             OUT_XBAR_CFG_SEL);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 3 — Inject simulated CGRA computation result
    //
    //   Force cgra_gpr_data_lo before dispatch so it is stable when the
    //   write-back valid arrives.  cgra_gpr_data_lo layout (from mini_dice
    //   port connections in dice_backend):
    //     bits[ 7: 0] = PE out 0  (sb_0_8 East)
    //     bits[15: 8] = PE out 1  (sb_2_8 East)
    //     bits[23:16] = PE out 2  (sb_4_8 East)
    //     bits[31:24] = PE out 3  (sb_6_8 East)
    //     bits[39:32] = PE out 4  (sb_0_0 West)
    //     bits[47:40] = PE out 5  (sb_2_0 West)
    //     bits[55:48] = PE out 6  (sb_4_0 West)
    //     bits[63:56] = PE out 7  (sb_6_0 West)
    //
    //   PE0 = ADD(GPR0, GPR1) = 0xAA + 0x55 = 0xFF
    //   PE1 = INC(GPR1)       = 0x55 + 0x01 = 0x56
    // ─────────────────────────────────────────────────────────────────────────
    force u_dut.cgra_gpr_data_lo = {
      8'h00,        // PE7 — unused
      8'h00,        // PE6 — unused
      8'h00,        // PE5 — unused
      8'h00,        // PE4 — unused
      8'h00,        // PE3 — unused
      8'h00,        // PE2 — unused
      CGRA_PE1_OUT, // PE1 = 0x56  (INC)
      CGRA_PE0_OUT  // PE0 = 0xFF  (ADD)
    };
    $display("[TB] CGRA outputs forced:  PE0=0x%02h (ADD)  PE1=0x%02h (INC)",
             CGRA_PE0_OUT, CGRA_PE1_OUT);

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 4 — Generate metadata and dispatch FDR
    //
    //   MetadataGenerator matches tb_dice_core_pkg.sv exactly.
    //   We override in/out_regs_bitmap after randomization to pin which
    //   registers participate in this test.
    //
    //   in_regs_bitmap[0]  = 1  →  read GPR0
    //   in_regs_bitmap[1]  = 1  →  read GPR1
    //   out_regs_bitmap[0] = 1  →  write-back GPR0
    // ─────────────────────────────────────────────────────────────────────────
    begin
      MetadataGenerator gen = new();
      fdr_meta_t        meta;

      if (!gen.randomize())
        $fatal(1, "[TB] MetadataGenerator randomize() failed");

      // Extract fdr_meta_t fields from pgraph_meta_t
      meta                  = '0;
      meta.bitstream_length = gen.metadata.bitstream_length;
      meta.lat              = gen.metadata.lat;
      meta.unrolling_factor = gen.metadata.unrolling_factor;
      meta.parameter_load   = gen.metadata.parameter_load;
      meta.ld_dest_regs     = gen.metadata.ld_dest_regs;
      meta.num_stores       = gen.metadata.num_stores;

      // Pin register bitmaps for this test
      meta.in_regs_bitmap              = '0;
      meta.in_regs_bitmap[0]           = 1'b1; // GPR0
      meta.in_regs_bitmap[1]           = 1'b1; // GPR1
      meta.out_regs_bitmap             = '0;
      meta.out_regs_bitmap[0]          = 1'b1; // write-back GPR0

      $display("[TB] FDR metadata:  lat=%0d  in_bmp=0x%05h  out_bmp=0x%05h",
               meta.lat, meta.in_regs_bitmap, meta.out_regs_bitmap);

      drive_fdr(meta);
      $display("[TB] FDR dispatched for TID=0");

      // ───────────────────────────────────────────────────────────────────────
      // Phase 5 — Check input crossbar (RF → CGRA side)
      //
      //   After the dispatcher triggers an RF read for TID=0:
      //     rd_data_lo[7:0]  = RF bank0[TID=0] = 0xAA
      //     rd_data_lo[15:8] = RF bank1[TID=0] = 0x55
      //
      //   Input xbar with sel_reg = IN_XBAR_CFG_SEL:
      //     gpr_rd_xbar_lo[0] = data_i[ sel=0 ] = bank0 data = 0xAA
      //     gpr_rd_xbar_lo[1] = data_i[ sel=1 ] = bank1 data = 0x55
      //
      //   Wait long enough for dispatcher + RF read pipeline.
      // ───────────────────────────────────────────────────────────────────────
      repeat(12) @(posedge clk);

      // Debug: isolate which layer produces wrong values
      $display("[TB] DBG sel_reg      = 32'h%08h  (expect 32'h00000010)",
               u_dut.u_gpr_xbar_in.sel_reg);
      $display("[TB] DBG rd_data_lo[0]= 0x%02h  (expect 0xaa)",
               u_dut.rd_data_lo[7:0]);
      $display("[TB] DBG rd_data_lo[1]= 0x%02h  (expect 0x55)",
               u_dut.rd_data_lo[15:8]);
      $display("[TB] DBG xbar data_i[0]=0x%02h  data_i[1]=0x%02h",
               u_dut.u_gpr_xbar_in.data_i[0], u_dut.u_gpr_xbar_in.data_i[1]);

      $display("[TB] ─── Phase 5: input crossbar (RF → CGRA) ───");
      check8("gpr_rd_xbar_lo[PE0] == GPR0_INIT (0xAA)",
             u_dut.gpr_rd_xbar_lo[0], GPR0_INIT);
      check8("gpr_rd_xbar_lo[PE1] == GPR1_INIT (0x55)",
             u_dut.gpr_rd_xbar_lo[1], GPR1_INIT);

      // ───────────────────────────────────────────────────────────────────────
      // Phase 6 — Check output crossbar (CGRA → RF side)
      //
      //   cgra_gpr_data_lo is forced; output xbar routes immediately:
      //     gpr_wb_xbar_lo[0] = cgra_data_lo[ sel=0 ] = PE0 = 0xFF
      //     gpr_wb_xbar_lo[1] = cgra_data_lo[ sel=1 ] = PE1 = 0x56
      // ───────────────────────────────────────────────────────────────────────
      $display("[TB] ─── Phase 6: output crossbar (CGRA → RF) ───");
      check8("gpr_wb_xbar_lo[bank0] == CGRA_PE0 (0xFF)",
             u_dut.gpr_wb_xbar_lo[0], CGRA_PE0_OUT);
      check8("gpr_wb_xbar_lo[bank1] == CGRA_PE1 (0x56)",
             u_dut.gpr_wb_xbar_lo[1], CGRA_PE1_OUT);

      // ───────────────────────────────────────────────────────────────────────
      // Phase 7 — Wait for CGRA_V_SHIFT to assert cgra_v_lo
      //
      //   dice_backend CGRA_V_SHIFT shifts rf_rd_valid_lo by metadata.lat
      //   cycles.  We already waited ~12 cycles; allow up to lat more cycles
      //   plus some margin for dispatcher + RF-read overhead.
      // ───────────────────────────────────────────────────────────────────────
      $display("[TB] Waiting for cgra_v_lo (lat=%0d cycles from RF read valid)...",
               meta.lat);

      fork
        begin : wait_v
          @(posedge u_dut.cgra_v_lo);
          $display("[TB] cgra_v_lo asserted at cycle %0d  tid_lo=0x%0h",
                   cyc, u_dut.cgra_tid_lo);
          disable timeout_v;
        end
        begin : timeout_v
          repeat(int'(meta.lat) + 30) @(posedge clk);
          $error("[TB] cgra_v_lo never asserted within expected window");
          disable wait_v;
        end
      join

      // Allow RF write-back to complete
      repeat(5) @(posedge clk);
    end

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 8 — Release forces
    // ─────────────────────────────────────────────────────────────────────────
    release_xbar_cfg();
    release u_dut.cgra_gpr_data_lo;

    // ─────────────────────────────────────────────────────────────────────────
    // Phase 9 — Summary
    // ─────────────────────────────────────────────────────────────────────────
    repeat(3) @(posedge clk);
    $display("[TB] ══════════════════════════════════════════════════════════");
    $display("[TB]  SUMMARY:  %0d PASS   %0d FAIL", pass_count, fail_count);
    $display("[TB] ══════════════════════════════════════════════════════════");
    if (fail_count == 0)
      $display("[TB]  ALL TESTS PASSED");
    else
      $error("[TB]  %0d TEST(S) FAILED", fail_count);

    $finish;
  end



endmodule
