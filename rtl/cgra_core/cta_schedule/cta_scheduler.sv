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

    // External interface to invalidate committed e-blocks
    input logic                            eblock_commit_valid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i,

    // External interface to release flushed e-blocks (from FDR predict-miss)
    input logic                            eblock_flush_valid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_flush_id_i,

    // Scheduler outputs
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

  // Output assignments
  always_comb begin
    scheduled_eblock.valid = enable_i && selection_valid && (eblock_live_q[eblock_ptr_q] == 1'b0);
    scheduled_eblock.data.schedule_next_pc = (cta_branch_resolving == 1'b1) ? predict_pc_i : cta_next_pc_i;
    scheduled_eblock.data.schedule_eblock_id = (EBLOCK_ID_WIDTH)'(eblock_ptr_q);
    scheduled_eblock.data.schedule_active_mask = stack_top_active_mask_i;
    scheduled_eblock.data.schedule_prefetch_block = cta_branch_resolving;
    scheduled_eblock.data.schedule_grid_size = active_cta_entry_i.grid_size;
  end


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
