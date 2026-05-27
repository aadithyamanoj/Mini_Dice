`timescale 1ns / 1ps

module tb_dice_frontend;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;

  localparam int ClkPeriod     = 10;
  localparam int TimeoutCycles = 5_000_000;

  // =========================================================================
  // Clock / reset
  // =========================================================================
  logic clk_i;
  logic rst_i;

  initial clk_i = 1'b0;
  always  #(ClkPeriod / 2) clk_i = ~clk_i;

  int cycle_count;
  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles)
        $fatal(1, "[TB] TIMEOUT at cycle %0d", cycle_count);
    end
  end

  // =========================================================================
  // Interfaces
  // =========================================================================
  cta_if cta_if_inst ();
  fdr_if fdr_if_inst ();

  // =========================================================================
  // AXI4 memory ports
  // =========================================================================
  slv_req_t  mfetch_req,  bsfetch_req;
  slv_resp_t mfetch_resp, bsfetch_resp;

  // =========================================================================
  // DUT output monitors (config-memory write port)
  // =========================================================================
  logic                                   cm_wr_buffer;
  logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr;
  logic [AxiDataWidth-1:0]                cm_wr_data;
  logic                                   cm_wr_valid;
  logic [SIMT_STACK_ENTRY_COUNT_WIDTH-1:0] simt_stack_entry_count;

  // =========================================================================
  // Backend feedback (held inactive for basic dispatch test)
  // =========================================================================
  logic                       eblock_commit_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id;
  block_retire_status_t       brt_info;
  logic                       brt_info_write_enable;
  logic [`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE-1:0] pred_regs;

  // =========================================================================
  // DUT
  // =========================================================================
  dice_frontend u_dut (
    .clk_i                   (clk_i),
    .rst_i                   (rst_i),
    .cta_if_inst             (cta_if_inst),
    .mfetch_req_o            (mfetch_req),
    .mfetch_resp_i           (mfetch_resp),
    .bsfetch_req_o           (bsfetch_req),
    .bsfetch_resp_i          (bsfetch_resp),
    .fdr_if_o                (fdr_if_inst),
    .cm_wr_buffer_o          (cm_wr_buffer),
    .cm_wr_addr_o            (cm_wr_addr),
    .cm_wr_data_o            (cm_wr_data),
    .cm_wr_valid_o           (cm_wr_valid),
    .pred_regs_i             (pred_regs),
    .prog_active_i           (1'b0),
    .prog_active_buffer_i    (1'b0),
    .disable_ucd_prefetch_sched_i(1'b0),
    .eblock_commit_valid_i   (eblock_commit_valid),
    .eblock_commit_id_i      (eblock_commit_id),
    .brt_info_i              (brt_info),
    .brt_info_write_enable_i (brt_info_write_enable),
    .stack_overflow_o        (),
    .stack_depth_o           (),
    .stack_error_pc_o        (),
    .simt_stack_entry_count_o(simt_stack_entry_count)
  );

  // =========================================================================
  // AXI read-slave stubs
  //   One-outstanding-transaction model: accepts AR, returns (len+1) beats of
  //   zero data, then goes idle.  Write channels are tied off (not used by FE).
  // =========================================================================
  typedef enum logic { AXI_IDLE, AXI_SEND } axi_state_t;

  // ── mfetch stub ──────────────────────────────────────────────────────────
  axi_state_t  mfetch_st;
  logic [7:0]  mfetch_beats;
  slv_id_t     mfetch_rid;

  assign mfetch_resp.aw_ready = 1'b0;
  assign mfetch_resp.w_ready  = 1'b0;
  assign mfetch_resp.b_valid  = 1'b0;
  assign mfetch_resp.b        = '0;
  assign mfetch_resp.ar_ready = (mfetch_st == AXI_IDLE);
  assign mfetch_resp.r_valid  = (mfetch_st == AXI_SEND);
  assign mfetch_resp.r.data   = '0;
  assign mfetch_resp.r.resp   = 2'b00;
  assign mfetch_resp.r.last   = (mfetch_beats == 8'h0);
  assign mfetch_resp.r.id     = mfetch_rid;
  assign mfetch_resp.r.user   = '0;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      mfetch_st    <= AXI_IDLE;
      mfetch_beats <= '0;
      mfetch_rid   <= '0;
    end else unique case (mfetch_st)
      AXI_IDLE: if (mfetch_req.ar_valid) begin
        mfetch_st    <= AXI_SEND;
        mfetch_beats <= mfetch_req.ar.len;
        mfetch_rid   <= mfetch_req.ar.id;
      end
      AXI_SEND: if (mfetch_req.r_ready) begin
        if (mfetch_beats == 8'h0) mfetch_st    <= AXI_IDLE;
        else                       mfetch_beats <= mfetch_beats - 1;
      end
    endcase
  end

  // ── bsfetch stub (identical pattern) ─────────────────────────────────────
  axi_state_t  bsfetch_st;
  logic [7:0]  bsfetch_beats;
  slv_id_t     bsfetch_rid;

  assign bsfetch_resp.aw_ready = 1'b0;
  assign bsfetch_resp.w_ready  = 1'b0;
  assign bsfetch_resp.b_valid  = 1'b0;
  assign bsfetch_resp.b        = '0;
  assign bsfetch_resp.ar_ready = (bsfetch_st == AXI_IDLE);
  assign bsfetch_resp.r_valid  = (bsfetch_st == AXI_SEND);
  assign bsfetch_resp.r.data   = '0;
  assign bsfetch_resp.r.resp   = 2'b00;
  assign bsfetch_resp.r.last   = (bsfetch_beats == 8'h0);
  assign bsfetch_resp.r.id     = bsfetch_rid;
  assign bsfetch_resp.r.user   = '0;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      bsfetch_st    <= AXI_IDLE;
      bsfetch_beats <= '0;
      bsfetch_rid   <= '0;
    end else unique case (bsfetch_st)
      AXI_IDLE: if (bsfetch_req.ar_valid) begin
        bsfetch_st    <= AXI_SEND;
        bsfetch_beats <= bsfetch_req.ar.len;
        bsfetch_rid   <= bsfetch_req.ar.id;
      end
      AXI_SEND: if (bsfetch_req.r_ready) begin
        if (bsfetch_beats == 8'h0) bsfetch_st    <= AXI_IDLE;
        else                        bsfetch_beats <= bsfetch_beats - 1;
      end
    endcase
  end

  // FDR output: always ready (accept all e-blocks dispatched by frontend)
  assign fdr_if_inst.ready = 1'b1;

  // =========================================================================
  // Tasks
  // =========================================================================
  task automatic idle_inputs();
    cta_if_inst.dispatch_valid = 1'b0;
    cta_if_inst.dispatch_data  = '0;
    cta_if_inst.complete_ready = 1'b1;
    pred_regs                  = '0;
    eblock_commit_valid        = 1'b0;
    eblock_commit_id           = '0;
    brt_info                   = '0;
    brt_info_write_enable      = 1'b0;
  endtask

  task automatic reset_dut();
    rst_i = 1'b1;
    idle_inputs();
    repeat (10) @(posedge clk_i);
    rst_i = 1'b0;
    @(posedge clk_i);
  endtask

  // Mirrors tb_dice_core.sv dispatch_cta (lines 276-285)
  task automatic dispatch_cta(input dice_cta_desc_t desc);
    cta_if_inst.dispatch_valid = 1'b1;
    cta_if_inst.dispatch_data  = desc;
    do @(posedge clk_i); while (!cta_if_inst.dispatch_ready);
    cta_if_inst.dispatch_valid = 1'b0;
  endtask

  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    `ifdef FSDB
      $fsdbDumpfile("waveform.fsdb");
      $fsdbDumpvars(0, tb_dice_frontend, "+struct", "+mda");
    `endif

    reset_dut();

    // Dispatch one CTA with minimal descriptor
    begin
      dice_cta_desc_t desc;
      desc                         = '0;
      desc.kernel_desc.grid_size.x = 1;
      desc.kernel_desc.grid_size.y = 1;
      desc.kernel_desc.grid_size.z = 1;
      desc.kernel_desc.thread_count = `DICE_NUM_MAX_THREADS_PER_CORE;
      desc.kernel_desc.start_pc    = 32'h1000;
      dispatch_cta(desc);
    end

    $display("[TB] CTA accepted by frontend at cycle %0d", cycle_count);

    // Allow the fetch pipeline to run.
    // AXI stubs return all-zero data so the pipeline will proceed but produce
    // dummy results.  Extend this test with real metadata/bitstream memories
    // when end-to-end execution tracing is needed.
    repeat (500) @(posedge clk_i);
    $display("[TB] PASS");
    $finish;
  end

endmodule
