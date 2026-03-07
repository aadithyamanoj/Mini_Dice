// =============================================================================
// tb_dice_backend_cgra.sv
//
// Connectivity smoke-test for the regfile → input_xbar → CGRA → output_xbar
// → regfile pipeline added to dice_backend.
//
// Test outline
// ────────────
//  1. Pre-load RF:  GPR0[TID=0]=0xAA, GPR1[TID=0]=0x55  (via mem_rsp LDST path)
//  2. Configure crossbars (force sel_reg — see NOTE A below)
//       input  xbar: PE0 ← RF bank0 (GPR0), PE1 ← RF bank1 (GPR1)
//       output xbar: RF bank0 ← CGRA PE0,   RF bank1 ← CGRA PE1
//  3. Dispatch FDR (TID=0, lat=LAT, read GPR0+GPR1, write-back GPR0)
//  4. CHECK  input xbar: gpr_rd_xbar_lo[0]==0xAA, [1]==0x55
//  5. Force CGRA outputs (force cgra_gpr_data_lo — see NOTE B below)
//       PE0 = GPR0 + GPR1 = 0xFF   (simulated ADD)
//       PE1 = GPR1 + 1   = 0x56   (simulated INC)
//  6. CHECK  output xbar: gpr_wb_xbar_lo[0]==0xFF, [1]==0x56
//  7. Force cgra_v_lo=1 for one cycle to trigger RF write-back
//
// ─────────────────────────────────────────────────────────────────────────────
// NOTE A – cfg_load / cfg_sel TODO
//   xbar_cfg_load, gpr_xbar_cfg_sel, and pred_xbar_cfg_sel are all tied to '0
//   inside dice_backend (marked TODO: connect to bitstream decoder).  We
//   therefore force the internal sel_reg registers of each crossbar instance
//   directly.  Once the bitstream decoder is wired up, these forces can be
//   replaced with proper cfg_sel_i / cfg_load_i stimulus.
//
//   cfg_sel_i bitstream layout reminder (for when the decoder is ready):
//     Input  xbar (9-in, 8-out, SEL_WIDTH=4): 8×4 = 32-bit flat vector
//       bits[(i+1)*4-1 : i*4] = selector for PE port i
//     Output xbar (8-in, 9-out, SEL_WIDTH=3): 9×3 = 27-bit flat vector
//       bits[(i+1)*3-1 : i*3] = selector for RF bank i
//
// NOTE B – CGRA not programmed
//   mini_dice prog_* ports are tied to '0, so its outputs are uninitialized X.
//   We force cgra_gpr_data_lo to inject known "computation" results.
//
// NOTE C – Known dice_backend.sv bugs that must be fixed before simulating
//   1. shift_reg instantiation uses .reset_i(reset_i) but dice_backend has no
//      `reset_i` port — should be .reset_i(rst_i)
//   2. Second shift_reg has typo "shif_reg" — should be "shift_reg"
//   3. Both shift_reg instances are named TID_SHIFT — second must be renamed
//      (e.g., WB_MAP_SHIFT)
//   4. cgra_v_lo is declared but never driven by mini_dice — must be connected
//      once the CGRA valid output port exists
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

  localparam int ClkPeriod    = 10;
  localparam int TimeoutCycles = 300;

  // Mirror dice_backend localparams
  localparam int NUM_PE_PORTS  = 8;
  localparam int GPR_N_IN      = DICE_NUM_BANKS + 1;  // 9  (8 GPR banks + 1 const)
  localparam int GPR_N_OUT     = NUM_PE_PORTS;          // 8

  // Selector widths inside each crossbar instance
  localparam int IN_SEL_W  = $clog2(GPR_N_IN);   // 4  — input  xbar, chooses RF bank
  localparam int OUT_SEL_W = $clog2(GPR_N_OUT);  // 3  — output xbar, chooses CGRA PE

  // Test stimulus values
  localparam logic [7:0] GPR0_INIT    = 8'hAA;
  localparam logic [7:0] GPR1_INIT    = 8'h55;
  localparam logic [7:0] CGRA_PE0_OUT = GPR0_INIT + GPR1_INIT; // 0xFF — simulated ADD
  localparam logic [7:0] CGRA_PE1_OUT = GPR1_INIT + 8'h01;     // 0x56 — simulated INC

  // CGRA pipeline latency for this test (must be < 128, the shift_reg MAX_PIPE_STAGE)
  localparam int LAT = 4;

  // ===========================================================================
  // FDR Metadata Generator  (mirrors MetadataGenerator in tb_dice_core_pkg.sv)
  //
  // Generates a randomized fdr_meta_t with lat constrained to [1:10] and the
  // register bitmaps fixed to read GPR0+GPR1 and write-back GPR0.
  // ===========================================================================
  class FdrMetaGen;
    rand fdr_meta_t meta;

    constraint c_lat {
      meta.lat inside {[1:10]};
    }

    constraint c_bitmaps {
      meta.in_regs_bitmap[0]  == 1'b1;  // read  GPR0 (RF bank 0)
      meta.in_regs_bitmap[1]  == 1'b1;  // read  GPR1 (RF bank 1)
      meta.out_regs_bitmap[0] == 1'b1;  // write GPR0 (RF bank 0)
    }

    constraint c_misc {
      meta.bitstream_length == 8'd64;
      meta.unrolling_factor == 2'd0;
      meta.parameter_load   == 1'b0;
    }
  endclass

  // ===========================================================================
  // DUT signals
  // ===========================================================================

  logic clk, rst;

  // FDR interface
  fdr_if fdr_bus ();

  // TMCU outputs — unused in this test, just drain them
  logic                                                                          tmcu_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]                                               tmcu_block_id;
  logic [DICE_TID_WIDTH-1:0]                                                     tmcu_base_tid;
  logic [DICE_TID_BITMAP_WIDTH-1:0]                                              tmcu_tid_bitmap;
  logic                                                                          tmcu_write_enable;
  logic [DICE_CACHE_LINE_SIZE*8-1:0]                                             tmcu_write_data;
  logic [DICE_CACHE_LINE_SIZE-1:0]                                               tmcu_write_mask;
  logic [DICE_ADDR_WIDTH-1:0]                                                    tmcu_address;
  logic [1:0]                                                                    tmcu_size;
  logic [DICE_MAX_REG_WIDTH-1:0]                                                 tmcu_ld_dest_reg;
  logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] tmcu_address_map;

  // mem_rsp_* — used to pre-load the RF via the LDST write path.
  // cache_wr_cmd fields (DE_pkg types):
  //   base_tid       : $clog2(DICE_NUM_MAX_THREADS_PER_CORE) bits = 4 bits
  //   tid_bitmap     : TID_BITMAP_WIDTH bits                    = 8 bits
  //   ld_dest_reg    : DICE_REG_ADDR_WIDTH bits                  = 5 bits
  //   address_map    : NUMBER_OF_MAX_COALESCED_COMMANDS×BASE_ADDRESS_OFFSET = 8×5 bits
  //   data           : CACHE_LINE_SIZE×8 bits                   = 256 bits
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]               mem_rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                      mem_rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                   mem_rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] mem_rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                   mem_rsp_data;
  logic                                                             mem_rsp_valid;

  // BCT — accept all commits immediately
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
  // Clock
  // ===========================================================================

  initial clk = 1'b0;
  always #(ClkPeriod/2) clk = ~clk;

  // ===========================================================================
  // Timeout
  // ===========================================================================

  int cyc;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) cyc <= 0;
    else begin
      cyc <= cyc + 1;
      if (cyc >= TimeoutCycles) begin
        $error("[TIMEOUT] simulation exceeded %0d cycles", TimeoutCycles);
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

  // ─────────────────────────────────────────────────────────────────────────
  // ldst_write_gpr — write one byte into GPR[gpr_idx] for TID=0.
  //
  // Uses the mem_rsp_* (LDST) path that feeds dice_rf_ctrl.
  // bank_select(tid=0, rs=gpr_idx) = (0 + gpr_idx) & 7 = gpr_idx, so a
  // single command slot with address_map[0]=0 writes into the correct bank.
  // ─────────────────────────────────────────────────────────────────────────
  task automatic ldst_write_gpr(
    input logic [DICE_REG_ADDR_WIDTH-1:0] gpr_idx,
    input logic [7:0]                     value
  );
    @(negedge clk);
    mem_rsp_base_tid    = '0;
    mem_rsp_ld_dest_reg = gpr_idx;
    mem_rsp_tid_bitmap  = 8'h01;  // command slot 0 valid → TID = base(0) + map[0](0) = 0
    mem_rsp_address_map = '0;
    mem_rsp_data        = '0;
    mem_rsp_data[7:0]   = value;  // slot 0 data
    mem_rsp_valid       = 1'b1;
    @(posedge clk);
    @(negedge clk);
    mem_rsp_valid = 1'b0;
    @(posedge clk);
  endtask

  // ─────────────────────────────────────────────────────────────────────────
  // drive_fdr — present one FDR packet and hold it stable for `meta.lat`
  // cycles so the TID_SHIFT shift-register captures the correct latency.
  // ─────────────────────────────────────────────────────────────────────────
  task automatic drive_fdr(input fdr_meta_t meta);
    fdr_t pkt;
    pkt                  = '0;
    pkt.real_active_mask = {{(DICE_NUM_MAX_THREADS_PER_CORE-1){1'b0}}, 1'b1}; // TID=0 only
    pkt.metadata         = meta;

    @(negedge clk);
    fdr_bus.valid = 1'b1;
    fdr_bus.data  = pkt;
    @(posedge clk);

    // Keep metadata.lat stable while the shift-reg pipeline fills
    repeat(int'(meta.lat)) @(posedge clk);

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
      $display("  PASS  %-45s  got=0x%02h", label, got);
      pass_count++;
    end else begin
      $error("  FAIL  %-45s  got=0x%02h  exp=0x%02h", label, got, exp);
      fail_count++;
    end
  endtask

  // ===========================================================================
  // Stimulus
  // ===========================================================================

  initial begin

    // ─────────────────────────────────────────────────────────────────────
    // Phase 0 — Reset
    // ─────────────────────────────────────────────────────────────────────
    reset_dut();
    $display("[TB] Reset complete");

    // ─────────────────────────────────────────────────────────────────────
    // Phase 1 — Pre-load register file
    //   GPR0[TID=0] = 0xAA   →   RF bank 0, address 0
    //   GPR1[TID=0] = 0x55   →   RF bank 1, address 0
    // ─────────────────────────────────────────────────────────────────────
    ldst_write_gpr(DICE_REG_ADDR_WIDTH'(0), GPR0_INIT);
    ldst_write_gpr(DICE_REG_ADDR_WIDTH'(1), GPR1_INIT);
    repeat(3) @(posedge clk);
    $display("[TB] RF loaded:  GPR0[TID=0]=0x%02h  GPR1[TID=0]=0x%02h",
             GPR0_INIT, GPR1_INIT);

    // ─────────────────────────────────────────────────────────────────────
    // Phase 2 — Configure crossbars
    //
    //  Input xbar  (9 RF banks → 8 PE ports, SEL_WIDTH=4):
    //    sel_reg[0] = 4'd0 → PE port 0 reads RF bank 0 (GPR0 for TID=0)
    //    sel_reg[1] = 4'd1 → PE port 1 reads RF bank 1 (GPR1 for TID=0)
    //    sel_reg[2..7] = 4'd0 (tied to bank 0, unused PEs)
    //
    //  Equivalent bitstream word (once decoder is wired):
    //    gpr_xbar_cfg_sel = {4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0}
    //                     = 32'h0000_0010
    //
    //  Output xbar (8 PE ports → 9 RF banks, SEL_WIDTH=3):
    //    sel_reg[0] = 3'd0 → RF bank 0 gets CGRA PE output 0
    //    sel_reg[1] = 3'd1 → RF bank 1 gets CGRA PE output 1
    //    sel_reg[2..8] = 3'd0 (tied to PE0, unused banks)
    //
    //  Equivalent bitstream word (lower 27 bits of gpr_xbar_cfg_sel once decoder wired):
    //    {3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd1, 3'd0} = 27'h000_0008
    // ─────────────────────────────────────────────────────────────────────

    // Input xbar sel_reg
    force u_dut.u_gpr_xbar_in.sel_reg[0] = IN_SEL_W'(0); // PE0 ← bank0 (GPR0)
    force u_dut.u_gpr_xbar_in.sel_reg[1] = IN_SEL_W'(1); // PE1 ← bank1 (GPR1)
    force u_dut.u_gpr_xbar_in.sel_reg[2] = IN_SEL_W'(0);
    force u_dut.u_gpr_xbar_in.sel_reg[3] = IN_SEL_W'(0);
    force u_dut.u_gpr_xbar_in.sel_reg[4] = IN_SEL_W'(0);
    force u_dut.u_gpr_xbar_in.sel_reg[5] = IN_SEL_W'(0);
    force u_dut.u_gpr_xbar_in.sel_reg[6] = IN_SEL_W'(0);
    force u_dut.u_gpr_xbar_in.sel_reg[7] = IN_SEL_W'(0);

    // Output xbar sel_reg
    force u_dut.u_gpr_xbar_out.sel_reg[0] = OUT_SEL_W'(0); // bank0 ← PE0
    force u_dut.u_gpr_xbar_out.sel_reg[1] = OUT_SEL_W'(1); // bank1 ← PE1
    force u_dut.u_gpr_xbar_out.sel_reg[2] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[3] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[4] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[5] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[6] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[7] = OUT_SEL_W'(0);
    force u_dut.u_gpr_xbar_out.sel_reg[8] = OUT_SEL_W'(0);

    $display("[TB] Xbar config: in[PE0]←bank0  in[PE1]←bank1 | out[bank0]←PE0  out[bank1]←PE1");

    // ─────────────────────────────────────────────────────────────────────
    // Phase 3 — Dispatch FDR (TID=0)
    //   FdrMetaGen: mirrors MetadataGenerator from tb_dice_core_pkg.sv but
    //   targets fdr_meta_t; lat is randomized in [1:10] then pinned to LAT.
    // ─────────────────────────────────────────────────────────────────────
    begin
      FdrMetaGen  gen = new();
      fdr_meta_t  meta;

      if (!gen.randomize() with { meta.lat == LAT; })
        $fatal(1, "[TB] FdrMetaGen randomize() failed");

      meta = gen.meta;

      // Pin timing-critical fields explicitly
      meta.lat             = 8'(LAT);
      meta.in_regs_bitmap  = REG_NUM'(18'h0_0003); // GPR0 (bit0) + GPR1 (bit1)
      meta.out_regs_bitmap = REG_NUM'(18'h0_0001); // write-back GPR0 (bit0)

      drive_fdr(meta);
      $display("[TB] FDR dispatched  lat=%0d  in_bmp=0x%05h  out_bmp=0x%05h",
               meta.lat, meta.in_regs_bitmap, meta.out_regs_bitmap);
    end

    // ─────────────────────────────────────────────────────────────────────
    // Phase 4 — Check input crossbar outputs (RF → CGRA side)
    //
    //   After the dispatcher triggers an RF read for TID=0:
    //     rd_data_lo[7:0]  = RF bank0[TID=0] = GPR0 = 0xAA
    //     rd_data_lo[15:8] = RF bank1[TID=0] = GPR1 = 0x55
    //
    //   Input xbar (combinational through sel_reg):
    //     gpr_rd_xbar_lo[0] = data_i[ sel_reg[0]=0 ] = rd_data_lo[7:0]  = 0xAA
    //     gpr_rd_xbar_lo[1] = data_i[ sel_reg[1]=1 ] = rd_data_lo[15:8] = 0x55
    //
    //   Wait 10 cycles to cover dispatcher + RF-read latency.
    // ─────────────────────────────────────────────────────────────────────
    repeat(10) @(posedge clk);

    $display("[TB] ─── Phase 4: input crossbar (RF → CGRA) ───");
    check8("gpr_rd_xbar_lo[PE0] == GPR0_INIT (0xAA)",
           u_dut.gpr_rd_xbar_lo[0], GPR0_INIT);
    check8("gpr_rd_xbar_lo[PE1] == GPR1_INIT (0x55)",
           u_dut.gpr_rd_xbar_lo[1], GPR1_INIT);

    // ─────────────────────────────────────────────────────────────────────
    // Phase 5 — Inject simulated CGRA PE output data
    //
    //   cgra_gpr_data_lo layout (from mini_dice port connections):
    //     bits[ 7: 0] = PE output 0  (sb_0_8 East)  — fed from gpr_rd_xbar_lo[4]
    //     bits[15: 8] = PE output 1  (sb_2_8 East)  — fed from gpr_rd_xbar_lo[5]
    //     bits[23:16] = PE output 2  (sb_4_8 East)  — fed from gpr_rd_xbar_lo[6]
    //     bits[31:24] = PE output 3  (sb_6_8 East)  — fed from gpr_rd_xbar_lo[7]
    //     bits[39:32] = PE output 4  (sb_0_0 West)  — fed from gpr_rd_xbar_lo[0]
    //     bits[47:40] = PE output 5  (sb_2_0 West)  — fed from gpr_rd_xbar_lo[1]
    //     bits[55:48] = PE output 6  (sb_4_0 West)  — fed from gpr_rd_xbar_lo[2]
    //     bits[63:56] = PE output 7  (sb_6_0 West)  — fed from gpr_rd_xbar_lo[3]
    //
    //   We model a trivial 1-cycle ADD (PE0) and INC (PE1):
    //     PE0 = GPR0 + GPR1 = 0xAA + 0x55 = 0xFF
    //     PE1 = GPR1 + 1   = 0x55 + 0x01 = 0x56
    // ─────────────────────────────────────────────────────────────────────
    force u_dut.cgra_gpr_data_lo = {
      8'h00,        // PE7 (unused)
      8'h00,        // PE6 (unused)
      8'h00,        // PE5 (unused)
      8'h00,        // PE4 (unused)
      8'h00,        // PE3 (unused)
      8'h00,        // PE2 (unused)
      CGRA_PE1_OUT, // PE1 = 0x56
      CGRA_PE0_OUT  // PE0 = 0xFF
    };

    @(posedge clk);

    // ─────────────────────────────────────────────────────────────────────
    // Phase 6 — Check output crossbar routing (CGRA → RF side)
    //
    //   Output xbar (combinational through sel_reg):
    //     gpr_wb_xbar_lo[0] = cgra_gpr_data_lo[sel_reg[0]=0 * 8 +: 8] = PE0 = 0xFF
    //     gpr_wb_xbar_lo[1] = cgra_gpr_data_lo[sel_reg[1]=1 * 8 +: 8] = PE1 = 0x56
    // ─────────────────────────────────────────────────────────────────────
    $display("[TB] ─── Phase 6: output crossbar (CGRA → RF) ───");
    check8("gpr_wb_xbar_lo[bank0] == CGRA_PE0 (0xFF)",
           u_dut.gpr_wb_xbar_lo[0], CGRA_PE0_OUT);
    check8("gpr_wb_xbar_lo[bank1] == CGRA_PE1 (0x56)",
           u_dut.gpr_wb_xbar_lo[1], CGRA_PE1_OUT);

    // ─────────────────────────────────────────────────────────────────────
    // Phase 7 — Trigger RF write-back
    //
    //   cgra_tid_lo emerges from TID_SHIFT after `lat` cycles post-dispatch.
    //   We already spent 10 (phase 4) + 1 (phase 5) cycles, and LAT=4, so
    //   add a few more to be safe, then pulse cgra_v_lo for one clock edge.
    //
    //   cgra_v_lo is undriven in dice_backend (NOTE C above); force it here.
    // ─────────────────────────────────────────────────────────────────────
    repeat(LAT + 2) @(posedge clk);

    $display("[TB] ─── Phase 7: RF write-back  (cgra_tid_lo=0x%0h) ───",
             u_dut.cgra_tid_lo);

    force u_dut.cgra_v_lo = 1'b1;
    @(posedge clk);
    force u_dut.cgra_v_lo = 1'b0;

    repeat(3) @(posedge clk);

    // ─────────────────────────────────────────────────────────────────────
    // Phase 8 — Release all forces
    // ─────────────────────────────────────────────────────────────────────
    release u_dut.u_gpr_xbar_in.sel_reg[0];
    release u_dut.u_gpr_xbar_in.sel_reg[1];
    release u_dut.u_gpr_xbar_in.sel_reg[2];
    release u_dut.u_gpr_xbar_in.sel_reg[3];
    release u_dut.u_gpr_xbar_in.sel_reg[4];
    release u_dut.u_gpr_xbar_in.sel_reg[5];
    release u_dut.u_gpr_xbar_in.sel_reg[6];
    release u_dut.u_gpr_xbar_in.sel_reg[7];

    release u_dut.u_gpr_xbar_out.sel_reg[0];
    release u_dut.u_gpr_xbar_out.sel_reg[1];
    release u_dut.u_gpr_xbar_out.sel_reg[2];
    release u_dut.u_gpr_xbar_out.sel_reg[3];
    release u_dut.u_gpr_xbar_out.sel_reg[4];
    release u_dut.u_gpr_xbar_out.sel_reg[5];
    release u_dut.u_gpr_xbar_out.sel_reg[6];
    release u_dut.u_gpr_xbar_out.sel_reg[7];
    release u_dut.u_gpr_xbar_out.sel_reg[8];

    release u_dut.cgra_gpr_data_lo;
    release u_dut.cgra_v_lo;

    // ─────────────────────────────────────────────────────────────────────
    // Phase 9 — Summary
    // ─────────────────────────────────────────────────────────────────────
    repeat(5) @(posedge clk);
    $display("[TB] ══════════════════════════════════════════════════");
    $display("[TB]  SUMMARY:  %0d PASS   %0d FAIL", pass_count, fail_count);
    $display("[TB] ══════════════════════════════════════════════════");

    if (fail_count == 0)
      $display("[TB]  ALL TESTS PASSED");
    else
      $error("[TB]  %0d TEST(S) FAILED", fail_count);

    $finish;
  end

  // ===========================================================================
  // Waveform dump (compile with +define+FSDB to enable)
  // ===========================================================================
`ifdef FSDB
  initial begin
    $fsdbDumpfile("tb_dice_backend_cgra.fsdb");
    $fsdbDumpvars(0, tb_dice_backend_cgra, "+struct", "+mda");
  end
`endif

endmodule
