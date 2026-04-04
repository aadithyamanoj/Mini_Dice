`timescale 1ns / 1ps

module tb_dice_frontend_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int ClkPeriod      = 10;
  localparam int TimeoutCycles  = 800;
  localparam int MetaBeats      = DICE_METADATA_WIDTH / 16;
  localparam int NumChunks      = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                  / DICE_MEM_DATA_WIDTH;
  localparam int BitstreamBeats = DICE_BITSTREAM_SIZE / 16;

  localparam logic [DICE_ADDR_WIDTH-1:0] StartPc             = 16'h0100;
  localparam logic [DICE_ADDR_WIDTH-1:0] FirstBitstreamAddr  = 16'h0400;
  localparam logic [DICE_ADDR_WIDTH-1:0] SecondBitstreamAddr = 16'h0500;

  // =========================================================================
  // Signals & Interfaces
  // =========================================================================
  logic clk;
  logic rst;
  int   cycle_count;

  cta_if cta_if_inst ();
  slv_req_t mfetch_req;
  slv_resp_t mfetch_resp;
  slv_req_t bsfetch_req;
  slv_resp_t bsfetch_resp;

  fdr_if     fdr_if_inst ();
  cgra_cm_if cm0_if ();
  cgra_cm_if cm1_if ();

  logic                       eblock_commit_valid_i;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i;
  logic                       meta_rsp_active_q;
  logic [$clog2(MetaBeats+1)-1:0] meta_rsp_idx_q;
  logic [DICE_METADATA_WIDTH-1:0] meta_rsp_payload_q;
  logic [$bits(mfetch_req.ar.id)-1:0] meta_rsp_id_q;

  logic                       bitstream_rsp_active_q;
  logic [$clog2(BitstreamBeats+1)-1:0] bitstream_rsp_idx_q;
  logic [DICE_ADDR_WIDTH-1:0] bitstream_base_addr_q;
  logic [$bits(bsfetch_req.ar.id)-1:0] bitstream_rsp_id_q;

  // =========================================================================
  // Helper Functions — metadata & bitstream generation
  // =========================================================================
  function automatic pgraph_meta_t metadata_for_pc(
      input logic [DICE_ADDR_WIDTH-1:0] pc
  );
    pgraph_meta_t meta;
    logic [DICE_ADDR_WIDTH-1:0] second_pc;

    second_pc = StartPc + DICE_METADATA_WIDTH;
    meta = '0;
    meta.bitstream_length = BITSTREAM_LENGTH_WIDTH'(NumChunks);
    meta.lat              = 8'd3;

    unique case (pc)
      StartPc: begin
        meta.bitstream_addr       = FirstBitstreamAddr;
        meta.in_regs_bitmap[0]    = 1'b1;
        meta.out_regs_bitmap[1]   = 1'b1;
      end
      second_pc: begin
        meta.bitstream_addr       = SecondBitstreamAddr;
        meta.in_regs_bitmap[2]    = 1'b1;
        meta.out_regs_bitmap[3]   = 1'b1;
        meta.branch_meta.is_return = 1'b1;
      end
      default: begin
        meta.bitstream_addr = FirstBitstreamAddr;
      end
    endcase

    return meta;
  endfunction

  function automatic logic [15:0] bitstream_beat_for_addr(
      input logic [DICE_ADDR_WIDTH-1:0] byte_addr
  );
    return byte_addr[15:0] ^ 16'hCAFE;
  endfunction

  // =========================================================================
  // DUT
  // =========================================================================
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
      .eblock_commit_valid_i (eblock_commit_valid_i),
      .eblock_commit_id_i    (eblock_commit_id_i)
  );

  // =========================================================================
  // Clock & Timeout
  // =========================================================================
  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $error("TIMEOUT");
        $finish;
      end
    end
  end

  // =========================================================================
  // AXI Read Response Models
  // =========================================================================

  always_comb begin
    mfetch_resp = '0;
    mfetch_resp.ar_ready = !meta_rsp_active_q;
    if (meta_rsp_active_q) begin
      mfetch_resp.r_valid = 1'b1;
      mfetch_resp.r.id    = meta_rsp_id_q;
      mfetch_resp.r.data  = meta_rsp_payload_q[meta_rsp_idx_q*16 +: 16];
      mfetch_resp.r.last  = (meta_rsp_idx_q == MetaBeats - 1);
    end
  end

  always_comb begin
    bsfetch_resp = '0;
    bsfetch_resp.ar_ready = !bitstream_rsp_active_q;
    if (bitstream_rsp_active_q) begin
      bsfetch_resp.r_valid = 1'b1;
      bsfetch_resp.r.id    = bitstream_rsp_id_q;
      bsfetch_resp.r.data  = bitstream_beat_for_addr(
          bitstream_base_addr_q + DICE_ADDR_WIDTH'(bitstream_rsp_idx_q << 1)
      );
      bsfetch_resp.r.last  = (bitstream_rsp_idx_q == BitstreamBeats - 1);
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      meta_rsp_active_q      <= 1'b0;
      meta_rsp_idx_q         <= '0;
      meta_rsp_payload_q     <= '0;
      meta_rsp_id_q          <= '0;
      bitstream_rsp_active_q <= 1'b0;
      bitstream_rsp_idx_q    <= '0;
      bitstream_base_addr_q  <= '0;
      bitstream_rsp_id_q     <= '0;
    end else begin
      if (!meta_rsp_active_q && mfetch_req.ar_valid && mfetch_resp.ar_ready) begin
        meta_rsp_active_q  <= 1'b1;
        meta_rsp_idx_q     <= '0;
        meta_rsp_payload_q <= DICE_METADATA_WIDTH'(metadata_for_pc(mfetch_req.ar.addr));
        meta_rsp_id_q      <= mfetch_req.ar.id;
      end else if (meta_rsp_active_q && mfetch_resp.r_valid && mfetch_req.r_ready) begin
        if (mfetch_resp.r.last) begin
          meta_rsp_active_q <= 1'b0;
        end else begin
          meta_rsp_idx_q <= meta_rsp_idx_q + 1'b1;
        end
      end

      if (!bitstream_rsp_active_q && bsfetch_req.ar_valid && bsfetch_resp.ar_ready) begin
        bitstream_rsp_active_q <= 1'b1;
        bitstream_rsp_idx_q    <= '0;
        bitstream_base_addr_q  <= bsfetch_req.ar.addr;
        bitstream_rsp_id_q     <= bsfetch_req.ar.id;
      end else if (bitstream_rsp_active_q && bsfetch_resp.r_valid && bsfetch_req.r_ready) begin
        if (bsfetch_resp.r.last) begin
          bitstream_rsp_active_q <= 1'b0;
        end else begin
          bitstream_rsp_idx_q <= bitstream_rsp_idx_q + 1'b1;
        end
      end
    end
  end

  // =========================================================================
  // Helper Tasks
  // =========================================================================

  // Initializes all DUT inputs to safe defaults
  task automatic init_inputs();
    cta_if_inst.dispatch_valid  = 1'b0;
    cta_if_inst.dispatch_data   = '0;
    cta_if_inst.complete_ready  = 1'b1;

    fdr_if_inst.ready           = 1'b1;

    eblock_commit_valid_i       = 1'b0;
    eblock_commit_id_i          = '0;
  endtask

  // Resets the DUT
  task automatic reset_dut();
    rst = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  // Builds a simple 1x1x1 CTA descriptor with the given start PC
  task automatic make_cta_desc(
    input  logic [DICE_ADDR_WIDTH-1:0] start_pc,
    output dice_cta_desc_t             desc
  );
    desc = '0;
    desc.kernel_desc.grid_size.x = 1;
    desc.kernel_desc.grid_size.y = 1;
    desc.kernel_desc.grid_size.z = 1;
    desc.kernel_desc.thread_count = 1;
    desc.kernel_desc.start_pc    = start_pc;
    desc.cta_id                  = '0;
  endtask

  // Dispatches a CTA — waits for ready, then asserts valid for one full cycle
  task automatic dispatch_cta(input dice_cta_desc_t desc);
    cta_if_inst.dispatch_valid = 1'b1;
    cta_if_inst.dispatch_data  = desc;

    do begin
      @(posedge clk);
    end while (!cta_if_inst.dispatch_ready);

    cta_if_inst.dispatch_valid = 1'b0;
  endtask

  // Commits an eblock execution result
  task automatic commit_eblock(input logic [EBLOCK_ID_WIDTH-1:0] eblock_id);
    eblock_commit_id_i    = eblock_id;
    eblock_commit_valid_i = 1'b1;
    @(posedge clk);
    eblock_commit_valid_i = 1'b0;
    eblock_commit_id_i    = '0;
  endtask

  // Waits for a CTA completion handshake
  task automatic wait_cta_complete();
    do begin
      @(posedge clk);
    end while (!(cta_if_inst.complete_valid && cta_if_inst.complete_ready));
    $display("[%0t] CTA complete id=(%0d,%0d,%0d)", $time,
             cta_if_inst.complete_cta_id.x,
             cta_if_inst.complete_cta_id.y,
             cta_if_inst.complete_cta_id.z);
  endtask

  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    dice_cta_desc_t desc;

    $display("tb_dice_frontend_top");

    init_inputs();
    reset_dut();

    make_cta_desc(StartPc, desc);
    dispatch_cta(desc);

    repeat (200) @(posedge clk);

    $display("TB Done");
    $finish;
  end

`ifdef FSDB
  initial begin
    $fsdbDumpfile("tb_dice_frontend_top.fsdb");
    $fsdbDumpvars(0, tb_dice_frontend_top, "+struct", "+mda");
  end
`endif

endmodule
