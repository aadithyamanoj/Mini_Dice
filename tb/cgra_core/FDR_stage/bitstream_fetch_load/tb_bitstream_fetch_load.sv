// =============================================================================
// Testbench: tb_bitstream_fetch_load.sv
// =============================================================================

`timescale 1ns / 1ps

module tb_bitstream_fetch_load;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;

  localparam int ClkPeriod      = 10;
  localparam int TimeoutCycles  = 3000;
  localparam int BeatBits       = AxiDataWidth;
  localparam int BitstreamBeats = (DICE_BITSTREAM_SIZE + BeatBits - 1) / BeatBits;
  localparam int CmAddrWidth    = $clog2(DICE_BITSTREAM_SIZE);

  logic clk;
  logic rst;

  int cycle_count;

  logic                            flush_i;
  logic                            meta_valid_i;
  logic [DICE_ADDR_WIDTH-1:0]      bitstream_addr_i;
  logic [CmAddrWidth-1:0]          cm_wr_addr_o;
  logic [BeatBits-1:0]             cm_wr_data_o;
  logic                            cm_wr_valid_o;
  logic                            done_streaming_o;
  logic                            cm_num_o;
  slv_req_t                        bs_req_o;
  slv_resp_t                       bs_resp_i;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $fatal(1, "TIMEOUT");
      end
    end
  end

  bitstream_fetch_load u_dut (
      .clk_i           (clk),
      .rst_i           (rst),
      .flush_i         (flush_i),
      .meta_valid_i    (meta_valid_i),
      .bitstream_addr_i(bitstream_addr_i),
      .cm_wr_addr_o    (cm_wr_addr_o),
      .cm_wr_data_o    (cm_wr_data_o),
      .cm_wr_valid_o   (cm_wr_valid_o),
      .done_streaming_o(done_streaming_o),
      .bs_req_o        (bs_req_o),
      .bs_resp_i       (bs_resp_i),
      .cm_num_o        (cm_num_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  task automatic reset_dut();
    rst              = 1'b1;
    flush_i          = 1'b0;
    meta_valid_i     = 1'b0;
    bitstream_addr_i = '0;
    bs_resp_i        = '0;
    bs_resp_i.ar_ready = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic issue_load(input logic [DICE_ADDR_WIDTH-1:0] addr);
    bitstream_addr_i = addr;
    meta_valid_i     = 1'b1;
    @(posedge clk);
    meta_valid_i     = 1'b0;
  endtask

  task automatic send_bitstream(
    input logic expected_buffer,
    input int   seed
  );
    logic [BeatBits-1:0] expected_data;

    wait (bs_req_o.ar_valid);
    for (int i = 0; i < BitstreamBeats; i++) begin
      wait (bs_req_o.r_ready);
      expected_data    = BeatBits'(seed + i);
      bs_resp_i.r_valid = 1'b1;
      bs_resp_i.r.data  = expected_data;
      bs_resp_i.r.last  = (i == BitstreamBeats - 1);
      #1;
      assert (cm_wr_valid_o)
        else $fatal(1, "cm_wr_valid_o not asserted on beat %0d", i);
      assert (cm_num_o == expected_buffer)
        else $fatal(1, "cm_num_o mismatch on beat %0d", i);
      assert (cm_wr_addr_o == CmAddrWidth'(i * BeatBits))
        else $fatal(1, "cm_wr_addr_o mismatch on beat %0d", i);
      assert (cm_wr_data_o == expected_data)
        else $fatal(1, "cm_wr_data_o mismatch on beat %0d", i);
      @(posedge clk);
      bs_resp_i.r_valid = 1'b0;
      bs_resp_i.r.last  = 1'b0;
      bs_resp_i.r.data  = '0;
    end
  endtask

  initial begin
    logic first_buffer;
    logic second_buffer;
    logic restart_buffer;

    $display("tb_bitstream_fetch_load");

    reset_dut();

    issue_load(32'h0000_2000);
    wait (bs_req_o.ar_valid);
    first_buffer = cm_num_o;
    send_bitstream(first_buffer, 16'h0100);

    wait (done_streaming_o);
    assert (cm_num_o == first_buffer)
      else $fatal(1, "resident buffer mismatch after initial load");

    issue_load(32'h0000_2000);
    repeat (3) begin
      @(posedge clk);
      assert (!bs_req_o.ar_valid)
        else $fatal(1, "resident hit unexpectedly re-issued a fetch");
      assert (!cm_wr_valid_o)
        else $fatal(1, "resident hit unexpectedly wrote CM data");
      assert (cm_num_o == first_buffer)
        else $fatal(1, "resident hit selected wrong buffer");
    end

    issue_load(32'h0000_2400);
    wait (bs_req_o.ar_valid);
    second_buffer = cm_num_o;
    assert (second_buffer != first_buffer)
      else $fatal(1, "second bitstream did not toggle buffers");
    send_bitstream(second_buffer, 16'h0200);

    wait (done_streaming_o);
    assert (cm_num_o == second_buffer)
      else $fatal(1, "resident buffer mismatch after second load");

    issue_load(32'h0000_2800);
    wait (bs_req_o.ar_valid);
    repeat (4) begin
      wait (bs_req_o.r_ready);
      bs_resp_i.r_valid = 1'b1;
      bs_resp_i.r.data  = BeatBits'(16'h0300);
      bs_resp_i.r.last  = 1'b0;
      #1;
      assert (cm_wr_valid_o)
        else $fatal(1, "cm write missing before flush");
      @(posedge clk);
      bs_resp_i.r_valid = 1'b0;
      bs_resp_i.r.data  = '0;
    end

    flush_i = 1'b1;
    @(posedge clk);
    flush_i = 1'b0;

    repeat (2) @(posedge clk);
    assert (!done_streaming_o)
      else $fatal(1, "flushed transfer incorrectly reported resident");

    issue_load(32'h0000_2800);
    wait (bs_req_o.ar_valid);
    restart_buffer = cm_num_o;
    wait (bs_req_o.r_ready);
    bs_resp_i.r_valid = 1'b1;
    bs_resp_i.r.data  = BeatBits'(16'h0400);
    bs_resp_i.r.last  = 1'b0;
    #1;
    assert (cm_wr_valid_o)
      else $fatal(1, "cm write missing after restart");
    assert (cm_wr_addr_o == '0)
      else $fatal(1, "cm write address did not restart at zero");
    assert (cm_num_o == restart_buffer)
      else $fatal(1, "restart buffer changed during first beat");
    @(posedge clk);
    bs_resp_i.r_valid = 1'b0;
    bs_resp_i.r.data  = '0;

    $display("PASS: bitstream loader direct-write path");
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
