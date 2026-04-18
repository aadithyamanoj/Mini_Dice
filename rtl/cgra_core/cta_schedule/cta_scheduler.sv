module cta_scheduler
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,
    input logic enable_i, // Enable signal for scheduler operation

    // Active CTA Table (single entry)
    input active_cta_t active_cta_entry_i,

    // CTA Status (from status table)
    input logic                        is_prefetch_i,
    input logic [DICE_ADDR_WIDTH-1:0]  predict_pc_i,

    // SIMT Stack (single stack)
    input logic                        stack_top_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0]  cta_next_pc_i,
    input thread_mask_t                stack_top_active_mask_i,

    // SIMT stack controller idle signal: 1 when controller is in StateIdle
    // (i.e. the stack top is stable — no in-progress push/pop/modify).
    // Used to ensure schedule output is only latched when the post-update
    // PC is visible in cta_next_pc_i.
    input logic                        simt_update_ready_i,

    // External interface to invalidate committed e-blocks
    input logic                            eblock_commit_valid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,

    // External interface to release flushed e-blocks (from FDR predict-miss)
    input logic                            eblock_flush_valid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i,

    // Scheduler outputs
    output logic                           has_live_eblock_o,
    cta_sched_if.master scheduled_eblock
);

  // E-block tracking table
  logic [MAX_EBLOCK-1:0]            eblock_live_q;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_ptr_q;  // Circular pointer for e-block alloc

  // Single-CTA scheduling signals
  logic cta_valid;
  logic cta_branch_resolving;
  logic selection_valid;

  // CTA is schedulable when it is valid and the stack top is valid
  assign cta_valid = active_cta_entry_i.cta_valid && stack_top_valid_i;
  assign cta_branch_resolving = is_prefetch_i;
  assign selection_valid = cta_valid;

  // -----------------------------------------------------------------------
  // Registered output for valid-ready stability
  //
  // Once scheduled_eblock.valid is asserted, data must remain stable until
  // the handshake completes (scheduled_eblock.ready = 1).  We latch the
  // candidate data the cycle we first present valid=1 and hold it.
  //
  // simt_update_done_q gates candidate acceptance so we only latch after the
  // SIMT stack has settled to the correct post-update PC.
  // -----------------------------------------------------------------------
  logic             sched_valid_q;
  schedule_eblock_t sched_data_q;

  // -----------------------------------------------------------------------
  // SIMT-update-done tracking
  //
  // Each accepted schedule handshake may be followed by a SIMT stack update
  // (issued by the branch handler after it processes the eblock's metadata).
  // The update causes simt_update_ready_i to go low (SIMT stack controller
  // leaves StateIdle) and then return high when the update is complete.
  //
  // We must not present the NEXT schedule until this 0→1 transition has been
  // observed, because cta_next_pc_i only reflects the post-update PC after
  // simt_update_ready_i returns high.
  //
  // simt_update_done_q:
  //   1 = safe to latch schedule output (either initial state after reset,
  //       or the SIMT update for the last in-flight eblock has completed)
  //   0 = waiting for the SIMT stack update to complete
  // -----------------------------------------------------------------------
  logic simt_update_ready_prev_q;   // previous-cycle value of simt_update_ready_i
  logic simt_update_done_q;         // 1 when safe to present next schedule

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      simt_update_ready_prev_q <= 1'b1;
      simt_update_done_q       <= 1'b1;   // safe to schedule immediately after reset
    end else begin
      simt_update_ready_prev_q <= simt_update_ready_i;

      if (sched_valid_q && scheduled_eblock.ready) begin
        // A schedule was just accepted — the branch handler will issue a SIMT
        // update after processing this eblock.  Wait for the 0→1 transition.
        simt_update_done_q <= 1'b0;
      end else if (!simt_update_done_q &&
                   simt_update_ready_i && !simt_update_ready_prev_q) begin
        // Detected 0→1 rising edge of simt_update_ready_i: the SIMT stack
        // controller just finished its update cycle.  cta_next_pc_i now
        // reflects the post-update PC.
        simt_update_done_q <= 1'b1;
      end
    end
  end

  // Combinational candidate (may change freely while not latched)
  logic             cand_valid;
  schedule_eblock_t cand_data;

  always_comb begin
    cand_valid = enable_i && selection_valid &&
                 (eblock_live_q[eblock_ptr_q] == 1'b0) &&
                 simt_update_done_q;
    cand_data.schedule_next_pc       = (cta_branch_resolving == 1'b1) ? predict_pc_i : cta_next_pc_i;
    cand_data.schedule_eblock_id     = (EBLOCK_ID_WIDTH)'(eblock_ptr_q);
    cand_data.schedule_active_mask   = stack_top_active_mask_i;
    cand_data.schedule_prefetch_block = cta_branch_resolving;
    cand_data.schedule_cta_id        = active_cta_entry_i.cta_id;
    cand_data.schedule_grid_size     = active_cta_entry_i.grid_size;
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      sched_valid_q <= 1'b0;
      sched_data_q  <= '0;
    end else begin
      if (sched_valid_q && scheduled_eblock.ready) begin
        // Handshake complete — deassert valid for one cycle so that
        // eblock_live_q and eblock_ptr_q settle before next candidate eval.
        sched_valid_q <= 1'b0;
      end else if (!sched_valid_q) begin
        // Not currently presenting — latch candidate when ready
        sched_valid_q <= cand_valid;
        if (cand_valid) sched_data_q <= cand_data;
      end
      // else: sched_valid_q=1 && !ready — hold data stable (no assignment)
    end
  end

  assign scheduled_eblock.valid = sched_valid_q;
  assign scheduled_eblock.data  = sched_data_q;

  assign has_live_eblock_o = |eblock_live_q;


  // Sequential logic for state updates
  always_ff @(posedge clk_i) begin
    if (rst_i == 1'b1) begin
      eblock_live_q <= '0;
      eblock_ptr_q <= '0;
    end else begin
      if (eblock_commit_valid_i == 1'b1) begin
        eblock_live_q[eblock_commit_id_i] <= 1'b0;
      end
      if (eblock_flush_valid_i == 1'b1) begin
        eblock_live_q[eblock_flush_id_i] <= 1'b0;
      end
      if ((enable_i == 1'b1) && (scheduled_eblock.valid == 1'b1) &&
          (scheduled_eblock.ready == 1'b1)) begin
        eblock_live_q[eblock_ptr_q] <= 1'b1;
        if (eblock_ptr_q == MAX_EBLOCK - 1) begin
          eblock_ptr_q <= '0;
        end else begin
          eblock_ptr_q <= eblock_ptr_q + 1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  ValidMask: assert property (@(posedge clk_i) disable iff (rst_i)
    scheduled_eblock.valid |-> (!$isunknown(scheduled_eblock.data.schedule_active_mask))
  ) else $display("ValidMask: Tried to schedule with invalid active mask");
`endif

endmodule
