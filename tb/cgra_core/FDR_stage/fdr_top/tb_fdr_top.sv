// =============================================================================
// Testbench: tb_fdr_top.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "VX_define.vh"

module tb_fdr_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int TagWidth = 48;
  localparam int ChunkSize = VX_gpu_pkg::VX_MEM_DATA_WIDTH;
  localparam int NumChunks = (DICE_BITSTREAM_SIZE + ChunkSize - 1) / ChunkSize;
  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 5000;

  logic clk;
  logic rst;
  int cycle_count;

  VX_mem_bus_if #(
      .DATA_SIZE(ChunkSize / 8),
      .TAG_WIDTH(TagWidth)
  ) metacache_mem_if ();

  VX_mem_bus_if #(
      .DATA_SIZE(ChunkSize / 8),
      .TAG_WIDTH(TagWidth)
  ) bitstream_cache_mem_if ();

  cta_sched_if schedule_if ();
  fdr_if fdr_if ();
  simt_stack_status_entry_t simt_status;
  branch_predict_interface_t bh_branch_predict_info_o;
  logic                      bh_branch_predict_info_we_o;
  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] cta_status_data_i;
  logic                            simt_update_valid_o;
  logic                            simt_update_ready_i;
  simt_stack_update_t              simt_update_stack_data_o;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] simt_update_hw_cta_id_o;
  cta_size_e                       simt_update_hw_cta_size_o;
  cgra_cm_if cm0_if();
  cgra_cm_if cm1_if();

  // Eblock flush outputs
  logic                       eblock_flush_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id;

  fdr_top #(
      .TAG_WIDTH     (TagWidth),
      .BITSTREAM_SIZE(DICE_BITSTREAM_SIZE)
  ) u_dut (
      .clk_i                  (clk),
      .rst_i                  (rst),
      .metacache_mem_if       (metacache_mem_if),
      .bitstream_cache_mem_if (bitstream_cache_mem_if),
      .schedule_if            (schedule_if),
      .fdr_if                 (fdr_if),
      .simt_status_i          (simt_status),
      .bh_branch_predict_info_o(bh_branch_predict_info_o),
      .bh_branch_predict_info_we_o(bh_branch_predict_info_we_o),
      .cta_status_data_i      (cta_status_data_i),
      .simt_update_valid_o    (simt_update_valid_o),
      .simt_update_ready_i    (simt_update_ready_i),
      .simt_update_stack_data_o(simt_update_stack_data_o),
      .simt_update_hw_cta_id_o(simt_update_hw_cta_id_o),
      .simt_update_hw_cta_size_o(simt_update_hw_cta_size_o),
      .cm0_if                 (cm0_if),
      .cm1_if                 (cm1_if),
      .eblock_flush_valid_o   (eblock_flush_valid),
      .eblock_flush_id_o      (eblock_flush_id)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  task automatic reset_dut();
    rst = 1'b1;

    schedule_if.valid = 1'b0;
    schedule_if.data  = '0;

    fdr_if.ready = 1'b1;

    simt_status = '0;

    metacache_mem_if.req_ready = 1'b1;
    metacache_mem_if.rsp_valid = 1'b0;
    metacache_mem_if.rsp_data  = '0;

    bitstream_cache_mem_if.req_ready = 1'b1;
    bitstream_cache_mem_if.rsp_valid = 1'b0;
    bitstream_cache_mem_if.rsp_data  = '0;

    simt_update_ready_i = 1'b1;
    cta_status_data_i   = '0;

    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    schedule_eblock_t sched;
    pgraph_meta_t meta;
    logic [DICE_ADDR_WIDTH-1:0] start_pc;

    $display("tb_fdr_top (happy-path)");

    reset_dut();

    start_pc = 32'h0000_1000;

    sched = '0;
    sched.schedule_hw_cta_id        = '0;
    sched.schedule_next_pc          = start_pc;
    sched.schedule_eblock_id        = '0;
    sched.schedule_active_mask      = {DICE_NUM_MAX_THREADS_PER_CORE{1'b1}};
    sched.schedule_prefetch_block   = 1'b0;
    sched.schedule_cta_id           = '0;
    sched.schedule_grid_size.x      = 1;
    sched.schedule_grid_size.y      = 1;
    sched.schedule_grid_size.z      = 1;
    sched.schedule_cta_size.x       = 1;
    sched.schedule_cta_size.y       = 1;
    sched.schedule_cta_size.z       = 1;
    sched.schedule_kernel_id        = '0;
    sched.schedule_smem_per_cta     = '0;
    sched.schedule_hw_cta_size      = CTA_SIZE_1;
    sched.schedule_cta_thread_count = 1;

    simt_status.valid = 1'b1;
    simt_status.next_pc = start_pc;
    simt_status.active_mask = {DICE_NUM_MAX_THREADS_PER_CORE{1'b1}};
    simt_status.empty = 1'b0;
    simt_status.full = 1'b0;

    cta_status_data_i = '0;

    wait (schedule_if.ready == 1'b1);
    schedule_if.data  = sched;
    schedule_if.valid = 1'b1;
    @(posedge clk);
    schedule_if.valid = 1'b0;

    // Respond to meta fetch
    meta = '0;
    meta.bitstream_addr   = 32'h0000_2000;
    meta.bitstream_length = 8'h04;
    meta.branch_meta.branch_ena = 1'b0;
    meta.barrier = 1'b0;

    wait (metacache_mem_if.req_valid == 1'b1);
    @(posedge clk);
    metacache_mem_if.rsp_valid = 1'b1;
    metacache_mem_if.rsp_data.tag = metacache_mem_if.req_data.tag;
    metacache_mem_if.rsp_data.data = '0;
    metacache_mem_if.rsp_data.data[$bits(pgraph_meta_t)-1:0] = meta;
    @(posedge clk);
    metacache_mem_if.rsp_valid = 1'b0;

    // Respond to bitstream fetch requests
    for (int i = 0; i < NumChunks; i++) begin
      wait (bitstream_cache_mem_if.req_valid == 1'b1);
      @(posedge clk);
      bitstream_cache_mem_if.rsp_valid = 1'b1;
      bitstream_cache_mem_if.rsp_data.tag  = bitstream_cache_mem_if.req_data.tag;
      bitstream_cache_mem_if.rsp_data.data = '0;
      @(posedge clk);
      bitstream_cache_mem_if.rsp_valid = 1'b0;
    end

    wait (fdr_if.valid == 1'b1);
    assert (fdr_if.data.schedule_hw_cta_id == sched.schedule_hw_cta_id)
      else $fatal(1, "schedule_hw_cta_id mismatch");
    assert (fdr_if.data.metadata.bitstream_length == meta.bitstream_length)
      else $fatal(1, "metadata.bitstream_length mismatch");

    $display("PASS: fdr_top produced valid output");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_fdr_top.vcd");
    $dumpvars(0, tb_fdr_top);
  end
`endif

endmodule
