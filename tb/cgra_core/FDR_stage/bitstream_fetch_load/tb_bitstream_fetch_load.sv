// =============================================================================
// Testbench: tb_bitstream_fetch_load.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "VX_define.vh"

module tb_bitstream_fetch_load;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 2000;
  localparam int TagWidth = DICE_ADDR_WIDTH;
  localparam int BitstreamSize = DICE_BITSTREAM_SIZE;
  localparam int ChunkSize = VX_gpu_pkg::VX_MEM_DATA_WIDTH;
  localparam int NumChunks = (BitstreamSize + ChunkSize - 1) / ChunkSize;

  logic clk;
  logic rst;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $fatal(1, "TIMEOUT");
      end
    end
  end

  // DUT Signals
  logic                       flush_i;
  logic                       meta_valid_i;
  logic [DICE_ADDR_WIDTH-1:0] bitstream_addr_i;
  logic [ChunkSize-1:0]       cm0_data_o;
  logic [NumChunks-1:0]       cm0_chunk_en_o;
  logic [ChunkSize-1:0]       cm1_data_o;
  logic [NumChunks-1:0]       cm1_chunk_en_o;
  logic                       done_streaming_o;
  logic                       cm_num_o;

  VX_mem_bus_if #(
      .DATA_SIZE(VX_gpu_pkg::VX_MEM_DATA_WIDTH / 8),
      .TAG_WIDTH(TagWidth)
  ) cache_bus_if ();

  bitstream_fetch_load #(
      .TAG_WIDTH(TagWidth)
  ) u_dut (
      .clk_i           (clk),
      .rst_i           (rst),
      .flush_i         (flush_i),
      .meta_valid_i    (meta_valid_i),
      .bitstream_addr_i(bitstream_addr_i),
      .cm0_data_o      (cm0_data_o),
      .cm0_chunk_en_o  (cm0_chunk_en_o),
      .cm1_data_o      (cm1_data_o),
      .cm1_chunk_en_o  (cm1_chunk_en_o),
      .done_streaming_o(done_streaming_o),
      .cache_bus_if    (cache_bus_if),
      .cm_num_o        (cm_num_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst                    = 1'b1;
    flush_i                = 1'b0;
    meta_valid_i           = 1'b0;
    bitstream_addr_i       = '0;
    cache_bus_if.req_ready = 1'b1;
    cache_bus_if.rsp_valid = 1'b0;
    cache_bus_if.rsp_data  = '0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    $display("tb_bitstream_fetch_load (happy-path)");

    reset_dut();

    bitstream_addr_i = 32'h0000_2000;
    meta_valid_i     = 1'b1;
    @(posedge clk);
    meta_valid_i     = 1'b0;

    for (int i = 0; i < NumChunks; i++) begin
      wait (cache_bus_if.req_valid == 1'b1);
      @(posedge clk);
      cache_bus_if.rsp_valid = 1'b1;
      cache_bus_if.rsp_data.tag  = cache_bus_if.req_data.tag;
      cache_bus_if.rsp_data.data = '0;
      @(posedge clk);
      cache_bus_if.rsp_valid = 1'b0;
    end

    wait (done_streaming_o == 1'b1);
    assert (done_streaming_o == 1'b1)
      else $fatal(1, "done_streaming_o not asserted");

    $display("PASS: bitstream loaded");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_bitstream_fetch_load.vcd");
    $dumpvars(0, tb_bitstream_fetch_load);
  end
`endif

endmodule
