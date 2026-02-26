// =============================================================================
// Testbench: tb_decode.sv (simplified happy-path)
// =============================================================================

`timescale 1ns / 1ps
`include "dice_define.vh"

module tb_decode;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 200;

  logic clk;
  logic rst;
  int cycle_count;

  pgraph_meta_t                      metadata_i;
  logic                              meta_in_valid_i;
  thread_mask_t                      real_active_thread_mask_i;
  logic [DICE_ADDR_WIDTH-1:0]        bitstream_addr_o;
  logic                              bitstream_addr_valid_o;
  logic [BITSTREAM_LENGTH_WIDTH-1:0] bitstream_length_o;
  branch_meta_t                      branch_metadata_o;
  logic                              branch_req_valid_o;
  logic                              is_barrier_o;
  fdr_meta_t                         meta_o;

  decode u_dut (
      .metadata_i               (metadata_i),
      .meta_in_valid_i          (meta_in_valid_i),
      .real_active_thread_mask_i(real_active_thread_mask_i),
      .bitstream_addr_o         (bitstream_addr_o),
      .bitstream_addr_valid_o   (bitstream_addr_valid_o),
      .bitstream_length_o       (bitstream_length_o),
      .branch_metadata_o        (branch_metadata_o),
      .branch_req_valid_o       (branch_req_valid_o),
      .is_barrier_o             (is_barrier_o),
      .meta_o                   (meta_o)
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

  task automatic reset_inputs();
    rst = 1'b1;
    metadata_i = '0;
    meta_in_valid_i = 1'b0;
    real_active_thread_mask_i = '0;
    repeat (2) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  initial begin
    $display("tb_decode (happy-path)");

    reset_inputs();

    // meta_in_valid low
    #1;
    assert (bitstream_addr_valid_o == 1'b0)
      else $fatal(1, "bitstream_addr_valid_o should be 0");
    assert (branch_req_valid_o == 1'b0)
      else $fatal(1, "branch_req_valid_o should be 0");

    // Drive valid metadata
    metadata_i = '0;
    metadata_i.bitstream_addr   = 32'h0000_2000;
    metadata_i.bitstream_length = 8'h04;
    metadata_i.branch_meta.branch_ena = 1'b1;
    metadata_i.branch_meta.branch_uni = 1'b1;
    metadata_i.barrier = 1'b0;
    meta_in_valid_i = 1'b1;
    #1;

    assert (bitstream_addr_o == metadata_i.bitstream_addr)
      else $fatal(1, "bitstream_addr_o mismatch");
    assert (bitstream_length_o == metadata_i.bitstream_length)
      else $fatal(1, "bitstream_length_o mismatch");
    assert (bitstream_addr_valid_o == 1'b1)
      else $fatal(1, "bitstream_addr_valid_o not asserted");
    assert (branch_req_valid_o == 1'b1)
      else $fatal(1, "branch_req_valid_o not asserted");
    assert (branch_metadata_o == metadata_i.branch_meta)
      else $fatal(1, "branch_metadata_o mismatch");
    assert (is_barrier_o == metadata_i.barrier)
      else $fatal(1, "is_barrier_o mismatch");

    $display("PASS: decode outputs");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

endmodule
