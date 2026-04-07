module tb_branch_handler;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod     = 10;
  localparam int TimeoutCycles = 100;
  localparam logic [DICE_ADDR_WIDTH-1:0] StartPc = 16'h0100;

  logic clk;
  logic rst;
  int cycle_count;

  branch_meta_t branch_meta;
  logic         branch_meta_valid;

  thread_mask_t                real_active_thread_mask;
  thread_mask_t                cs_active_mask;
  logic [DICE_ADDR_WIDTH-1:0]  pc;

  logic               update_valid;
  logic               update_ready;
  simt_stack_update_t simt_stack_update;

  branch_predict_interface_t branch_predict_info;
  logic                      has_pending_eblock;
  logic                      unresolved_control_divergence;
  logic                      is_prefetch;
  logic                      fire_eblock;
  logic [DICE_ADDR_WIDTH-1:0] simt_stack_pc;
  logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs;
  logic bh_done;
  logic predict_miss;

  branch_handler u_dut (
    .clk_i                           (clk),
    .rst_i                           (rst),
    .branch_predict_info_o           (branch_predict_info),
    .branch_meta_i                   (branch_meta),
    .branch_meta_valid_i             (branch_meta_valid),
    .real_active_thread_mask_o       (real_active_thread_mask),
    .cs_active_mask_i                (cs_active_mask),
    .pc_i                            (pc),
    .update_valid_o                  (update_valid),
    .update_ready_i                  (update_ready),
    .simt_stack_update_o             (simt_stack_update),
    .pred_regs_i                     (pred_regs),
    .has_pending_eblock_i            (has_pending_eblock),
    .unresolved_control_divergence_i (unresolved_control_divergence),
    .is_prefetch_i                   (is_prefetch),
    .fire_eblock_i                   (fire_eblock),
    .simt_stack_pc_i                 (simt_stack_pc),
    .bh_done_o                       (bh_done),
    .predict_miss_o                  (predict_miss)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod/2) clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $error("TIMEOUT");
        $finish;
      end
    end
  end

  task automatic reset_dut();
    rst                           = 1'b1;
    branch_meta                   = '0;
    branch_meta_valid             = 1'b0;
    cs_active_mask                = '1;
    pc                            = StartPc;
    update_ready                  = 1'b1;
    pred_regs                     = '0;
    has_pending_eblock            = 1'b0;
    unresolved_control_divergence = 1'b0;
    is_prefetch                   = 1'b0;
    fire_eblock                   = 1'b0;
    simt_stack_pc                 = StartPc;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic send_branch_meta(input branch_meta_t meta_i);
    branch_meta       = meta_i;
    branch_meta_valid = 1'b0;
    @(posedge clk);
    branch_meta_valid = 1'b1;
    @(posedge clk);
    branch_meta_valid = 1'b0;
  endtask

  task automatic clear_completed_entry();
    fire_eblock = 1'b1;
    @(posedge clk);
    fire_eblock = 1'b0;
    @(posedge clk);
  endtask

  task automatic wait_for_done();
    int wait_cycles;
    wait_cycles = 0;
    while (!bh_done) begin
      @(posedge clk);
      wait_cycles++;
      if (wait_cycles >= 20) begin
        $error("branch_handler did not finish");
        $finish;
      end
    end
  endtask

  task automatic test_linear_return();
    branch_meta_t meta;
    int update_valid_count;
    int status_we_count;

    meta = '0;
    meta.is_return = 1'b1;
    update_valid_count = 0;
    status_we_count = 0;

    fork
      begin
        repeat (10) begin
          @(posedge clk);
          if (update_valid) begin
            update_valid_count++;
            assert (simt_stack_update.update_next_pc == StartPc + DICE_ADDR_WIDTH'(DICE_METADATA_WIDTH))
              else $fatal(1, "Unexpected next PC for linear return: %h", simt_stack_update.update_next_pc);
          end
          if (|branch_predict_info.valid_edits_bitmap) begin
            status_we_count++;
            assert (branch_predict_info.valid_edits_bitmap == 3'b001)
              else $fatal(1, "Unexpected valid_edits_bitmap for return: %b", branch_predict_info.valid_edits_bitmap);
            assert (branch_predict_info.is_return)
              else $fatal(1, "Return bit was not set");
          end
          assert (!predict_miss)
            else $fatal(1, "Predict miss should stay low in linear return test");
        end
      end
      begin
        send_branch_meta(meta);
      end
    join

    wait_for_done();
    assert (update_valid_count == 1)
      else $fatal(1, "Expected one SIMT update for linear return, got %0d", update_valid_count);
    assert (status_we_count == 1)
      else $fatal(1, "Expected one status write for linear return, got %0d", status_we_count);
    assert (real_active_thread_mask == cs_active_mask)
      else $fatal(1, "Active mask changed unexpectedly in linear return test");
    clear_completed_entry();
  endtask

  task automatic test_divergent_branch_status();
    branch_meta_t meta;
    int update_valid_count;
    int status_we_count;

    meta = '0;
    meta.branch_ena                = 1'b1;
    meta.branch_uni                = 1'b0;
    meta.branch_jump_target_offset = 'd3;
    meta.branch_reconv_offset      = 'd5;
    update_valid_count = 0;
    status_we_count = 0;

    fork
      begin
        repeat (10) begin
          @(posedge clk);
          if (update_valid) update_valid_count++;
          if (|branch_predict_info.valid_edits_bitmap) begin
            status_we_count++;
            assert (branch_predict_info.valid_edits_bitmap == 3'b110)
              else $fatal(1, "Unexpected valid_edits_bitmap for divergent branch: %b", branch_predict_info.valid_edits_bitmap);
            assert (branch_predict_info.unresolved_control_divergence)
              else $fatal(1, "Divergence flag was not set");
            assert (branch_predict_info.predict_pc == StartPc + DICE_ADDR_WIDTH'(DICE_METADATA_WIDTH * 3))
              else $fatal(1, "Unexpected predict PC: %h", branch_predict_info.predict_pc);
          end
          assert (!predict_miss)
            else $fatal(1, "Predict miss should stay low in divergent status test");
        end
      end
      begin
        send_branch_meta(meta);
      end
    join

    wait_for_done();
    assert (update_valid_count == 0)
      else $fatal(1, "Expected zero SIMT updates for non-prefetch divergent branch, got %0d", update_valid_count);
    assert (status_we_count == 1)
      else $fatal(1, "Expected one status write for divergent branch, got %0d", status_we_count);
    assert (real_active_thread_mask == cs_active_mask)
      else $fatal(1, "Active mask changed unexpectedly in divergent branch test");
    clear_completed_entry();
  endtask

  initial begin
    reset_dut();

    test_linear_return();
    test_divergent_branch_status();

    repeat (5) @(posedge clk);
    $finish;
  end

`ifdef FSDB
  initial begin
    $fsdbDumpfile("tb_branch_handler.fsdb");
    $fsdbDumpvars(0, tb_branch_handler, "+struct", "+mda");
  end
`endif

endmodule
