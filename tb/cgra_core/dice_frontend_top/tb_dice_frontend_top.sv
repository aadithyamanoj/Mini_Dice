module tb_dice_frontend_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;

  localparam int ClkPeriod     = 10;
  localparam int TimeoutCycles = 50;
  localparam int MetaBeats     = DICE_METADATA_WIDTH / 16;
  localparam int BitstreamBeats= DICE_BITSTREAM_SIZE / 16;
  localparam logic [DICE_ADDR_WIDTH-1:0] StartPc       = 16'h0100;
  localparam logic [DICE_ADDR_WIDTH-1:0] BitstreamAddr = 16'h0400;

  logic clk;
  logic rst;

  cta_if cta_if_inst ();
  slv_req_t  mfetch_req, bsfetch_req;
  slv_resp_t mfetch_resp, bsfetch_resp;
  fdr_if fdr_if_inst ();
  cgra_cm_if cm0_if (), cm1_if ();

  logic                            eblock_commit_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id;
  dice_cta_desc_t                  dispatch_desc;

  dice_frontend u_dut (
    .clk_i                 (clk),
    .rst_i                 (rst),
    .cta_if_inst           (cta_if_inst),
    .mfetch_req_o          (mfetch_req),
    .mfetch_resp_i         (mfetch_resp),
    .bsfetch_req_o         (bsfetch_req),
    .bsfetch_resp_i        (bsfetch_resp),
    .fdr_if_o              (fdr_if_inst),
    .cm0_if_o              (cm0_if),
    .cm1_if_o              (cm1_if),
    .eblock_commit_valid_i (eblock_commit_valid),
    .eblock_commit_id_i    (eblock_commit_id)
  );

  initial clk = 1'b0;

  always #(ClkPeriod/2) clk = ~clk;

  int cycle_count;

  initial cycle_count = 0;

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count >= TimeoutCycles) begin
      $display("[%0t] TIMEOUT after %0d cycles", $time, TimeoutCycles);
      $finish;
    end
  end

  // Keep the dispatch source static and permanently valid so the frontend
  // behaves as if software is always trying to add another CTA.
  always_comb begin
    dispatch_desc = '0;
    dispatch_desc.kernel_desc.grid_size.x  = 1;
    dispatch_desc.kernel_desc.grid_size.y  = 1;
    dispatch_desc.kernel_desc.grid_size.z  = 1;
    dispatch_desc.kernel_desc.thread_count = 5;
    dispatch_desc.kernel_desc.start_pc     = StartPc;
  end

  assign cta_if_inst.dispatch_data  = dispatch_desc;
  assign cta_if_inst.dispatch_valid = 1'b1;
  assign cta_if_inst.complete_ready = 1'b1;

  logic                          meta_busy;
  logic [$clog2(MetaBeats+1)-1:0] meta_beat_idx;
  logic [$bits(mfetch_req.ar.id)-1:0] meta_txn_id;
  pgraph_meta_t meta_payload;

  // Minimal metadata responder: accept one read request, then stream the
  // packed metadata payload one 16-bit beat at a time.
  always_comb begin
    meta_payload = '0;
    meta_payload.bitstream_addr = BitstreamAddr;
    meta_payload.bitstream_length = BITSTREAM_LENGTH_WIDTH'((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH);
    meta_payload.lat = 8'd1;
    meta_payload.in_regs_bitmap[0]  = 1'b1;
    meta_payload.out_regs_bitmap[1] = 1'b1;

    mfetch_resp = '0;
    mfetch_resp.ar_ready = !meta_busy;
    if (meta_busy) begin
      mfetch_resp.r_valid = 1'b1;
      mfetch_resp.r.id    = meta_txn_id;
      mfetch_resp.r.data  = DICE_METADATA_WIDTH'(meta_payload) >> (meta_beat_idx * 16);
      mfetch_resp.r.last  = (meta_beat_idx == MetaBeats - 1);
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      meta_busy <= 1'b0;
      meta_beat_idx <= '0;
    end else if (!meta_busy && mfetch_req.ar_valid) begin
      meta_busy <= 1'b1;
      meta_beat_idx <= '0;
      meta_txn_id <= mfetch_req.ar.id;
    end else if (meta_busy && mfetch_req.r_ready) begin
      if (mfetch_resp.r.last) meta_busy <= 1'b0;
      else meta_beat_idx <= meta_beat_idx + 1'b1;
    end
  end

  logic                               bs_busy;
  logic [$clog2(BitstreamBeats+1)-1:0] bs_beat_idx;
  logic [$bits(bsfetch_req.ar.id)-1:0] bs_txn_id;

  // Minimal bitstream responder: return the beat index as dummy payload data.
  always_comb begin
    bsfetch_resp = '0;
    bsfetch_resp.ar_ready = !bs_busy;
    if (bs_busy) begin
      bsfetch_resp.r_valid = 1'b1;
      bsfetch_resp.r.id    = bs_txn_id;
      bsfetch_resp.r.data  = 16'(bs_beat_idx);
      bsfetch_resp.r.last  = (bs_beat_idx == BitstreamBeats - 1);
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      bs_busy <= 1'b0;
      bs_beat_idx <= '0;
    end else if (!bs_busy && bsfetch_req.ar_valid) begin
      bs_busy <= 1'b1;
      bs_beat_idx <= '0;
      bs_txn_id <= bsfetch_req.ar.id;
    end else if (bs_busy && bsfetch_req.r_ready) begin
      if (bsfetch_resp.r.last) bs_busy <= 1'b0;
      else bs_beat_idx <= bs_beat_idx + 1'b1;
    end
  end

  assign fdr_if_inst.ready = 1'b1;

  // Immediately commit each scheduled eblock once the frontend emits it so
  // this bench does not need a separate backend model.
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      eblock_commit_valid <= 1'b0;
      eblock_commit_id    <= '0;
    end else begin
      eblock_commit_valid <= fdr_if_inst.valid && fdr_if_inst.ready;
      eblock_commit_id    <= fdr_if_inst.data.schedule_eblock_id;
    end
  end

  task reset_dut();
    rst = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task wait_cta_complete();
    forever begin
      @(posedge clk);
      if (cta_if_inst.complete_valid && cta_if_inst.complete_ready) break;
    end
  endtask

  initial begin
    // Reset once, then wait for the frontend to report CTA completion.
    reset_dut();

    wait_cta_complete();
    
    repeat (5) @(posedge clk);
    $finish;
  end

endmodule
