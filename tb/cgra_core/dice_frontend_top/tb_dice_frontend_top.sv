`timescale 1ns / 1ps

module tb_dice_frontend_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int ClkPeriod      = 10;
  localparam int TimeoutCycles  = 800;
  localparam int TagWidth       = DICE_ADDR_WIDTH;
  localparam int DataSizeBytes  = DICE_MEM_DATA_WIDTH / 8;
  localparam int BusAddrWidth   = DICE_MEM_ADDR_WIDTH - $clog2(DataSizeBytes);
  localparam int NumChunks      = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                  / DICE_MEM_DATA_WIDTH;
  localparam int AddrShift      = $clog2(DataSizeBytes);

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

  VX_mem_bus_if #(
      .DATA_SIZE(DataSizeBytes),
      .TAG_WIDTH(TagWidth)
  ) metacache_mem_if ();

  VX_mem_bus_if #(
      .DATA_SIZE(DataSizeBytes),
      .TAG_WIDTH(TagWidth)
  ) bitstream_cache_mem_if ();

  fdr_if     fdr_if_inst ();
  cgra_cm_if cm0_if ();
  cgra_cm_if cm1_if ();

  logic                       eblock_commit_valid_i;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i;
  block_retire_status_t       brt_info_i;
  logic                       brt_info_write_enable_i;

  // Memory response staging
  logic              meta_rsp_pending_q;
  logic [TagWidth-1:0] meta_rsp_tag_q;
  pgraph_meta_t      meta_rsp_payload_q;

  logic              bitstream_rsp_pending_q;
  logic [TagWidth-1:0] bitstream_rsp_tag_q;
  logic [DICE_MEM_DATA_WIDTH-1:0] bitstream_rsp_payload_q;

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

  function automatic logic [DICE_MEM_DATA_WIDTH-1:0] bitstream_word_for_addr(
      input logic [BusAddrWidth-1:0] word_addr
  );
    logic [DICE_MEM_DATA_WIDTH-1:0] data_word;

    data_word         = '0;
    data_word[31:0]   = {16'hCAFE, word_addr};
    data_word[63:32]  = {16'hD00D, word_addr};
    data_word[95:64]  = {16'hBEEF, word_addr};
    data_word[127:96] = {16'hFACE, word_addr};

    return data_word;
  endfunction

  // =========================================================================
  // DUT
  // =========================================================================
  dice_frontend_top u_dut (
      .clk_i                 (clk),
      .rst_i                 (rst),
      .cta_if_inst           (cta_if_inst),
      .metacache_mem_if      (metacache_mem_if),
      .bitstream_cache_mem_if(bitstream_cache_mem_if),
      .fdr_if_inst           (fdr_if_inst),
      .cm0_if                (cm0_if),
      .cm1_if                (cm1_if),
      .eblock_commit_valid_i (eblock_commit_valid_i),
      .eblock_commit_id_i    (eblock_commit_id_i),
      .brt_info_i            (brt_info_i),
      .brt_info_write_enable_i(brt_info_write_enable_i)
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
  // Memory Response Models
  // =========================================================================

  // Metacache: accept request, respond one cycle later
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      metacache_mem_if.req_ready <= 1'b1;
      metacache_mem_if.rsp_valid <= 1'b0;
      metacache_mem_if.rsp_data  <= '0;
      meta_rsp_pending_q         <= 1'b0;
      meta_rsp_tag_q             <= '0;
      meta_rsp_payload_q         <= '0;
    end else begin
      metacache_mem_if.req_ready <= 1'b1;
      metacache_mem_if.rsp_valid <= 1'b0;
      metacache_mem_if.rsp_data  <= '0;

      if (meta_rsp_pending_q) begin
        metacache_mem_if.rsp_valid           <= 1'b1;
        metacache_mem_if.rsp_data.tag.uuid   <= meta_rsp_tag_q;
        metacache_mem_if.rsp_data.data[$bits(pgraph_meta_t)-1:0] <= meta_rsp_payload_q;
        meta_rsp_pending_q                   <= 1'b0;
      end

      if (metacache_mem_if.req_valid && metacache_mem_if.req_ready) begin
        logic [DICE_ADDR_WIDTH-1:0] requested_pc;

        requested_pc     = DICE_ADDR_WIDTH'(metacache_mem_if.req_data.addr << AddrShift);
        meta_rsp_pending_q <= 1'b1;
        meta_rsp_tag_q     <= metacache_mem_if.req_data.tag.uuid;
        meta_rsp_payload_q <= metadata_for_pc(requested_pc);
      end
    end
  end

  // Bitstream cache: accept request, respond one cycle later
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      bitstream_cache_mem_if.req_ready <= 1'b1;
      bitstream_cache_mem_if.rsp_valid <= 1'b0;
      bitstream_cache_mem_if.rsp_data  <= '0;
      bitstream_rsp_pending_q          <= 1'b0;
      bitstream_rsp_tag_q              <= '0;
      bitstream_rsp_payload_q          <= '0;
    end else begin
      bitstream_cache_mem_if.req_ready <= 1'b1;
      bitstream_cache_mem_if.rsp_valid <= 1'b0;
      bitstream_cache_mem_if.rsp_data  <= '0;

      if (bitstream_rsp_pending_q) begin
        bitstream_cache_mem_if.rsp_valid         <= 1'b1;
        bitstream_cache_mem_if.rsp_data.tag.uuid <= bitstream_rsp_tag_q;
        bitstream_cache_mem_if.rsp_data.data     <= bitstream_rsp_payload_q;
        bitstream_rsp_pending_q                  <= 1'b0;
      end

      if (bitstream_cache_mem_if.req_valid && bitstream_cache_mem_if.req_ready) begin
        bitstream_rsp_pending_q <= 1'b1;
        bitstream_rsp_tag_q     <= bitstream_cache_mem_if.req_data.tag.uuid;
        bitstream_rsp_payload_q <= bitstream_word_for_addr(bitstream_cache_mem_if.req_data.addr);
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
    brt_info_i                  = '0;
    brt_info_write_enable_i     = 1'b0;
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
    desc.kernel_desc.cta_size.x  = 1;
    desc.kernel_desc.cta_size.y  = 1;
    desc.kernel_desc.cta_size.z  = 1;
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
