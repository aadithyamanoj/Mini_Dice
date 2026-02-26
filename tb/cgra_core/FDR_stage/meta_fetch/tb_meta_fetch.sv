// =============================================================================
// Testbench: tb_meta_fetch.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "VX_define.vh"

module tb_meta_fetch;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 2000;
  localparam int TagWidth = DICE_ADDR_WIDTH;

  logic clk;
  logic rst;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $fatal(1, "TIMEOUT");
      end
    end
  end

  // DUT Signals
  logic                       schedule_valid_i;
  logic [DICE_ADDR_WIDTH-1:0] fdr_next_pc_i;
  logic                       schedule_ready_o;
  pgraph_meta_t               outgoing_meta_o;
  logic                       meta_valid_o;
  logic                       fire_eblock_i;
  logic                       flush_i;

  VX_mem_bus_if #(
      .DATA_SIZE(VX_gpu_pkg::VX_MEM_DATA_WIDTH / 8),
      .TAG_WIDTH(TagWidth)
  ) meta_fetch_bus_if ();

  meta_fetch #(
      .TAG_WIDTH(TagWidth)
  ) u_dut (
      .clk_i            (clk),
      .rst_i            (rst),
      .schedule_valid_i (schedule_valid_i),
      .fdr_next_pc_i    (fdr_next_pc_i),
      .schedule_ready_o (schedule_ready_o),
      .meta_fetch_bus_if(meta_fetch_bus_if),
      .outgoing_meta_o  (outgoing_meta_o),
      .meta_valid_o     (meta_valid_o),
      .fire_eblock_i    (fire_eblock_i),
      .flush_i          (flush_i)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst                       = 1'b1;
    schedule_valid_i          = 1'b0;
    fdr_next_pc_i             = '0;
    fire_eblock_i             = 1'b0;
    flush_i                   = 1'b0;
    meta_fetch_bus_if.req_ready = 1'b1;
    meta_fetch_bus_if.rsp_valid = 1'b0;
    meta_fetch_bus_if.rsp_data  = '0;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    logic [DICE_ADDR_WIDTH-1:0] pc;

    $display("tb_meta_fetch (happy-path)");

    reset_dut();

    assert (schedule_ready_o == 1'b1)
      else $fatal(1, "schedule_ready_o not high after reset");

    pc = 32'h0000_1000;
    fdr_next_pc_i    = pc;
    schedule_valid_i = 1'b1;
    @(posedge clk);
    schedule_valid_i = 1'b0;

    wait (meta_fetch_bus_if.req_valid == 1'b1);
    wait (meta_fetch_bus_if.rsp_ready == 1'b1);
    @(posedge clk);
    meta_fetch_bus_if.rsp_valid     = 1'b1;
    meta_fetch_bus_if.rsp_data.tag  = meta_fetch_bus_if.req_data.tag;
    meta_fetch_bus_if.rsp_data.data = '0;
    @(posedge clk);
    meta_fetch_bus_if.rsp_valid = 1'b0;

    wait (meta_valid_o == 1'b1);
    assert (meta_valid_o == 1'b1)
      else $fatal(1, "meta_valid_o not asserted");

    fire_eblock_i = 1'b1;
    @(posedge clk);
    fire_eblock_i = 1'b0;

    $display("PASS: meta fetched");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_meta_fetch.vcd");
    $dumpvars(0, tb_meta_fetch);
  end
`endif

endmodule
