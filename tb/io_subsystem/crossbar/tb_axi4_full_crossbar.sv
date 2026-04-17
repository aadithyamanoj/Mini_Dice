// =============================================================================
// tb_axi4_full_crossbar.sv
//
// Testbench for axi4_full_crossbar.
//
// Test scenarios
// --------------
//  T1  : FPGA master single-beat writes to all 8 CSR registers
//  T2  : FPGA master reads back all 8 CSR registers (verifies T1)
//  T3  : dfetch    single-beat reads from FPGA SRAM (first 8 words)
//  T4  : mfetch    single-beat reads from FPGA SRAM (words 16–23)
//  T5  : bsfetch   single-beat reads from FPGA SRAM (words 32–39)
//  T6  : dfetch    burst read (INCR, 4 beats) from FPGA SRAM
//  T7  : bsfetch   burst read (INCR, 8 beats) from FPGA SRAM
//  T8  : Concurrent – fpga_mst writes CSR while dfetch reads SRAM
//  T9  : FPGA master writes SRAM, dfetch reads it back (loopback)
//  T10 : Out-of-range address → expect DECERR
// =============================================================================

`timescale 1ns/1ps

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module tb_axi4_full_crossbar;

  import axi4_xbar_pkg::*;
  import axi_pkg::*;

  // -------------------------------------------------------------------------
  // Simulation parameters
  // -------------------------------------------------------------------------
  localparam int CLK_PERIOD_NS = 10;

  localparam int MEM_WORDS   = 1024;
  localparam int MEM_BASE    = 16'h0800;
  localparam int CSR_NUM_REG = 8;
  localparam int CSR_BASE_A  = 16'h0000;

  // -------------------------------------------------------------------------
  // Clock / reset  (active-high)
  // -------------------------------------------------------------------------
  logic clk, rst;
  initial clk = 0;
  always #(CLK_PERIOD_NS/2) clk = ~clk;

  // -------------------------------------------------------------------------
  // DUT I/O signals
  // -------------------------------------------------------------------------
  slv_req_t  fpga_mst_req,  dfetch_req,  mfetch_req,  bsfetch_req;
  slv_resp_t fpga_mst_resp, dfetch_resp, mfetch_resp, bsfetch_resp;

  mst_req_t  fpga_mem_req,  cgra_csr_req;
  mst_resp_t fpga_mem_resp, cgra_csr_resp;

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  axi4_full_crossbar i_dut (
    .clk_i           ( clk            ),
    .rst_i           ( rst            ),
    .test_i          ( 1'b0           ),

    .fpga_mst_req_i  ( fpga_mst_req   ),
    .fpga_mst_resp_o ( fpga_mst_resp  ),
    .dfetch_req_i    ( dfetch_req     ),
    .dfetch_resp_o   ( dfetch_resp    ),
    .mfetch_req_i    ( mfetch_req     ),
    .mfetch_resp_o   ( mfetch_resp    ),
    .bsfetch_req_i   ( bsfetch_req    ),
    .bsfetch_resp_o  ( bsfetch_resp   ),

    .fpga_mem_req_o  ( fpga_mem_req   ),
    .fpga_mem_resp_i ( fpga_mem_resp  ),
    .cgra_csr_req_o  ( cgra_csr_req   ),
    .cgra_csr_resp_i ( cgra_csr_resp  )
  );

  // =========================================================================
  // Behavioral slave – FPGA SRAM  (master port [0], 1024 × 16-bit)
  // Base 0x0800; word-addressed as (byte_addr - 0x0800) >> 1.
  // =========================================================================
  logic [15:0] sram [0:MEM_WORDS-1];

  initial begin
    for (int i = 0; i < MEM_WORDS; i++)
      sram[i] = 16'hA000 | (i & 16'hFFFF);
  end

  typedef enum logic [2:0] {
    MEM_IDLE, MEM_W_WAIT, MEM_B_RESP, MEM_R_BEAT
  } mem_st_t;
  mem_st_t mem_st;

  logic [MstIdWidth-1:0] mem_aw_id, mem_ar_id;
  logic [15:0]           mem_aw_addr, mem_ar_addr;
  logic [7:0]            mem_ar_len;
  logic [7:0]            mem_beat_cnt;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      mem_st        <= MEM_IDLE;
      fpga_mem_resp <= '0;
    end else begin
      // Default deassert
      fpga_mem_resp.aw_ready <= 1'b0;
      fpga_mem_resp.w_ready  <= 1'b0;
      fpga_mem_resp.b_valid  <= 1'b0;
      fpga_mem_resp.ar_ready <= 1'b0;
      fpga_mem_resp.r_valid  <= 1'b0;

      unique case (mem_st)

        MEM_IDLE: begin
          if (fpga_mem_req.aw_valid) begin
            // Latch AW; also accept W if already present
            fpga_mem_resp.aw_ready <= 1'b1;
            mem_aw_addr            <= fpga_mem_req.aw.addr;
            mem_aw_id              <= fpga_mem_req.aw.id;
            if (fpga_mem_req.w_valid) begin
              fpga_mem_resp.w_ready <= 1'b1;
              begin
                automatic int wa = int'((fpga_mem_req.aw.addr - MEM_BASE) >> 1);
                if (wa >= 0 && wa < MEM_WORDS) begin
                  if (fpga_mem_req.w.strb[0]) sram[wa][ 7:0] <= fpga_mem_req.w.data[ 7:0];
                  if (fpga_mem_req.w.strb[1]) sram[wa][15:8] <= fpga_mem_req.w.data[15:8];
                end
              end
              mem_st <= MEM_B_RESP;
            end else begin
              mem_st <= MEM_W_WAIT;
            end
          end else if (fpga_mem_req.ar_valid) begin
            fpga_mem_resp.ar_ready <= 1'b1;
            mem_ar_addr            <= fpga_mem_req.ar.addr;
            mem_ar_id              <= fpga_mem_req.ar.id;
            mem_ar_len             <= fpga_mem_req.ar.len;
            mem_beat_cnt           <= '0;
            mem_st                 <= MEM_R_BEAT;
          end
        end

        MEM_W_WAIT: begin
          fpga_mem_resp.w_ready <= 1'b1;
          if (fpga_mem_req.w_valid) begin
            automatic int wa = int'((mem_aw_addr - MEM_BASE) >> 1);
            if (wa >= 0 && wa < MEM_WORDS) begin
              if (fpga_mem_req.w.strb[0]) sram[wa][ 7:0] <= fpga_mem_req.w.data[ 7:0];
              if (fpga_mem_req.w.strb[1]) sram[wa][15:8] <= fpga_mem_req.w.data[15:8];
            end
            mem_st <= MEM_B_RESP;
          end
        end

        MEM_B_RESP: begin
          fpga_mem_resp.b_valid <= 1'b1;
          fpga_mem_resp.b.id    <= mem_aw_id;
          fpga_mem_resp.b.resp  <= RESP_OKAY;
          fpga_mem_resp.b.user  <= '0;
          if (fpga_mem_req.b_ready)
            mem_st <= MEM_IDLE;
        end

        MEM_R_BEAT: begin
          fpga_mem_resp.r_valid <= 1'b1;
          begin
            automatic int ra = int'((mem_ar_addr - MEM_BASE) >> 1) + int'(mem_beat_cnt);
            fpga_mem_resp.r.data <= (ra >= 0 && ra < MEM_WORDS) ? sram[ra] : 16'hDEAD;
          end
          fpga_mem_resp.r.id   <= mem_ar_id;
          fpga_mem_resp.r.resp <= RESP_OKAY;
          fpga_mem_resp.r.user <= '0;
          fpga_mem_resp.r.last <= (mem_beat_cnt == mem_ar_len);
          if (fpga_mem_req.r_ready) begin
            if (mem_beat_cnt == mem_ar_len)
              mem_st <= MEM_IDLE;
            else
              mem_beat_cnt <= mem_beat_cnt + 1;
          end
        end

        default: mem_st <= MEM_IDLE;
      endcase
    end
  end


  // =========================================================================
  // Behavioral slave – CGRA CSR bank  (master port [1], 8 × 16-bit)
  // =========================================================================
  logic [15:0] csr_regs [0:CSR_NUM_REG-1];
  initial foreach (csr_regs[i]) csr_regs[i] = '0;

  typedef enum logic [1:0] {
    CSR_IDLE, CSR_W_WAIT, CSR_B_RESP, CSR_R_RESP
  } csr_st_t;
  csr_st_t csr_st;

  logic [MstIdWidth-1:0] csr_aw_id, csr_ar_id;
  logic [15:0]           csr_aw_addr, csr_ar_addr;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      csr_st        <= CSR_IDLE;
      cgra_csr_resp <= '0;
    end else begin
      cgra_csr_resp.aw_ready <= 1'b0;
      cgra_csr_resp.w_ready  <= 1'b0;
      cgra_csr_resp.b_valid  <= 1'b0;
      cgra_csr_resp.ar_ready <= 1'b0;
      cgra_csr_resp.r_valid  <= 1'b0;

      unique case (csr_st)

        CSR_IDLE: begin
          if (cgra_csr_req.aw_valid) begin
            cgra_csr_resp.aw_ready <= 1'b1;
            csr_aw_addr            <= cgra_csr_req.aw.addr;
            csr_aw_id              <= cgra_csr_req.aw.id;
            if (cgra_csr_req.w_valid) begin
              cgra_csr_resp.w_ready <= 1'b1;
              begin
                automatic int ci = int'((cgra_csr_req.aw.addr - CSR_BASE_A) >> 1);
                if (ci >= 0 && ci < CSR_NUM_REG) begin
                  if (cgra_csr_req.w.strb[0]) csr_regs[ci][ 7:0] <= cgra_csr_req.w.data[ 7:0];
                  if (cgra_csr_req.w.strb[1]) csr_regs[ci][15:8] <= cgra_csr_req.w.data[15:8];
                end
              end
              csr_st <= CSR_B_RESP;
            end else begin
              csr_st <= CSR_W_WAIT;
            end
          end else if (cgra_csr_req.ar_valid) begin
            cgra_csr_resp.ar_ready <= 1'b1;
            csr_ar_addr            <= cgra_csr_req.ar.addr;
            csr_ar_id              <= cgra_csr_req.ar.id;
            csr_st                 <= CSR_R_RESP;
          end
        end

        CSR_W_WAIT: begin
          cgra_csr_resp.w_ready <= 1'b1;
          if (cgra_csr_req.w_valid) begin
            automatic int ci = int'((csr_aw_addr - CSR_BASE_A) >> 1);
            if (ci >= 0 && ci < CSR_NUM_REG) begin
              if (cgra_csr_req.w.strb[0]) csr_regs[ci][ 7:0] <= cgra_csr_req.w.data[ 7:0];
              if (cgra_csr_req.w.strb[1]) csr_regs[ci][15:8] <= cgra_csr_req.w.data[15:8];
            end
            csr_st <= CSR_B_RESP;
          end
        end

        CSR_B_RESP: begin
          cgra_csr_resp.b_valid <= 1'b1;
          cgra_csr_resp.b.id    <= csr_aw_id;
          cgra_csr_resp.b.resp  <= RESP_OKAY;
          cgra_csr_resp.b.user  <= '0;
          if (cgra_csr_req.b_ready)
            csr_st <= CSR_IDLE;
        end

        CSR_R_RESP: begin
          cgra_csr_resp.r_valid <= 1'b1;
          begin
            automatic int ci = int'((csr_ar_addr - CSR_BASE_A) >> 1);
            cgra_csr_resp.r.data <= (ci >= 0 && ci < CSR_NUM_REG) ?
                                    csr_regs[ci] : 16'hDEAD;
          end
          cgra_csr_resp.r.id   <= csr_ar_id;
          cgra_csr_resp.r.resp <= RESP_OKAY;
          cgra_csr_resp.r.user <= '0;
          cgra_csr_resp.r.last <= 1'b1;
          if (cgra_csr_req.r_ready)
            csr_st <= CSR_IDLE;
        end

        default: csr_st <= CSR_IDLE;
      endcase
    end
  end


  // =========================================================================
  // AXI4 Master BFM tasks
  // =========================================================================

  // Single-beat write: drive AW+W simultaneously, collect B response.
  task automatic axi4_write (
    ref  slv_req_t                req,
    ref  slv_resp_t               resp,
    input logic [SlvIdWidth-1:0]   id,
    input logic [AxiAddrWidth-1:0] addr,
    input logic [AxiDataWidth-1:0] data,
    input logic [AxiStrbWidth-1:0] strb,
    output logic [1:0]             bresp
  );
    req           = '0;
    req.aw.id     = id;
    req.aw.addr   = addr;
    req.aw.len    = 8'h00;
    req.aw.size   = 3'b001;   // 2-byte beats
    req.aw.burst  = BURST_INCR;
    req.aw_valid  = 1'b1;
    req.w.data    = data;
    req.w.strb    = strb;
    req.w.last    = 1'b1;
    req.w_valid   = 1'b1;
    req.b_ready   = 1'b1;

    @(posedge clk);
    while (!(resp.aw_ready && resp.w_ready)) @(posedge clk);
    req.aw_valid = 1'b0;
    req.w_valid  = 1'b0;

    while (!resp.b_valid) @(posedge clk);
    bresp       = resp.b.resp;
    req.b_ready = 1'b0;
    @(posedge clk);
  endtask

  // Single-beat read.
  task automatic axi4_read (
    ref  slv_req_t                req,
    ref  slv_resp_t               resp,
    input logic [SlvIdWidth-1:0]   id,
    input logic [AxiAddrWidth-1:0] addr,
    output logic [AxiDataWidth-1:0] rdata,
    output logic [1:0]              rresp
  );
    req           = '0;
    req.ar.id     = id;
    req.ar.addr   = addr;
    req.ar.len    = 8'h00;
    req.ar.size   = 3'b001;
    req.ar.burst  = BURST_INCR;
    req.ar_valid  = 1'b1;
    req.r_ready   = 1'b1;

    @(posedge clk);
    while (!resp.ar_ready) @(posedge clk);
    req.ar_valid = 1'b0;

    while (!resp.r_valid) @(posedge clk);
    rdata       = resp.r.data;
    rresp       = resp.r.resp;
    req.r_ready = 1'b0;
    @(posedge clk);
  endtask

  // INCR burst read; len_beats is the number of beats (AXI len = len_beats-1).
  task automatic axi4_burst_read (
    ref  slv_req_t                req,
    ref  slv_resp_t               resp,
    input logic [SlvIdWidth-1:0]   id,
    input logic [AxiAddrWidth-1:0] addr,
    input int unsigned             len_beats,
    output logic [AxiDataWidth-1:0] rdata [],
    output logic [1:0]              rresp
  );
    rdata         = new[len_beats];
    req           = '0;
    req.ar.id     = id;
    req.ar.addr   = addr;
    req.ar.len    = 8'(len_beats - 1);
    req.ar.size   = 3'b001;
    req.ar.burst  = BURST_INCR;
    req.ar_valid  = 1'b1;
    req.r_ready   = 1'b1;

    @(posedge clk);
    while (!resp.ar_ready) @(posedge clk);
    req.ar_valid = 1'b0;

    for (int b = 0; b < int'(len_beats); b++) begin
      while (!resp.r_valid) @(posedge clk);
      rdata[b] = resp.r.data;
      rresp    = resp.r.resp;
      @(posedge clk);
    end
    req.r_ready = 1'b0;
    @(posedge clk);
  endtask


  // =========================================================================
  // Checker helper
  // =========================================================================
  int pass_cnt, fail_cnt;

  task check (input string name, input logic cond);
    if (cond) begin
      $display("  PASS  %s", name);
      pass_cnt++;
    end else begin
      $display("  FAIL  %s  *** MISMATCH ***", name);
      fail_cnt++;
    end
  endtask


  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    pass_cnt      = 0;
    fail_cnt      = 0;
    fpga_mst_req  = '0;
    dfetch_req    = '0;
    mfetch_req    = '0;
    bsfetch_req   = '0;

    // Reset
    rst = 1;
    repeat(4) @(posedge clk);
    rst = 0;
    repeat(4) @(posedge clk);

    $display("\n===== axi4_full_crossbar testbench =====\n");

    // -----------------------------------------------------------------------
    // T1: FPGA master writes 8 CSR registers
    // -----------------------------------------------------------------------
    $display("--- T1: FPGA master writes CSR registers ---");
    begin
      logic [1:0] bresp;
      for (int i = 0; i < CSR_NUM_REG; i++) begin
        axi4_write(fpga_mst_req, fpga_mst_resp,
                   4'(i), 16'(CSR_BASE_A + i*2), 16'(16'hC000 | i), 2'b11,
                   bresp);
        check($sformatf("T1 CSR[%0d] write OKAY", i), bresp == RESP_OKAY);
      end
    end

    // -----------------------------------------------------------------------
    // T2: FPGA master reads back CSR registers
    // -----------------------------------------------------------------------
    $display("--- T2: FPGA master reads CSR registers ---");
    begin
      logic [15:0] rdata;
      logic [1:0]  rresp;
      for (int i = 0; i < CSR_NUM_REG; i++) begin
        axi4_read(fpga_mst_req, fpga_mst_resp,
                  4'(i), 16'(CSR_BASE_A + i*2), rdata, rresp);
        check($sformatf("T2 CSR[%0d] read OKAY",    i), rresp == RESP_OKAY);
        check($sformatf("T2 CSR[%0d] data correct", i), rdata == 16'(16'hC000 | i));
      end
    end

    // -----------------------------------------------------------------------
    // T3: dfetch single-beat reads from FPGA SRAM (words 0–7)
    // -----------------------------------------------------------------------
    $display("--- T3: dfetch single reads from FPGA SRAM ---");
    begin
      logic [15:0] rdata;
      logic [1:0]  rresp;
      for (int i = 0; i < 8; i++) begin
        axi4_read(dfetch_req, dfetch_resp,
                  4'(i), 16'(MEM_BASE + i*2), rdata, rresp);
        check($sformatf("T3 SRAM[%0d] OKAY",    i), rresp == RESP_OKAY);
        check($sformatf("T3 SRAM[%0d] correct", i), rdata == 16'(16'hA000 | i));
      end
    end

    // -----------------------------------------------------------------------
    // T4: mfetch single reads (words 16–23)
    // -----------------------------------------------------------------------
    $display("--- T4: mfetch single reads from FPGA SRAM ---");
    begin
      logic [15:0] rdata;
      logic [1:0]  rresp;
      for (int i = 16; i < 24; i++) begin
        axi4_read(mfetch_req, mfetch_resp,
                  4'(i[3:0]), 16'(MEM_BASE + i*2), rdata, rresp);
        check($sformatf("T4 SRAM[%0d] OKAY",    i), rresp == RESP_OKAY);
        check($sformatf("T4 SRAM[%0d] correct", i), rdata == 16'(16'hA000 | i[15:0]));
      end
    end

    // -----------------------------------------------------------------------
    // T5: bsfetch single reads (words 32–39)
    // -----------------------------------------------------------------------
    $display("--- T5: bsfetch single reads from FPGA SRAM ---");
    begin
      logic [15:0] rdata;
      logic [1:0]  rresp;
      for (int i = 32; i < 40; i++) begin
        axi4_read(bsfetch_req, bsfetch_resp,
                  4'(i[3:0]), 16'(MEM_BASE + i*2), rdata, rresp);
        check($sformatf("T5 SRAM[%0d] OKAY",    i), rresp == RESP_OKAY);
        check($sformatf("T5 SRAM[%0d] correct", i), rdata == 16'(16'hA000 | i[15:0]));
      end
    end

    // -----------------------------------------------------------------------
    // T6: dfetch burst read – 4 beats starting at word 64
    // -----------------------------------------------------------------------
    $display("--- T6: dfetch burst read (4 beats) ---");
    begin
      logic [15:0] rdata [];
      logic [1:0]  rresp;
      int base_w = 64;
      axi4_burst_read(dfetch_req, dfetch_resp,
                      4'h2, 16'(MEM_BASE + base_w*2), 4, rdata, rresp);
      check("T6 burst OKAY", rresp == RESP_OKAY);
      for (int i = 0; i < 4; i++)
        check($sformatf("T6 beat[%0d]", i),
              rdata[i] == 16'(16'hA000 | (base_w + i)));
    end

    // -----------------------------------------------------------------------
    // T7: bsfetch burst read – 8 beats starting at word 128
    // -----------------------------------------------------------------------
    $display("--- T7: bsfetch burst read (8 beats) ---");
    begin
      logic [15:0] rdata [];
      logic [1:0]  rresp;
      int base_w = 128;
      axi4_burst_read(bsfetch_req, bsfetch_resp,
                      4'h3, 16'(MEM_BASE + base_w*2), 8, rdata, rresp);
      check("T7 burst OKAY", rresp == RESP_OKAY);
      for (int i = 0; i < 8; i++)
        check($sformatf("T7 beat[%0d]", i),
              rdata[i] == 16'(16'hA000 | (base_w + i)));
    end

    // -----------------------------------------------------------------------
    // T8: Concurrent – fpga_mst writes CSR while dfetch reads SRAM
    // -----------------------------------------------------------------------
    $display("--- T8: Concurrent CSR write + SRAM read ---");
    begin
      logic [1:0]  fpga_bresp, dfetch_rresp;
      logic [15:0] dfetch_rdata;
      fork
        axi4_write(fpga_mst_req, fpga_mst_resp,
                   4'h0, 16'h0000, 16'hBEEF, 2'b11, fpga_bresp);
        axi4_read (dfetch_req, dfetch_resp,
                   4'h5, 16'(MEM_BASE + 5*2), dfetch_rdata, dfetch_rresp);
      join
      check("T8 CSR write OKAY",  fpga_bresp   == RESP_OKAY);
      check("T8 SRAM read OKAY",  dfetch_rresp == RESP_OKAY);
      check("T8 SRAM data match", dfetch_rdata == 16'(16'hA000 | 5));
      // Verify CSR[0] took the new value
      begin
        logic [15:0] rd; logic [1:0] rr;
        axi4_read(fpga_mst_req, fpga_mst_resp, 4'h0, 16'h0000, rd, rr);
        check("T8 CSR[0] updated", rd == 16'hBEEF);
      end
    end

    // -----------------------------------------------------------------------
    // T9: FPGA master writes SRAM, dfetch reads back (loopback)
    // -----------------------------------------------------------------------
    $display("--- T9: FPGA master SRAM write, dfetch readback ---");
    begin
      logic [1:0]  bresp, rresp;
      logic [15:0] rdata;
      axi4_write(fpga_mst_req, fpga_mst_resp,
                 4'h4, 16'(MEM_BASE + 200*2), 16'h1234, 2'b11, bresp);
      check("T9 write OKAY", bresp == RESP_OKAY);
      axi4_read(dfetch_req, dfetch_resp,
                4'h4, 16'(MEM_BASE + 200*2), rdata, rresp);
      check("T9 readback OKAY",    rresp == RESP_OKAY);
      check("T9 loopback correct", rdata == 16'h1234);
    end

    // -----------------------------------------------------------------------
    // T10: Out-of-range address → DECERR
    // -----------------------------------------------------------------------
    $display("--- T10: Out-of-range address → DECERR ---");
    begin
      logic [15:0] rdata;
      logic [1:0]  rresp;
      axi4_read(fpga_mst_req, fpga_mst_resp,
                4'hF, 16'hF000, rdata, rresp);
      check("T10 DECERR returned", rresp == RESP_DECERR);
    end

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    repeat(4) @(posedge clk);
    $display("\n===== Results: %0d PASS  %0d FAIL =====\n", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("ALL TESTS PASSED");
    else               $display("SOME TESTS FAILED – check FAIL lines above");
    $finish;
  end

  // Watchdog
  initial begin
    #(CLK_PERIOD_NS * 200000);
    $display("ERROR: watchdog timeout");
    $finish;
  end

endmodule : tb_axi4_full_crossbar
