// =============================================================================
// Testbench: tb_fdr_top.sv
// =============================================================================

`timescale 1ns / 1ps

module tb_fdr_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;

  localparam int ClkPeriod      = 10;
  localparam int TimeoutCycles  = 5000;
  localparam int BeatBits       = AxiDataWidth;
  localparam int MetaBeats      = DICE_METADATA_WIDTH / BeatBits;
  localparam int BitstreamBeats = DICE_BITSTREAM_SIZE / BeatBits;
  localparam int CmAddrWidth    = $clog2(DICE_BITSTREAM_SIZE);

  logic clk;
  logic rst;
  int cycle_count;

  slv_req_t mfetch_req_o;
  slv_resp_t mfetch_resp_i;
  slv_req_t bsfetch_req_o;
  slv_resp_t bsfetch_resp_i;
  cta_sched_if schedule_if ();
  fdr_if fdr_if ();
  simt_stack_status_entry_t simt_status;
  logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs_i;
  branch_predict_interface_t bh_branch_predict_info_o;
  logic                      bh_branch_predict_info_we_o;
  dice_cta_status_t          cta_status_data_i;
  logic                      simt_update_valid_o;
  logic                      simt_update_ready_i;
  simt_stack_update_t        simt_update_stack_data_o;
  logic                      cm_wr_buffer_o;
  logic [CmAddrWidth-1:0]    cm_wr_addr_o;
  logic [BeatBits-1:0]       cm_wr_data_o;
  logic                      cm_wr_valid_o;
  logic                      eblock_flush_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id;

  fdr_top #(
      .BITSTREAM_SIZE(DICE_BITSTREAM_SIZE)
  ) u_dut (
      .clk_i                   (clk),
      .rst_i                   (rst),
      .mfetch_req_o            (mfetch_req_o),
      .mfetch_resp_i           (mfetch_resp_i),
      .bsfetch_req_o           (bsfetch_req_o),
      .bsfetch_resp_i          (bsfetch_resp_i),
      .schedule_if             (schedule_if),
      .fdr_if                  (fdr_if),
      .simt_status_i           (simt_status),
      .pred_regs_i             (pred_regs_i),
      .bh_branch_predict_info_o(bh_branch_predict_info_o),
      .bh_branch_predict_info_we_o(bh_branch_predict_info_we_o),
      .cta_status_data_i       (cta_status_data_i),
      .simt_update_valid_o     (simt_update_valid_o),
      .simt_update_ready_i     (simt_update_ready_i),
      .simt_update_stack_data_o(simt_update_stack_data_o),
      .cm_wr_buffer_o          (cm_wr_buffer_o),
      .cm_wr_addr_o            (cm_wr_addr_o),
      .cm_wr_data_o            (cm_wr_data_o),
      .cm_wr_valid_o           (cm_wr_valid_o),
      .eblock_flush_valid_o    (eblock_flush_valid),
      .eblock_flush_id_o       (eblock_flush_id)
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
    fdr_if.ready      = 1'b1;

    simt_status       = '0;
    pred_regs_i       = '0;
    cta_status_data_i = '0;
    simt_update_ready_i = 1'b1;

    mfetch_resp_i = '0;
    bsfetch_resp_i = '0;
    mfetch_resp_i.ar_ready = 1'b1;
    bsfetch_resp_i.ar_ready = 1'b1;

    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic send_meta_response(input pgraph_meta_t meta);
    logic [DICE_METADATA_WIDTH-1:0] packed_meta;

    packed_meta = DICE_METADATA_WIDTH'(meta);
    wait (mfetch_req_o.ar_valid);
    for (int i = 0; i < MetaBeats; i++) begin
      wait (mfetch_req_o.r_ready);
      mfetch_resp_i.r_valid = 1'b1;
      mfetch_resp_i.r.id    = mfetch_req_o.ar.id;
      mfetch_resp_i.r.data  = packed_meta >> (i * BeatBits);
      mfetch_resp_i.r.last  = (i == MetaBeats - 1);
      @(posedge clk);
      mfetch_resp_i.r_valid = 1'b0;
      mfetch_resp_i.r.last  = 1'b0;
      mfetch_resp_i.r.data  = '0;
    end
  endtask

  task automatic send_bitstream_response(input logic expected_buffer);
    logic [BeatBits-1:0] expected_data;

    wait (bsfetch_req_o.ar_valid);
    for (int i = 0; i < BitstreamBeats; i++) begin
      wait (bsfetch_req_o.r_ready);
      expected_data       = BeatBits'(16'h0200 + i);
      bsfetch_resp_i.r_valid = 1'b1;
      bsfetch_resp_i.r.id    = bsfetch_req_o.ar.id;
      bsfetch_resp_i.r.data  = expected_data;
      bsfetch_resp_i.r.last  = (i == BitstreamBeats - 1);
      #1;
      assert (cm_wr_valid_o)
        else $fatal(1, "missing cm write pulse on beat %0d", i);
      assert (cm_wr_buffer_o == expected_buffer)
        else $fatal(1, "buffer select mismatch on beat %0d", i);
      assert (cm_wr_addr_o == CmAddrWidth'(i * BeatBits))
        else $fatal(1, "cm write address mismatch on beat %0d", i);
      assert (cm_wr_data_o == expected_data)
        else $fatal(1, "cm write data mismatch on beat %0d", i);
      @(posedge clk);
      bsfetch_resp_i.r_valid = 1'b0;
      bsfetch_resp_i.r.last  = 1'b0;
      bsfetch_resp_i.r.data  = '0;
    end
  endtask

  initial begin
    schedule_eblock_t sched;
    pgraph_meta_t     meta;
    logic             expected_buffer;

    $display("tb_fdr_top");

    reset_dut();

    sched = '0;
    sched.schedule_next_pc        = 32'h0000_1000;
    sched.schedule_eblock_id      = '0;
    sched.schedule_active_mask    = {DICE_NUM_MAX_THREADS_PER_CORE{1'b1}};
    sched.schedule_prefetch_block = 1'b0;
    sched.schedule_cta_id         = '0;
    sched.schedule_grid_size.x    = 1;
    sched.schedule_grid_size.y    = 1;
    sched.schedule_grid_size.z    = 1;

    simt_status.valid       = 1'b1;
    simt_status.next_pc     = sched.schedule_next_pc;
    simt_status.active_mask = sched.schedule_active_mask;
    simt_status.empty       = 1'b0;
    simt_status.full        = 1'b0;

    meta = '0;
    meta.bitstream_addr           = 32'h0000_2000;
    meta.bitstream_length         = 8'h04;
    meta.branch_meta.branch_ena   = 1'b0;
    meta.barrier                  = 1'b0;

    wait (schedule_if.ready);
    schedule_if.data  = sched;
    schedule_if.valid = 1'b1;
    @(posedge clk);
    schedule_if.valid = 1'b0;

    send_meta_response(meta);

    wait (bsfetch_req_o.ar_valid);
    expected_buffer = cm_wr_buffer_o;
    send_bitstream_response(expected_buffer);

    wait (fdr_if.valid);
    assert (fdr_if.data.schedule_eblock_id == sched.schedule_eblock_id)
      else $fatal(1, "schedule_eblock_id mismatch");
    assert (fdr_if.data.metadata.bitstream_length == meta.bitstream_length)
      else $fatal(1, "metadata.bitstream_length mismatch");
    assert (fdr_if.data.loaded_buffer == expected_buffer)
      else $fatal(1, "loaded_buffer mismatch");

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
