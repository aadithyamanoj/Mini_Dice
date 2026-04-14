`include "dice_define.vh"

module branch_handler
  import dice_frontend_pkg::*;
  import dice_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Status table output
    output branch_predict_interface_t branch_predict_info_o,

    // Decode inputs
    input  branch_meta_t branch_meta_i,
    input  logic         branch_meta_valid_i,  // stays valid for many cycles

    // Active thread mask output
    output thread_mask_t real_active_thread_mask_o,

    // CS → FDR stage buffer
    input thread_mask_t                cs_active_mask_i,
    input logic [DICE_ADDR_WIDTH-1:0]  pc_i,

    // SIMT stacks
    output logic                update_valid_o,
    input  logic                update_ready_i,
    output simt_stack_update_t  simt_stack_update_o,

    // Predicate registers
    input [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs_i,

    // Status table inputs
    input logic has_pending_eblock_i,
    input logic unresolved_control_divergence_i,

    // Phase / fire control
    input  logic                       is_prefetch_i,
    input  logic                       fire_eblock_i,
    input  logic [DICE_ADDR_WIDTH-1:0] simt_stack_pc_i,

    // Outputs to valid_check / fdr_top
    output logic bh_done_o,
    output logic predict_miss_o
);

  // -----------------------------------------------------------------------
  // Per-entry status enum
  // -----------------------------------------------------------------------
  typedef enum logic [3:0] {
    S_EMPTY,
    S_STORED,
    // Phase 1 (prefetch entries only)
    S_WAIT_EXEC,
    S_PREV_STACK_SUBMIT,
    S_PREV_STACK_WAIT,
    S_PC_CHECK,
    // Phase 2 (all entries)
    S_CURR_STACK_SUBMIT,
    S_CURR_STACK_WAIT,
    S_CURR_STATUS_WRITE,
    S_DONE
  } entry_status_e;

  // -----------------------------------------------------------------------
  // 2-entry metadata table
  // -----------------------------------------------------------------------
  branch_meta_t               meta_table_q [1:0];
  logic [DICE_ADDR_WIDTH-1:0] entry_pc_q   [1:0];
  logic                       entry_is_prefetch_q [1:0];

  logic meta_wr_ptr_q;
  logic meta_rd_ptr_q;

  entry_status_e entry_status_q [1:0];

  // -----------------------------------------------------------------------
  // Rising-edge detector on branch_meta_valid_i
  // -----------------------------------------------------------------------
  logic branch_meta_valid_rise;

  bsg_edge_detect u_branch_meta_valid_rise (
      .clk_i   (clk_i),
      .reset_i (rst_i),
      .sig_i   (branch_meta_valid_i),
      .detect_o(branch_meta_valid_rise)
  );

  // -----------------------------------------------------------------------
  // Predicate register unpack
  // -----------------------------------------------------------------------
  logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] pred_reg_0, pred_reg_1;
  always_comb begin
    pred_reg_0 = '0;
    pred_reg_1 = '0;
    for (int i = 0; i < (`DICE_PR_NUM * `DICE_NUM_MAX_THREADS_PER_CORE); i++) begin
      if (i % 2 == 0)
        pred_reg_0[i/2] = pred_regs_i[i];
      else
        pred_reg_1[i/2] = pred_regs_i[i];
    end
  end

  // -----------------------------------------------------------------------
  // Active-meta mux: Phase 1 → previous entry; Phase 2 → current entry
  // -----------------------------------------------------------------------
  branch_meta_t               active_meta;
  logic [DICE_ADDR_WIDTH-1:0] active_pc;

  always_comb begin
    if (entry_status_q[meta_rd_ptr_q] == S_PREV_STACK_SUBMIT ||
        entry_status_q[meta_rd_ptr_q] == S_PREV_STACK_WAIT) begin
      active_meta = meta_table_q[meta_rd_ptr_q ^ 1];
      active_pc   = entry_pc_q  [meta_rd_ptr_q ^ 1];
    end else begin
      active_meta = meta_table_q[meta_rd_ptr_q];
      active_pc   = entry_pc_q  [meta_rd_ptr_q];
    end
  end

  // -----------------------------------------------------------------------
  // PC computations
  // -----------------------------------------------------------------------
  logic [DICE_ADDR_WIDTH-1:0] jump_target_pc;
  logic [DICE_ADDR_WIDTH-1:0] not_taken_pc;
  logic [DICE_ADDR_WIDTH-1:0] reconvergence_pc;

  assign jump_target_pc   = active_pc + DICE_ADDR_WIDTH'(DICE_METADATA_WIDTH) *
                                        DICE_ADDR_WIDTH'(active_meta.branch_jump_target_offset);
  assign not_taken_pc     = active_pc + DICE_ADDR_WIDTH'(DICE_METADATA_WIDTH);
  assign reconvergence_pc = active_pc + DICE_ADDR_WIDTH'(DICE_METADATA_WIDTH) *
                                        DICE_ADDR_WIDTH'(active_meta.branch_reconv_offset);

  // -----------------------------------------------------------------------
  // Predicate register selection and divergence classification
  // -----------------------------------------------------------------------
  thread_mask_t selected_pred;
  thread_mask_t branch_taken_mask;
  logic         all_taken;
  logic         all_not_taken;
  logic         has_divergence;

  always_comb begin
    selected_pred    = (active_meta.branch_pred_reg == 1'b1) ? pred_reg_1 : pred_reg_0;
    branch_taken_mask = active_meta.branch_neg_pred
                         ? (~selected_pred & cs_active_mask_i)
                         : ( selected_pred & cs_active_mask_i);
    all_taken     = (branch_taken_mask == cs_active_mask_i) && (cs_active_mask_i != '0);
    all_not_taken = (branch_taken_mask == '0)               && (cs_active_mask_i != '0);
    has_divergence = !all_taken && !all_not_taken            && (cs_active_mask_i != '0);
  end

  // -----------------------------------------------------------------------
  // SIMT stack update (combinational)
  // -----------------------------------------------------------------------
  always_comb begin
    simt_stack_update_o = '0;
    unique case (entry_status_q[meta_rd_ptr_q])
      S_PREV_STACK_SUBMIT: begin
        // Phase 1: resolve previous divergent branch using pred regs
        if (all_taken) begin
          simt_stack_update_o.update_with_divergence  = 1'b0;
          simt_stack_update_o.update_next_pc          = jump_target_pc;
          simt_stack_update_o.predicate_regs_value    = '0;
          simt_stack_update_o.branch_not_taken_pc     = '0;
          simt_stack_update_o.branch_reconvergence_pc = '0;
        end else if (all_not_taken) begin
          simt_stack_update_o.update_with_divergence  = 1'b0;
          simt_stack_update_o.update_next_pc          = not_taken_pc;
          simt_stack_update_o.predicate_regs_value    = '0;
          simt_stack_update_o.branch_not_taken_pc     = '0;
          simt_stack_update_o.branch_reconvergence_pc = '0;
        end else begin
          // Diverged
          simt_stack_update_o.update_with_divergence  = 1'b1;
          simt_stack_update_o.update_next_pc          = jump_target_pc;
          simt_stack_update_o.predicate_regs_value    = branch_taken_mask;
          simt_stack_update_o.branch_not_taken_pc     = not_taken_pc;
          simt_stack_update_o.branch_reconvergence_pc = reconvergence_pc;
        end
      end
      S_CURR_STACK_SUBMIT: begin
        // Phase 2: non-divergent current branch
        if (!active_meta.branch_ena) begin
          // No branch — linear advance
          simt_stack_update_o.update_with_divergence  = 1'b0;
          simt_stack_update_o.update_next_pc          = not_taken_pc;
          simt_stack_update_o.predicate_regs_value    = '0;
          simt_stack_update_o.branch_not_taken_pc     = '0;
          simt_stack_update_o.branch_reconvergence_pc = '0;
        end else begin
          // Uniform branch — jump
          simt_stack_update_o.update_with_divergence  = 1'b0;
          simt_stack_update_o.update_next_pc          = jump_target_pc;
          simt_stack_update_o.predicate_regs_value    = '0;
          simt_stack_update_o.branch_not_taken_pc     = '0;
          simt_stack_update_o.branch_reconvergence_pc = '0;
        end
      end
      default: simt_stack_update_o = '0;
    endcase
  end

  // -----------------------------------------------------------------------
  // Status table output (branch_predict_info_o) — combinational
  // -----------------------------------------------------------------------
  always_comb begin
    branch_predict_info_o = '0;
    unique case (entry_status_q[meta_rd_ptr_q])
      S_PC_CHECK: begin
        // Clear unresolved_control_divergence
        branch_predict_info_o.valid_edits_bitmap[2]        = 1'b1;
        branch_predict_info_o.unresolved_control_divergence = 1'b0;
      end
      S_CURR_STATUS_WRITE: begin
        // is_return (bit 0)
        branch_predict_info_o.valid_edits_bitmap[0] = meta_table_q[meta_rd_ptr_q].is_return;
        branch_predict_info_o.is_return             = meta_table_q[meta_rd_ptr_q].is_return;
        // predict_pc + unresolved_div (bits 1,2) for divergent blocks only
        if (meta_table_q[meta_rd_ptr_q].branch_ena && !meta_table_q[meta_rd_ptr_q].branch_uni) begin
          branch_predict_info_o.valid_edits_bitmap[1]        = 1'b1;
          branch_predict_info_o.predict_pc                   = jump_target_pc;
          branch_predict_info_o.valid_edits_bitmap[2]        = 1'b1;
          branch_predict_info_o.unresolved_control_divergence = 1'b1;
        end
      end
      default: ;
    endcase
  end

  // -----------------------------------------------------------------------
  // Real active thread mask
  // -----------------------------------------------------------------------
  always_comb begin
    if (entry_is_prefetch_q[meta_rd_ptr_q] && !has_pending_eblock_i &&
        meta_table_q[meta_rd_ptr_q].branch_ena &&
        !meta_table_q[meta_rd_ptr_q].branch_uni) begin
      real_active_thread_mask_o = cs_active_mask_i & branch_taken_mask;
    end else begin
      real_active_thread_mask_o = cs_active_mask_i;
    end
  end

  // -----------------------------------------------------------------------
  // Output assignments
  // -----------------------------------------------------------------------
  assign bh_done_o     = (entry_status_q[meta_rd_ptr_q] == S_DONE);

  assign predict_miss_o = (entry_status_q[meta_rd_ptr_q] == S_PC_CHECK) &&
                          (entry_pc_q[meta_rd_ptr_q] != simt_stack_pc_i);

  assign update_valid_o = (entry_status_q[meta_rd_ptr_q] == S_PREV_STACK_SUBMIT) ||
                          (entry_status_q[meta_rd_ptr_q] == S_CURR_STACK_SUBMIT);

  // -----------------------------------------------------------------------
  // Sequential state machine
  // -----------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      entry_status_q[0]      <= S_EMPTY;
      entry_status_q[1]      <= S_EMPTY;
      entry_is_prefetch_q[0] <= 1'b0;
      entry_is_prefetch_q[1] <= 1'b0;
      meta_wr_ptr_q          <= 1'b0;
      meta_rd_ptr_q          <= 1'b0;
    end else begin

      // ------------------------------------------------------------------
      // Case block: rd_ptr entry state transitions (lower priority)
      // ------------------------------------------------------------------
      unique case (entry_status_q[meta_rd_ptr_q])

        S_STORED: begin
          if (entry_is_prefetch_q[meta_rd_ptr_q])
            entry_status_q[meta_rd_ptr_q] <= S_WAIT_EXEC;
          else if (!meta_table_q[meta_rd_ptr_q].branch_ena ||
                    meta_table_q[meta_rd_ptr_q].branch_uni)
            entry_status_q[meta_rd_ptr_q] <= S_CURR_STACK_SUBMIT;
          else
            entry_status_q[meta_rd_ptr_q] <= S_CURR_STATUS_WRITE;
        end

        // ── Phase 1 ────────────────────────────────────────────────────
        S_WAIT_EXEC: begin
          if (!has_pending_eblock_i)
            entry_status_q[meta_rd_ptr_q] <= S_PREV_STACK_SUBMIT;
        end

        S_PREV_STACK_SUBMIT: begin
          if (update_valid_o && update_ready_i)
            entry_status_q[meta_rd_ptr_q] <= S_PREV_STACK_WAIT;
        end

        S_PREV_STACK_WAIT: begin
          if (update_ready_i)
            entry_status_q[meta_rd_ptr_q] <= S_PC_CHECK;
        end

        S_PC_CHECK: begin
          if (entry_pc_q[meta_rd_ptr_q] == simt_stack_pc_i) begin
            // PC match — proceed to Phase 2
            if (!meta_table_q[meta_rd_ptr_q].branch_ena ||
                 meta_table_q[meta_rd_ptr_q].branch_uni)
              entry_status_q[meta_rd_ptr_q] <= S_CURR_STACK_SUBMIT;
            else
              entry_status_q[meta_rd_ptr_q] <= S_CURR_STATUS_WRITE;
          end else begin
            // PC mismatch — flush; skip Phase 2
            entry_status_q[meta_rd_ptr_q] <= S_EMPTY;
            meta_rd_ptr_q                  <= meta_rd_ptr_q ^ 1'b1;
          end
        end

        // ── Phase 2 ────────────────────────────────────────────────────
        S_CURR_STACK_SUBMIT: begin
          if (update_valid_o && update_ready_i)
            entry_status_q[meta_rd_ptr_q] <= S_CURR_STACK_WAIT;
        end

        S_CURR_STACK_WAIT: begin
          if (update_ready_i)
            entry_status_q[meta_rd_ptr_q] <= S_CURR_STATUS_WRITE;
        end

        S_CURR_STATUS_WRITE: begin
          entry_status_q[meta_rd_ptr_q] <= S_DONE;
        end

        S_DONE: begin
          if (fire_eblock_i) begin
            entry_status_q[meta_rd_ptr_q] <= S_EMPTY;
            meta_rd_ptr_q                  <= meta_rd_ptr_q ^ 1'b1;
          end
        end

        default: ;

      endcase

      // ------------------------------------------------------------------
      // Write block: capture new metadata on rising edge of branch_meta_valid_i
      // (higher priority — runs after case block)
      // ------------------------------------------------------------------
      if (branch_meta_valid_rise) begin
        meta_table_q        [meta_wr_ptr_q] <= branch_meta_i;
        entry_pc_q          [meta_wr_ptr_q] <= pc_i;
        entry_is_prefetch_q [meta_wr_ptr_q] <= is_prefetch_i;
        entry_status_q      [meta_wr_ptr_q] <= S_STORED;
        meta_wr_ptr_q                       <= meta_wr_ptr_q ^ 1'b1;
      end

    end
  end

endmodule
