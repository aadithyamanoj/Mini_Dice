// =============================================================================
// tb_cgra_io_csr.sv
//
// Unit testbench for cgra_io_csr.sv
//
// Tests (T1-T11):
//   T1  — post-reset outputs all zero
//   T2  — CTRL cgra_reset + bsload_en level outputs
//   T3  — START_PC write / AXI readback / start_pc_o port
//   T4  — CTRL start bit self-clears after one cycle
//   T5  — STATUS live bits: hw_busy[1] and hw_dispatching[2]
//   T6  — STATUS complete sticky: set by hw_complete_i, cleared by start
//   T7  — STATUS stack_overflow sticky + ERROR_INFO capture; cleared by start
//   T8  — BSLOAD_CNT live readout (hw_bsload_cnt_i)
//   T9  — SIMT_STACK_DEPTH live readout (hw_stack_depth_i)
//   T10 — CSRX0-7 write / AXI readback / csrX output ports
//   T11 — RO register write silently ignored (BSLOAD_CNT)
//
// AXI timing notes (from cgra_io_csr.sv):
//   aw_ready = ~aw_pending_r  (combinatorial)
//   w_ready  = aw_pending_r   (combinatorial, rises 1 cycle after AW)
//   b_valid  = aw_pending_r && w_valid  (combinatorial, same cycle as W)
//   ar_ready = ~ar_pending_r  (combinatorial)
//   r_valid  = ar_pending_r   (combinatorial, rises 1 cycle after AR)
//
// b_ready must be pre-asserted before the W phase because b_valid is
// combinatorial and fires the exact same cycle as the W handshake.
// =============================================================================

`timescale 1ns/1ps
`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module tb_cgra_io_csr;
  import axi4_xbar_pkg::*;
  import DE_pkg::*;

  // =========================================================================
  // Clock and reset
  // =========================================================================
  localparam int CLK_HALF_NS = 5;   // 100 MHz
  localparam int TIMEOUT_NS  = 50000;

  logic clk, rst;

  initial clk = 0;
  always #(CLK_HALF_NS) clk = ~clk;

  initial begin
    #(TIMEOUT_NS);
    $display("[TIMEOUT] simulation exceeded %0d ns", TIMEOUT_NS);
    $finish;
  end

  // =========================================================================
  // DUT interface signals
  // =========================================================================
  mst_req_t  axi_req;
  mst_resp_t axi_resp;

  logic        start_o;
  logic [15:0] start_pc_o;
  logic        cgra_reset_o;
  logic        bsload_en_o;

  logic        hw_busy;
  logic        hw_complete;
  logic        hw_dispatching;
  logic        hw_stack_overflow;
  logic [15:0] hw_stack_depth;
  logic [15:0] hw_error_info;
  logic [15:0] hw_bsload_cnt;

  logic [DICE_REG_DATA_WIDTH-1:0] csrX[8];

  // =========================================================================
  // DUT instantiation
  // =========================================================================
  cgra_io_csr dut (
    .clk_i              (clk),
    .rst_i              (rst),
    .axi_req_i          (axi_req),
    .axi_resp_o         (axi_resp),
    .start_o            (start_o),
    .start_pc_o         (start_pc_o),
    .cgra_reset_o       (cgra_reset_o),
    .bsload_en_o        (bsload_en_o),
    .hw_busy_i          (hw_busy),
    .hw_complete_i      (hw_complete),
    .hw_dispatching_i   (hw_dispatching),
    .hw_stack_overflow_i(hw_stack_overflow),
    .hw_stack_depth_i   (hw_stack_depth),
    .hw_error_info_i    (hw_error_info),
    .hw_bsload_cnt_i    (hw_bsload_cnt),
    .csrX0_o            (csrX[0]),
    .csrX1_o            (csrX[1]),
    .csrX2_o            (csrX[2]),
    .csrX3_o            (csrX[3]),
    .csrX4_o            (csrX[4]),
    .csrX5_o            (csrX[5]),
    .csrX6_o            (csrX[6]),
    .csrX7_o            (csrX[7])
  );

  // =========================================================================
  // CSR address constants (byte-addressed, 2-byte stride)
  // =========================================================================
  localparam logic [15:0] ADDR_CTRL   = 16'h0000;
  localparam logic [15:0] ADDR_PC     = 16'h0002;
  localparam logic [15:0] ADDR_STATUS = 16'h0004;
  localparam logic [15:0] ADDR_BSLOAD = 16'h0006;
  localparam logic [15:0] ADDR_STACK  = 16'h0008;
  localparam logic [15:0] ADDR_ERROR  = 16'h000A;
  localparam logic [15:0] ADDR_CSRX0  = 16'h0010;

  // =========================================================================
  // AXI helper tasks
  // =========================================================================

  // Write task.
  // b_ready must be pre-asserted because b_valid fires combinatorially on
  // the same clock edge as the W handshake — no separate B cycle.
  task automatic axi_write(input logic [15:0] addr, input logic [15:0] wdata);
    @(negedge clk);
    axi_req          = '0;
    axi_req.b_ready  = 1'b1;   // pre-assert before W phase
    axi_req.aw_valid = 1'b1;
    axi_req.aw.addr  = addr;
    axi_req.aw.size  = 3'b010;
    axi_req.aw.burst = 2'b01;
    @(posedge clk iff axi_resp.aw_ready);  // AW handshake
    @(negedge clk);
    axi_req.aw_valid = 1'b0;
    // w_ready is now 1 (aw_pending_r=1 after above posedge)
    axi_req.w_valid  = 1'b1;
    axi_req.w.data   = 32'(wdata);
    axi_req.w.strb   = 4'b0011;
    axi_req.w.last   = 1'b1;
    @(posedge clk iff axi_resp.w_ready);   // W handshake (b fires same cycle)
    @(negedge clk);
    axi_req.w_valid  = 1'b0;
    axi_req.w.last   = 1'b0;
    axi_req.b_ready  = 1'b0;
  endtask

  // Read task.
  // r_valid rises one cycle after AR is accepted (ar_pending_r=1).
  task automatic axi_read(input logic [15:0] addr, output logic [15:0] rdata);
    @(negedge clk);
    axi_req          = '0;
    axi_req.ar_valid = 1'b1;
    axi_req.ar.addr  = addr;
    axi_req.ar.size  = 3'b010;
    axi_req.ar.burst = 2'b01;
    @(posedge clk iff axi_resp.ar_ready);  // AR handshake
    @(negedge clk);
    axi_req.ar_valid = 1'b0;
    axi_req.r_ready  = 1'b1;
    @(posedge clk iff axi_resp.r_valid);   // R handshake
    rdata = axi_resp.r.data[15:0];
    @(negedge clk);
    axi_req.r_ready  = 1'b0;
  endtask

  // Comparison helper
  task automatic check16(
    input string      label,
    input logic [15:0] got,
    input logic [15:0] exp
  );
    if (got !== exp)
      $display("[FAIL] %-40s got=0x%04X  exp=0x%04X", label, got, exp);
    else
      $display("[PASS] %-40s 0x%04X", label, exp);
  endtask

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    // Default stimulus
    axi_req          = '0;
    hw_busy          = 1'b0;
    hw_complete      = 1'b0;
    hw_dispatching   = 1'b0;
    hw_stack_overflow = 1'b0;
    hw_stack_depth   = 16'h0;
    hw_error_info    = 16'h0;
    hw_bsload_cnt    = 16'h0;

    // Apply and release reset
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    // -----------------------------------------------------------------------
    // T1: All hardware outputs are zero after reset
    // -----------------------------------------------------------------------
    $display("\n--- T1: post-reset outputs ---");
    @(negedge clk);
    if (start_o !== 1'b0 || cgra_reset_o !== 1'b0 ||
        bsload_en_o !== 1'b0 || start_pc_o !== 16'h0)
      $display("[FAIL] T1: non-zero hardware output after reset");
    else
      $display("[PASS] T1: all hardware outputs are 0 after reset");

    // -----------------------------------------------------------------------
    // T2: CTRL write — cgra_reset and bsload_en level outputs
    // -----------------------------------------------------------------------
    $display("\n--- T2: CTRL cgra_reset + bsload_en ---");
    // bit[0]=start, bit[1]=cgra_reset, bit[2]=bsload_en
    axi_write(ADDR_CTRL, 16'h0006);
    @(negedge clk);  // let outputs settle
    if (cgra_reset_o !== 1'b1)
      $display("[FAIL] T2: cgra_reset_o expected 1, got %b", cgra_reset_o);
    else
      $display("[PASS] T2: cgra_reset_o=1");
    if (bsload_en_o !== 1'b1)
      $display("[FAIL] T2: bsload_en_o expected 1, got %b", bsload_en_o);
    else
      $display("[PASS] T2: bsload_en_o=1");
    if (start_o !== 1'b0)
      $display("[FAIL] T2: start_o should be 0 (bit[0] not written), got %b", start_o);
    else
      $display("[PASS] T2: start_o=0");

    // -----------------------------------------------------------------------
    // T3: START_PC write, port check, AXI readback
    // -----------------------------------------------------------------------
    $display("\n--- T3: START_PC write/readback ---");
    axi_write(ADDR_PC, 16'hABCD);
    @(negedge clk);
    if (start_pc_o !== 16'hABCD)
      $display("[FAIL] T3-port: start_pc_o=0x%04X exp=0xABCD", start_pc_o);
    else
      $display("[PASS] T3-port: start_pc_o=0xABCD");
    begin
      logic [15:0] rd;
      axi_read(ADDR_PC, rd);
      check16("T3-readback START_PC", rd, 16'hABCD);
    end

    // -----------------------------------------------------------------------
    // T4: CTRL start bit self-clears after one cycle
    // -----------------------------------------------------------------------
    $display("\n--- T4: start bit self-clears ---");
    // Clear any residual state from T2 first
    axi_write(ADDR_CTRL, 16'h0000);
    // Write start=1
    axi_write(ADDR_CTRL, 16'h0001);
    // axi_write returns at negedge after W posedge; ctrl_r[0]=1 now
    if (start_o !== 1'b1)
      $display("[FAIL] T4a: start_o expected 1 immediately after write, got %b", start_o);
    else
      $display("[PASS] T4a: start_o=1 right after write");
    // Next posedge: ctrl_r[0] self-clears to 0
    @(posedge clk); @(negedge clk);
    if (start_o !== 1'b0)
      $display("[FAIL] T4b: start_o did not self-clear, got %b", start_o);
    else
      $display("[PASS] T4b: start_o=0 (self-cleared)");

    // -----------------------------------------------------------------------
    // T5: STATUS live bits — hw_busy[1] and hw_dispatching[2]
    // -----------------------------------------------------------------------
    $display("\n--- T5: STATUS live bits ---");
    @(negedge clk);
    hw_busy        = 1'b1;
    hw_dispatching = 1'b1;
    begin
      logic [15:0] rd;
      axi_read(ADDR_STATUS, rd);
      if (rd[1] !== 1'b1)
        $display("[FAIL] T5: STATUS[1] (busy) expected 1, got 0x%04X", rd);
      else
        $display("[PASS] T5: STATUS[1]=1 (busy live)");
      if (rd[2] !== 1'b1)
        $display("[FAIL] T5: STATUS[2] (dispatching) expected 1, got 0x%04X", rd);
      else
        $display("[PASS] T5: STATUS[2]=1 (dispatching live)");
    end
    @(negedge clk);
    hw_busy        = 1'b0;
    hw_dispatching = 1'b0;

    // -----------------------------------------------------------------------
    // T6: complete sticky — set by hw_complete_i pulse, cleared by start
    // -----------------------------------------------------------------------
    $display("\n--- T6: complete sticky ---");
    @(negedge clk);
    hw_complete = 1'b1;
    @(posedge clk); @(negedge clk);   // sticky latches at this posedge
    hw_complete = 1'b0;
    begin
      logic [15:0] rd;
      axi_read(ADDR_STATUS, rd);
      if (rd[0] !== 1'b1)
        $display("[FAIL] T6a: STATUS[0] (complete) not sticky after pulse, got 0x%04X", rd);
      else
        $display("[PASS] T6a: STATUS[0]=1 (complete sticky)");
    end
    // Write start to clear sticky (clears one cycle after ctrl_r[0] is set)
    axi_write(ADDR_CTRL, 16'h0001);
    begin
      logic [15:0] rd;
      axi_read(ADDR_STATUS, rd);   // axi_read takes several cycles, well past W+1
      if (rd[0] !== 1'b0)
        $display("[FAIL] T6b: complete sticky not cleared by start, got 0x%04X", rd);
      else
        $display("[PASS] T6b: complete sticky cleared by start");
    end

    // -----------------------------------------------------------------------
    // T7: stack_overflow sticky + error_info capture; both cleared by start
    // -----------------------------------------------------------------------
    $display("\n--- T7: stack_overflow sticky + error_info ---");
    @(negedge clk);
    hw_stack_overflow = 1'b1;
    hw_error_info     = 16'hDEAD;
    @(posedge clk); @(negedge clk);   // sticky latches
    hw_stack_overflow = 1'b0;
    begin
      logic [15:0] stat_rd, err_rd;
      axi_read(ADDR_STATUS, stat_rd);
      if (stat_rd[3] !== 1'b1)
        $display("[FAIL] T7a: STATUS[3] (stack_overflow) not sticky, got 0x%04X", stat_rd);
      else
        $display("[PASS] T7a: STATUS[3]=1 (stack_overflow sticky)");
      axi_read(ADDR_ERROR, err_rd);
      check16("T7b: ERROR_INFO captured", err_rd, 16'hDEAD);
    end
    // Clear both via start
    axi_write(ADDR_CTRL, 16'h0001);
    begin
      logic [15:0] stat_rd, err_rd;
      axi_read(ADDR_STATUS, stat_rd);
      if (stat_rd[3] !== 1'b0)
        $display("[FAIL] T7c: stack_overflow sticky not cleared by start, got 0x%04X", stat_rd);
      else
        $display("[PASS] T7c: stack_overflow cleared by start");
      axi_read(ADDR_ERROR, err_rd);
      check16("T7d: ERROR_INFO cleared by start", err_rd, 16'h0000);
    end

    // -----------------------------------------------------------------------
    // T8: BSLOAD_CNT live readout
    // -----------------------------------------------------------------------
    $display("\n--- T8: BSLOAD_CNT live ---");
    @(negedge clk);
    hw_bsload_cnt = 16'h00AB;
    begin
      logic [15:0] rd;
      axi_read(ADDR_BSLOAD, rd);
      check16("T8: BSLOAD_CNT", rd, 16'h00AB);
    end

    // -----------------------------------------------------------------------
    // T9: SIMT_STACK_DEPTH live readout
    // -----------------------------------------------------------------------
    $display("\n--- T9: SIMT_STACK_DEPTH live ---");
    @(negedge clk);
    hw_stack_depth = 16'h0007;
    begin
      logic [15:0] rd;
      axi_read(ADDR_STACK, rd);
      check16("T9: SIMT_STACK_DEPTH", rd, 16'h0007);
    end

    // -----------------------------------------------------------------------
    // T10: CSRX0-7 write / AXI readback / output port check
    // -----------------------------------------------------------------------
    $display("\n--- T10: CSRX0-7 write/readback ---");
    begin
      logic [15:0] rd;
      for (int i = 0; i < 8; i++) begin
        automatic logic [15:0] wval = 16'(16'hA000 + i);
        axi_write(ADDR_CSRX0 + 16'(2*i), wval);
      end
      for (int i = 0; i < 8; i++) begin
        automatic logic [15:0] wval = 16'(16'hA000 + i);
        axi_read(ADDR_CSRX0 + 16'(2*i), rd);
        check16($sformatf("T10-axi  CSRX%0d", i), rd, wval);
        @(negedge clk);
        if (csrX[i] !== wval)
          $display("[FAIL] T10-port CSRX%0d: got=0x%04X  exp=0x%04X", i, csrX[i], wval);
        else
          $display("[PASS] T10-port CSRX%0d=0x%04X", i, csrX[i]);
      end
    end

    // -----------------------------------------------------------------------
    // T11: RO register write silently ignored (attempt write to BSLOAD_CNT)
    // -----------------------------------------------------------------------
    $display("\n--- T11: RO write silently ignored ---");
    begin
      logic [15:0] before_rd, after_rd;
      @(negedge clk);
      hw_bsload_cnt = 16'h0055;
      axi_read(ADDR_BSLOAD, before_rd);
      axi_write(ADDR_BSLOAD, 16'hFFFF);   // write to RO register
      axi_read(ADDR_BSLOAD, after_rd);
      if (after_rd !== before_rd)
        $display("[FAIL] T11: RO BSLOAD_CNT changed after write: before=0x%04X after=0x%04X",
                 before_rd, after_rd);
      else
        $display("[PASS] T11: RO write ignored, BSLOAD_CNT=0x%04X (unchanged)", after_rd);
    end

    // -----------------------------------------------------------------------
    repeat (5) @(posedge clk);
    $display("\n=== tb_cgra_io_csr complete ===");
    $finish;
  end

endmodule : tb_cgra_io_csr
