module simt_stack_controller
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // ============== BRANCH HANDLER ==============
    // Update request interface (valid/ready handshake) - BRANCH HANDLER
    input logic update_valid_i,
    input logic update_with_divergence_i,  // 0 = no divergence, 1 = with divergence
    input logic [DICE_ADDR_WIDTH-1:0] update_next_pc_i,  // No divergence: next PC

    // Divergence case inputs (only used when update_with_divergence = 1)
    input thread_mask_t predicate_regs_value_i,
    input logic [DICE_ADDR_WIDTH-1:0] branch_not_taken_pc_i,
    input logic [DICE_ADDR_WIDTH-1:0] branch_reconvergence_pc_i,
    output logic update_ready_o,

    // ============== CTA CONTROLLER ==============
    input logic init_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0] init_pc_i,
    input logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_i,
    input logic [DICE_TID_WIDTH:0] init_thread_count_i,
    output logic init_ready_o,

    // ============== STACK TOP ==============
    output logic stack_top_valid_o,
    output logic [DICE_ADDR_WIDTH-1:0] stack_top_next_pc_o,
    output logic [DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_o,
    output thread_mask_t stack_top_active_mask_o,

    // ============== STACK STATUS ==============
    output logic stack_empty_o,
    output logic stack_full_o,
    output logic [SIMT_STACK_ENTRY_COUNT_WIDTH-1:0] stack_entry_count_o
);

  // ===========================================================================
  // LOCAL PARAMETERS AND TYPES
  // ===========================================================================

  // FSM States
  typedef enum logic [2:0] {
    StateIdle,
    StateReadTop,
    StateModifyTop,
    StatePushFirst,
    StatePushSecond,
    StatePopStack,
    StateInitPush,
    StateFinalRead
  } state_e;

  // Divergence Case Classification
  // Classifies branch divergence into one of 5 cases for stack operations
  typedef enum logic [2:0] {
    DIV_NONE,         // No operation needed
    DIV_POP,          // Pop stack (reached reconvergence point)
    DIV_MODIFY_ONLY,  // Update top PC only
    DIV_PUSH_ONE,     // Modify top + push 1 entry
    DIV_PUSH_TWO      // Modify top + push 2 entries (full divergence)
  } divergence_case_e;

  // ===========================================================================
  // INTERNAL SIGNAL DECLARATIONS
  // ===========================================================================

  // FSM state registers
  state_e current_state_q, next_state;

  // Captured input registers - from branch handler
  logic update_with_divergence_q;
  logic [DICE_ADDR_WIDTH-1:0] update_next_pc_q;
  thread_mask_t predicate_regs_value_q;
  logic [DICE_ADDR_WIDTH-1:0] branch_not_taken_pc_q;
  logic [DICE_ADDR_WIDTH-1:0] branch_reconvergence_pc_q;

  // Captured input registers - from CTA controller (init)
  logic [DICE_ADDR_WIDTH-1:0] init_pc_q;
  logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_q;
  logic [DICE_TID_WIDTH:0]    init_thread_count_q;

  // Stack control signals
  logic stack_push;
  logic stack_modify_top;
  logic stack_pop;
  logic stack_read_top;
  logic stack_out_valid;

  // Stack data signals
  logic [DICE_ADDR_WIDTH-1:0] stack_push_next_pc;
  logic [DICE_ADDR_WIDTH-1:0] stack_push_reconvergence_pc;
  thread_mask_t               stack_push_active_mask;
  logic [DICE_ADDR_WIDTH-1:0] stack_top_next_pc_int;
  logic [DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_int;
  thread_mask_t               stack_top_active_mask_int;

  // Divergence analysis signals
  thread_mask_t taken_active_mask;
  thread_mask_t not_taken_active_mask;
  thread_mask_t effective_active_mask;
  logic all_taken, all_not_taken, has_divergence;
  divergence_case_e current_div_case;

  // Operation control signals - combinational
  logic need_pop_next, need_modify_top_next, need_push_first_next, need_push_second_next;

  // Operation control signals - registered
  logic need_pop_q, need_modify_top_q, need_push_first_q, need_push_second_q;

  // Stack entry signals - combinational (computed in always_comb)
  stack_entry_t new_top_entry_next;
  stack_entry_t push_entry_1_next;
  stack_entry_t push_entry_2_next;

  // Stack entry signals - registered
  stack_entry_t new_top_entry_q;
  stack_entry_t push_entry_1_q;
  stack_entry_t push_entry_2_q;

  // ===========================================================================
  // DERIVED SIGNAL ASSIGNMENTS
  // ===========================================================================

  logic stack_empty_internal;
  logic stack_full_internal;
  logic [SIMT_STACK_ENTRY_COUNT_WIDTH-1:0] stack_entry_count_internal;

  // Output status signals - direct pass-through from single stack
  assign stack_empty_o = stack_empty_internal;
  assign stack_full_o = stack_full_internal;
  assign stack_entry_count_o = stack_entry_count_internal;

  // Output data signals - direct pass-through from single stack
  assign stack_top_valid_o = stack_out_valid && !stack_empty_internal;
  assign stack_top_next_pc_o = stack_top_next_pc_int;
  assign stack_top_reconvergence_pc_o = stack_top_reconvergence_pc_int;
  assign stack_top_active_mask_o = stack_top_active_mask_int;

  // Handshake ready signals
  assign update_ready_o = (current_state_q == StateIdle) && (init_valid_i == 1'b0);
  assign init_ready_o = (current_state_q == StateIdle);

  // With 1 CTA, the effective active mask is just the stack top active mask
  assign effective_active_mask = stack_top_active_mask_int;

  // ===========================================================================
  // SIMT STACK INSTANTIATION
  // ===========================================================================

  simt_stack stack_inst (
      .clk_i                  (clk_i),
      .rst_i                  (rst_i),
      .push_i                 (stack_push),
      .modify_top_i           (stack_modify_top),
      .push_next_pc_i         (stack_push_next_pc),
      .push_reconvergence_pc_i(stack_push_reconvergence_pc),
      .push_active_mask_i     (stack_push_active_mask),
      .pop_i                  (stack_pop),
      .read_top_i             (stack_read_top),
      .top_next_pc_o          (stack_top_next_pc_int),
      .top_reconvergence_pc_o (stack_top_reconvergence_pc_int),
      .top_active_mask_o      (stack_top_active_mask_int),
      .out_valid_o            (stack_out_valid),
      .stack_empty_o          (stack_empty_internal),
      .stack_full_o           (stack_full_internal),
      .stack_entry_count_o    (stack_entry_count_internal)
  );

  // ===========================================================================
  // HELPER FUNCTIONS
  // ===========================================================================

  // Compute the new top PC based on divergence state
  function automatic logic [DICE_ADDR_WIDTH-1:0] compute_new_top_pc();
    if (!update_with_divergence_q || all_taken) return update_next_pc_q;
    else if (all_not_taken) return branch_not_taken_pc_q;
    else return branch_reconvergence_pc_q;
  endfunction

  // ============================================================
  // DIVERGENCE DECISION TABLE
  // ============================================================
  // with_div | all_taken | all_not | has_div | Condition              | Result
  // ---------|-----------|---------|---------|------------------------|--------
  // 0        | -         | -       | -       | next == stack_reconv   | POP
  // 0        | -         | -       | -       | next != stack_reconv   | MODIFY
  // 1        | 1         | 0       | 0       | taken == stack_reconv  | POP
  // 1        | 1         | 0       | 0       | taken != stack_reconv  | MODIFY
  // 1        | 0         | 1       | 0       | not_taken==stack_reconv| POP
  // 1        | 0         | 1       | 0       | not_taken!=stack_reconv| MODIFY
  // 1        | 0         | 0       | 1       | 3 distinct PCs         | PUSH_TWO
  // 1        | 0         | 0       | 1       | taken == reconv        | PUSH_ONE
  // 1        | 0         | 0       | 1       | otherwise              | MODIFY
  // ============================================================

  function automatic divergence_case_e classify_divergence(
      input logic with_divergence, input logic [DICE_ADDR_WIDTH-1:0] next_pc,
      input logic [DICE_ADDR_WIDTH-1:0] not_taken_pc, input logic [DICE_ADDR_WIDTH-1:0] reconv_pc,
      input logic [DICE_ADDR_WIDTH-1:0] stack_reconv_pc, input logic in_all_taken,
      input logic in_all_not_taken, input logic in_has_divergence);
    logic reached_reconvergence;
    logic three_distinct_pcs;
    logic taken_equals_reconv;

    // No divergence flag set
    if (!with_divergence) begin
      reached_reconvergence = (next_pc == stack_reconv_pc);
      if (reached_reconvergence) return DIV_POP;
      else return DIV_MODIFY_ONLY;
    end

    // All threads take branch
    if (in_all_taken) begin
      reached_reconvergence = (next_pc == stack_reconv_pc);
      if (reached_reconvergence) return DIV_POP;
      else return DIV_MODIFY_ONLY;
    end

    // All threads don't take branch
    if (in_all_not_taken) begin
      reached_reconvergence = (not_taken_pc == stack_reconv_pc);
      if (reached_reconvergence) return DIV_POP;
      else return DIV_MODIFY_ONLY;
    end

    // Real divergence - threads split
    if (in_has_divergence) begin
      three_distinct_pcs = (next_pc != reconv_pc) &&
                           (not_taken_pc != reconv_pc) &&
                           (reconv_pc != stack_reconv_pc);
      if (three_distinct_pcs) return DIV_PUSH_TWO;

      taken_equals_reconv = (next_pc == reconv_pc) && (reconv_pc != stack_reconv_pc);
      if (taken_equals_reconv) return DIV_PUSH_ONE;

      return DIV_MODIFY_ONLY;
    end

    return DIV_NONE;
  endfunction

  // ===========================================================================
  // COMBINATIONAL LOGIC: DIVERGENCE ANALYSIS
  // ===========================================================================

  // Compute taken/not-taken masks and divergence flags
  always_comb begin
    taken_active_mask = effective_active_mask & predicate_regs_value_q;
    not_taken_active_mask = effective_active_mask & ~predicate_regs_value_q;
    all_taken = (taken_active_mask == effective_active_mask) && (effective_active_mask != '0);
    all_not_taken = (not_taken_active_mask == effective_active_mask) &&
                    (effective_active_mask != '0);
    has_divergence = (all_taken == 1'b0) && (all_not_taken == 1'b0) &&
                     (effective_active_mask != '0);
  end

  // Classify divergence case using helper function
  always_comb begin
    current_div_case = classify_divergence(
      update_with_divergence_q,
      update_next_pc_q,
      branch_not_taken_pc_q,
      branch_reconvergence_pc_q,
      stack_top_reconvergence_pc_int,
      all_taken,
      all_not_taken,
      has_divergence
    );
  end

  // ===========================================================================
  // COMBINATIONAL LOGIC: OPERATION DECISION
  // ===========================================================================

  // Determine which stack operations are needed based on divergence case
  always_comb begin
    // Default values
    need_pop_next = 1'b0;
    need_modify_top_next = 1'b0;
    need_push_first_next = 1'b0;
    need_push_second_next = 1'b0;

    if ((current_state_q == StateReadTop) && (stack_out_valid == 1'b1)) begin
      case (current_div_case)
        DIV_POP: begin
          need_pop_next = 1'b1;
        end
        DIV_MODIFY_ONLY: begin
          need_modify_top_next = 1'b1;
        end
        DIV_PUSH_ONE: begin
          need_modify_top_next = 1'b1;
          need_push_first_next = 1'b1;
        end
        DIV_PUSH_TWO: begin
          need_modify_top_next  = 1'b1;
          need_push_first_next  = 1'b1;
          need_push_second_next = 1'b1;
        end
        default: ;  // DIV_NONE - no operation
      endcase
    end
  end

  // ===========================================================================
  // COMBINATIONAL LOGIC: DIVERGENCE ENTRY COMPUTATION
  // ===========================================================================

  // Compute new_top_entry_next, push_entry_1_next, push_entry_2_next based on
  // divergence case. These values are registered in always_ff when state allows.
  always_comb begin
    // -------- Default Values --------
    new_top_entry_next = '0;
    push_entry_1_next  = '0;
    push_entry_2_next  = '0;

    if ((current_state_q == StateReadTop) && (stack_out_valid == 1'b1)) begin
      case (current_div_case)
        DIV_MODIFY_ONLY: begin
          new_top_entry_next.pc = compute_new_top_pc();
          new_top_entry_next.reconvergence_pc = stack_top_reconvergence_pc_int;
          new_top_entry_next.active_mask = effective_active_mask;
        end
        DIV_PUSH_ONE: begin
          // Modify top to reconvergence point, push not-taken path
          new_top_entry_next.pc = branch_reconvergence_pc_q;
          new_top_entry_next.reconvergence_pc = stack_top_reconvergence_pc_int;
          new_top_entry_next.active_mask = effective_active_mask;
          push_entry_1_next.pc = branch_not_taken_pc_q;
          push_entry_1_next.reconvergence_pc = branch_reconvergence_pc_q;
          push_entry_1_next.active_mask = not_taken_active_mask;
        end
        DIV_PUSH_TWO: begin
          // Modify top to reconvergence point, push both paths
          new_top_entry_next.pc = branch_reconvergence_pc_q;
          new_top_entry_next.reconvergence_pc = stack_top_reconvergence_pc_int;
          new_top_entry_next.active_mask = effective_active_mask;
          push_entry_1_next.pc = update_next_pc_q;  // taken target
          push_entry_1_next.reconvergence_pc = branch_reconvergence_pc_q;
          push_entry_1_next.active_mask = taken_active_mask;
          push_entry_2_next.pc = branch_not_taken_pc_q;
          push_entry_2_next.reconvergence_pc = branch_reconvergence_pc_q;
          push_entry_2_next.active_mask = not_taken_active_mask;
        end
        default: ;  // DIV_POP, DIV_NONE - no entry modification
      endcase
    end
  end

  // ===========================================================================
  // COMBINATIONAL LOGIC: STACK SIGNAL DRIVE
  // ===========================================================================

  // Drive control and data signals to the single stack based on FSM state
  always_comb begin
    // Defaults
    stack_push = 1'b0;
    stack_modify_top = 1'b0;
    stack_pop = 1'b0;
    stack_read_top = 1'b1;  // Always read to keep top valid
    stack_push_next_pc = '0;
    stack_push_reconvergence_pc = '0;
    stack_push_active_mask = '0;

    case (current_state_q)
      StateModifyTop: begin
        stack_push = 1'b1;
        stack_modify_top = 1'b1;
        stack_push_next_pc = new_top_entry_q.pc;
        stack_push_reconvergence_pc = new_top_entry_q.reconvergence_pc;
        stack_push_active_mask = new_top_entry_q.active_mask;
      end

      StatePushFirst: begin
        stack_push = 1'b1;
        stack_push_next_pc = push_entry_1_q.pc;
        stack_push_reconvergence_pc = push_entry_1_q.reconvergence_pc;
        stack_push_active_mask = push_entry_1_q.active_mask;
      end

      StatePushSecond: begin
        stack_push = 1'b1;
        stack_push_next_pc = push_entry_2_q.pc;
        stack_push_reconvergence_pc = push_entry_2_q.reconvergence_pc;
        stack_push_active_mask = push_entry_2_q.active_mask;
      end

      StatePopStack: begin
        stack_pop = 1'b1;
      end

      StateInitPush: begin
        stack_push = 1'b1;
        stack_push_next_pc = init_pc_q;
        stack_push_reconvergence_pc = init_reconvergence_pc_q;
        stack_push_active_mask = thread_mask_t'(
            {1'b0, {SIMT_STACK_THREAD_WIDTH{1'b1}}}
            >> (SIMT_STACK_THREAD_WIDTH - init_thread_count_q)
        );
      end

      default: ;
    endcase
  end

  // ===========================================================================
  // FSM NEXT STATE LOGIC
  // ===========================================================================

  always_comb begin
    next_state = current_state_q;

    case (current_state_q)
      StateIdle: begin
        if (init_valid_i == 1'b1) begin
          next_state = StateInitPush;
        end else if (update_valid_i == 1'b1) begin
          next_state = StateReadTop;
        end
      end

      StateReadTop: begin
        if (stack_out_valid == 1'b1) begin
          if (need_pop_next == 1'b1) begin
            next_state = StatePopStack;
          end else if (need_modify_top_next == 1'b1) begin
            next_state = StateModifyTop;
          end else if (need_push_first_next == 1'b1) begin
            next_state = StatePushFirst;
          end else begin
            next_state = StateIdle;  // No operation needed
          end
        end
      end

      StateModifyTop: begin
        if (need_push_first_q == 1'b1) begin
          next_state = StatePushFirst;
        end else begin
          next_state = StateFinalRead;
        end
      end

      StatePushFirst: begin
        if (need_push_second_q == 1'b1) begin
          next_state = StatePushSecond;
        end else begin
          next_state = StateFinalRead;
        end
      end

      StatePushSecond: begin
        next_state = StateFinalRead;
      end

      StatePopStack: begin
        next_state = StateFinalRead;
      end

      StateInitPush: begin
        next_state = StateFinalRead;
      end

      StateFinalRead: begin
        if ((stack_out_valid == 1'b1) || (stack_empty_o == 1'b1)) begin
          next_state = StateIdle;
        end
      end

      default: begin
        next_state = StateIdle;
      end
    endcase
  end

  // ===========================================================================
  // SEQUENTIAL LOGIC
  // ===========================================================================

  always_ff @(posedge clk_i) begin
    if (rst_i == 1'b1) begin
      // -------- Reset All Registers --------
      // FSM state
      current_state_q <= StateIdle;

      // Captured inputs - branch handler
      update_with_divergence_q <= 1'b0;
      update_next_pc_q <= '0;
      predicate_regs_value_q <= '0;
      branch_not_taken_pc_q <= '0;
      branch_reconvergence_pc_q <= '0;

      // Captured inputs - CTA controller
      init_pc_q           <= '0;
      init_reconvergence_pc_q <= '0;
      init_thread_count_q <= '0;

      // Operation control registers
      need_pop_q <= 1'b0;
      need_modify_top_q <= 1'b0;
      need_push_first_q <= 1'b0;
      need_push_second_q <= 1'b0;

      // Stack entry registers
      new_top_entry_q <= '0;
      push_entry_1_q <= '0;
      push_entry_2_q <= '0;

    end else begin
      // -------- State Transition --------
      current_state_q <= next_state;

      // -------- Input Capture (Init Priority) --------
      if ((current_state_q == StateIdle) && (init_valid_i == 1'b1)) begin
        init_pc_q               <= init_pc_i;
        init_reconvergence_pc_q <= init_reconvergence_pc_i;
        init_thread_count_q     <= init_thread_count_i;

      end else if ((current_state_q == StateIdle) && (update_valid_i == 1'b1)) begin
        update_with_divergence_q <= update_with_divergence_i;
        update_next_pc_q <= update_next_pc_i;
        predicate_regs_value_q <= predicate_regs_value_i;
        branch_not_taken_pc_q <= branch_not_taken_pc_i;
        branch_reconvergence_pc_q <= branch_reconvergence_pc_i;
      end

      // -------- Register Computed Divergence Values --------
      if ((current_state_q == StateReadTop) && (stack_out_valid == 1'b1)) begin
        // Capture operation flags
        need_pop_q <= need_pop_next;
        need_modify_top_q <= need_modify_top_next;
        need_push_first_q <= need_push_first_next;
        need_push_second_q <= need_push_second_next;

        // Register computed entry values from always_comb
        new_top_entry_q <= new_top_entry_next;
        push_entry_1_q <= push_entry_1_next;
        push_entry_2_q <= push_entry_2_next;
      end
    end
  end

endmodule
