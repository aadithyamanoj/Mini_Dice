module simt_stack_controller
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // ============== BRANCH HANDLER ==============
    input logic [DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_id_i,
    input cta_size_e hw_cta_size_i,  // CTA_SIZE_1/2/4

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
    input logic [DICE_HW_CTA_ID_WIDTH-1:0] init_hw_cta_id_i,
    input cta_size_e init_hw_cta_size_i,
    input logic [DICE_ADDR_WIDTH-1:0] init_pc_i,
    input logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_i,
    output logic init_ready_o,

    // ============== STACK TOP ==============
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_top_valid_o,
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][DICE_ADDR_WIDTH-1:0] stack_top_next_pc_o,
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_o,
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0][DICE_NUM_MAX_THREADS_PER_CORE/DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_top_active_mask_o,

    // ============== STACK STATUS ==============
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_empty_o,
    output logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_full_o
);

  // ===========================================================================
  // LOCAL PARAMETERS AND TYPES
  // ===========================================================================

  localparam int THREAD_WIDTH = DICE_NUM_MAX_THREADS_PER_CORE / DICE_NUM_MAX_CTA_PER_CORE;

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

  // CTA configuration registers
  logic [$clog2(DICE_NUM_MAX_CTA_PER_CORE)-1:0] hw_cta_id_q;
  cta_size_e hw_cta_size_q;

  // Number of stacks this CTA spans = cta_size_encoding + 1
  // Encoding: 00→1, 01→2, 11→4
  // Used to select stacks [hw_cta_id_q : hw_cta_id_q + num_active_stacks - 1]
  logic [2:0] num_active_stacks;

  // Effective thread width = THREAD_WIDTH * num_active_stacks
  // Max value = DICE_NUM_MAX_THREADS_PER_CORE, needs DICE_TID_WIDTH+1 bits
  logic [DICE_TID_WIDTH:0] effective_thread_width;

  // Captured input registers - from branch handler
  logic update_with_divergence_q;
  logic [DICE_ADDR_WIDTH-1:0] update_next_pc_q;
  thread_mask_t predicate_regs_value_q;
  logic [DICE_ADDR_WIDTH-1:0] branch_not_taken_pc_q;
  logic [DICE_ADDR_WIDTH-1:0] branch_reconvergence_pc_q;

  // Captured input registers - from CTA controller (init)
  logic [DICE_ADDR_WIDTH-1:0] init_pc_q;
  logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_q;

  // Per-stack control signals
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_push;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_modify_top;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_pop;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_read_top;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_out_valid;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_empty_individual;
  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0] stack_full_individual;

  // Per-stack data signals
  logic [DICE_ADDR_WIDTH-1:0] stack_push_next_pc[DICE_NUM_MAX_CTA_PER_CORE];
  logic [DICE_ADDR_WIDTH-1:0] stack_push_reconvergence_pc[DICE_NUM_MAX_CTA_PER_CORE];
  logic [THREAD_WIDTH-1:0]     stack_push_active_mask[DICE_NUM_MAX_CTA_PER_CORE];
  logic [DICE_ADDR_WIDTH-1:0] stack_top_next_pc_int[DICE_NUM_MAX_CTA_PER_CORE];
  logic [DICE_ADDR_WIDTH-1:0] stack_top_reconvergence_pc_int[DICE_NUM_MAX_CTA_PER_CORE];
  logic [THREAD_WIDTH-1:0]     stack_top_active_mask_int[DICE_NUM_MAX_CTA_PER_CORE];

  // Combined stack output signals
  logic                       combined_stack_out_valid;
  logic [DICE_ADDR_WIDTH-1:0] combined_stack_top_next_pc;
  logic [DICE_ADDR_WIDTH-1:0] combined_stack_top_reconvergence_pc;
  thread_mask_t               combined_stack_top_active_mask;

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

  assign num_active_stacks = 3'(hw_cta_size_q) + 3'd1;
  assign effective_thread_width = (DICE_TID_WIDTH+1)'(THREAD_WIDTH) * (DICE_TID_WIDTH+1)'(num_active_stacks);

  // Output status signals - direct pass-through
  assign stack_empty_o = stack_empty_individual;
  assign stack_full_o = stack_full_individual;

  // Handshake ready signals
  assign update_ready_o = (current_state_q == StateIdle) && (init_valid_i == 1'b0);
  assign init_ready_o = (current_state_q == StateIdle);

  // ===========================================================================
  // SIMT STACK INSTANTIATION
  // ===========================================================================

  genvar i;
  generate
    for (i = 0; i < DICE_NUM_MAX_CTA_PER_CORE; i++) begin : gen_stacks
      simt_stack stack_inst (
          .clk_i                  (clk_i),
          .rst_i                  (rst_i),
          .push_i                 (stack_push[i]),
          .modify_top_i           (stack_modify_top[i]),
          .push_next_pc_i         (stack_push_next_pc[i]),
          .push_reconvergence_pc_i(stack_push_reconvergence_pc[i]),
          .push_active_mask_i     (stack_push_active_mask[i]),
          .pop_i                  (stack_pop[i]),
          .read_top_i             (stack_read_top[i]),
          .top_next_pc_o          (stack_top_next_pc_int[i]),
          .top_reconvergence_pc_o (stack_top_reconvergence_pc_int[i]),
          .top_active_mask_o      (stack_top_active_mask_int[i]),
          .out_valid_o            (stack_out_valid[i]),
          .stack_empty_o          (stack_empty_individual[i]),
          .stack_full_o           (stack_full_individual[i])
      );
    end
  endgenerate

  // ===========================================================================
  // HELPER FUNCTIONS
  // ===========================================================================

  // Extract effective mask based on CTA size
  // Operates on the COMBINED mask already aggregated from stacks [hw_cta_id : hw_cta_id + n]
  function automatic thread_mask_t get_effective_mask(input cta_size_e cta_size,
                                                      input thread_mask_t full_mask);
    case (cta_size)
      CTA_SIZE_1:
      return {{(DICE_NUM_MAX_CTA_PER_CORE - 1) * THREAD_WIDTH{1'b0}}, full_mask[THREAD_WIDTH-1:0]};
      CTA_SIZE_2:
      return {{(DICE_NUM_MAX_CTA_PER_CORE - 2) * THREAD_WIDTH{1'b0}}, full_mask[2*THREAD_WIDTH-1:0]};
      CTA_SIZE_4: return full_mask;
      default:
      return {{(DICE_NUM_MAX_CTA_PER_CORE - 1) * THREAD_WIDTH{1'b0}}, full_mask[THREAD_WIDTH-1:0]};
    endcase
  endfunction

  // Check if a stack index is part of the current CTA's allocation
  // Returns true if stack_idx is within [hw_cta_id_q, hw_cta_id_q + num_active_stacks)
  function automatic logic is_active_stack(input int stack_idx);
    return (stack_idx >= hw_cta_id_q) && (stack_idx < (hw_cta_id_q + num_active_stacks));
  endfunction

  // Compute the new top PC based on divergence state
  // Accesses module-level signals: update_with_divergence_q, update_next_pc_q,
  // branch_not_taken_pc_q, all_taken, all_not_taken
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
  // COMBINATIONAL LOGIC: STACK OUTPUT COMBINING
  // ===========================================================================

  // Combine outputs from active stacks for multi-CTA configurations
  always_comb begin
    logic all_active_valid;
    int   mask_offset;
    mask_offset = 0;
    combined_stack_out_valid = 1'b0;
    combined_stack_top_next_pc = '0;
    combined_stack_top_reconvergence_pc = '0;
    combined_stack_top_active_mask = '0;

    // Check if all active stacks have valid output
    all_active_valid = 1'b1;
    for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
      if (j >= hw_cta_id_q && j < (hw_cta_id_q + num_active_stacks)) begin
        all_active_valid &= stack_out_valid[j];
      end
    end

    if (all_active_valid == 1'b1) begin
      combined_stack_out_valid = 1'b1;
      // Use the PC from the first active stack (they should all be the same for valid operations)
      combined_stack_top_next_pc = stack_top_next_pc_int[hw_cta_id_q];
      combined_stack_top_reconvergence_pc = stack_top_reconvergence_pc_int[hw_cta_id_q];

      // Combine active masks from all active stacks
      for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
        if (j >= hw_cta_id_q && j < (hw_cta_id_q + num_active_stacks)) begin
          mask_offset = (j - hw_cta_id_q) * THREAD_WIDTH;
          combined_stack_top_active_mask[mask_offset+:THREAD_WIDTH] = stack_top_active_mask_int[j];
        end else begin
          mask_offset = j * THREAD_WIDTH;
          combined_stack_top_active_mask[mask_offset+:THREAD_WIDTH] = '0;
        end
      end
    end
  end

  // Extract effective active mask based on CTA size
  assign effective_active_mask = get_effective_mask(hw_cta_size_q, combined_stack_top_active_mask); //this may bne

  // ===========================================================================
  // COMBINATIONAL LOGIC: DIVERGENCE ANALYSIS
  // ===========================================================================

  // Compute taken/not-taken masks and divergence flags
  always_comb begin
    thread_mask_t effective_predicate;

    // Extract effective predicate based on CTA size
    effective_predicate = get_effective_mask(hw_cta_size_q, predicate_regs_value_q);

    taken_active_mask = effective_active_mask & effective_predicate;
    not_taken_active_mask = effective_active_mask & ~effective_predicate;
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
      combined_stack_top_reconvergence_pc,
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

    if ((current_state_q == StateReadTop) && (combined_stack_out_valid == 1'b1)) begin
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

    if ((current_state_q == StateReadTop) && (combined_stack_out_valid == 1'b1)) begin
      case (current_div_case)
        DIV_MODIFY_ONLY: begin
          new_top_entry_next.pc = compute_new_top_pc();
          new_top_entry_next.reconvergence_pc = combined_stack_top_reconvergence_pc;
          new_top_entry_next.active_mask = effective_active_mask;
        end
        DIV_PUSH_ONE: begin
          // Modify top to reconvergence point, push not-taken path
          new_top_entry_next.pc = branch_reconvergence_pc_q;
          new_top_entry_next.reconvergence_pc = combined_stack_top_reconvergence_pc;
          new_top_entry_next.active_mask = effective_active_mask;
          push_entry_1_next.pc = branch_not_taken_pc_q;
          push_entry_1_next.reconvergence_pc = branch_reconvergence_pc_q;
          push_entry_1_next.active_mask = not_taken_active_mask;
        end
        DIV_PUSH_TWO: begin
          // Modify top to reconvergence point, push both paths
          new_top_entry_next.pc = branch_reconvergence_pc_q;
          new_top_entry_next.reconvergence_pc = combined_stack_top_reconvergence_pc;
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
  // COMBINATIONAL LOGIC: STACK SIGNAL DISTRIBUTION
  // ===========================================================================

  // Distribute control signals to individual stacks based on active configuration
  always_comb begin
    int mask_offset;
    mask_offset = 0;

    // Initialize all stacks to inactive
    for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
      stack_push[j] = 1'b0;
      stack_modify_top[j] = 1'b0;
      stack_pop[j] = 1'b0;
      stack_read_top[j] = 1'b0;
      stack_push_next_pc[j] = '0;
      stack_push_reconvergence_pc[j] = '0;
      stack_push_active_mask[j] = '0;
    end

    // Always read from all stacks to keep outputs valid
    for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
      stack_read_top[j] = 1'b1;
    end

    // Activate only the stacks in the current CTA for operations
    for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
      if (is_active_stack(j)) begin
        case (current_state_q)
          StateModifyTop: begin
            stack_push[j] = 1'b1;
            stack_modify_top[j] = 1'b1;
            stack_push_next_pc[j] = new_top_entry_q.pc;
            stack_push_reconvergence_pc[j] = new_top_entry_q.reconvergence_pc;
            // Distribute active mask across stacks
            mask_offset = (j - hw_cta_id_q) * THREAD_WIDTH;
            stack_push_active_mask[j] = new_top_entry_q.active_mask[mask_offset+:THREAD_WIDTH];
          end

          StatePushFirst: begin
            stack_push[j] = 1'b1;
            stack_push_next_pc[j] = push_entry_1_q.pc;
            stack_push_reconvergence_pc[j] = push_entry_1_q.reconvergence_pc;
            // Distribute active mask across stacks
            mask_offset = (j - hw_cta_id_q) * THREAD_WIDTH;
            stack_push_active_mask[j] = push_entry_1_q.active_mask[mask_offset+:THREAD_WIDTH];
          end

          StatePushSecond: begin
            stack_push[j] = 1'b1;
            stack_push_next_pc[j] = push_entry_2_q.pc;
            stack_push_reconvergence_pc[j] = push_entry_2_q.reconvergence_pc;
            // Distribute active mask across stacks
            mask_offset = (j - hw_cta_id_q) * THREAD_WIDTH;
            stack_push_active_mask[j] = push_entry_2_q.active_mask[mask_offset+:THREAD_WIDTH];
          end

          StatePopStack: begin
            stack_pop[j] = 1'b1;
          end

          StateInitPush: begin
            stack_push[j] = 1'b1;
            stack_modify_top[j] = 1'b0;
            stack_push_next_pc[j] = init_pc_q;
            stack_push_reconvergence_pc[j] = init_reconvergence_pc_q;
            stack_push_active_mask[j] = '1;  // All threads active
          end
          default: ;
        endcase
      end
    end
  end

  // ===========================================================================
  // COMBINATIONAL LOGIC: OUTPUT ASSIGNMENTS
  // ===========================================================================

  // Convert unpacked arrays to packed arrays for outputs
  // stack_top_valid is always available when stack has data (not dependent on state)
  always_comb begin
    for (int j = 0; j < DICE_NUM_MAX_CTA_PER_CORE; j++) begin
      stack_top_valid_o[j] = stack_out_valid[j] && (stack_empty_individual[j] == 1'b0);
      stack_top_next_pc_o[j] = stack_top_next_pc_int[j];
      stack_top_reconvergence_pc_o[j] = stack_top_reconvergence_pc_int[j];
      stack_top_active_mask_o[j] = stack_top_active_mask_int[j];
    end
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
        if (combined_stack_out_valid == 1'b1) begin
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
        if ((combined_stack_out_valid == 1'b1) || (stack_empty_o != '0)) begin
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

      // CTA configuration
      hw_cta_id_q <= '0;
      hw_cta_size_q <= CTA_SIZE_1;

      // Captured inputs - branch handler
      update_with_divergence_q <= 1'b0;
      update_next_pc_q <= '0;
      predicate_regs_value_q <= '0;
      branch_not_taken_pc_q <= '0;
      branch_reconvergence_pc_q <= '0;

      // Captured inputs - CTA controller
      init_pc_q <= '0;
      init_reconvergence_pc_q <= '0;

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
        init_pc_q <= init_pc_i;
        init_reconvergence_pc_q <= init_reconvergence_pc_i;
        hw_cta_id_q <= init_hw_cta_id_i;
        hw_cta_size_q <= init_hw_cta_size_i;

      end else if ((current_state_q == StateIdle) && (update_valid_i == 1'b1)) begin
        update_with_divergence_q <= update_with_divergence_i;
        update_next_pc_q <= update_next_pc_i;
        predicate_regs_value_q <= predicate_regs_value_i;
        branch_not_taken_pc_q <= branch_not_taken_pc_i;
        branch_reconvergence_pc_q <= branch_reconvergence_pc_i;
        hw_cta_id_q <= hw_cta_id_i;
        hw_cta_size_q <= hw_cta_size_i;
      end

      // -------- Register Computed Divergence Values --------
      if ((current_state_q == StateReadTop) && (combined_stack_out_valid == 1'b1)) begin
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

  // ===========================================================================
  // DEBUG ASSERTIONS
  // ===========================================================================

`ifndef SYNTHESIS
  always @(posedge clk_i) begin
    if (rst_i == 1'b0) begin
      if ((update_valid_i == 1'b1) && (update_ready_o == 1'b1) &&
          (hw_cta_id_i + hw_cta_size_i >= DICE_NUM_MAX_CTA_PER_CORE)) begin
        $error(
            "SIMT Stack Controller: CTA configuration exceeds available stacks " + "(hw_cta_id=%0d, hw_cta_size=%0d, max=%0d)",
            hw_cta_id_i, hw_cta_size_i, DICE_NUM_MAX_CTA_PER_CORE);
      end

      if ((init_valid_i == 1'b1) && (init_ready_o == 1'b1) &&
          (init_hw_cta_id_i + init_hw_cta_size_i >= DICE_NUM_MAX_CTA_PER_CORE)) begin
        $error(
            "SIMT Stack Controller: Init CTA configuration exceeds available stacks " + "(init_hw_cta_id=%0d, init_hw_cta_size=%0d, max=%0d)",
            init_hw_cta_id_i, init_hw_cta_size_i, DICE_NUM_MAX_CTA_PER_CORE);
      end

      // Debug state transitions and operations
      if (current_state_q != next_state) begin
        $display("SIMT Controller: State %0s -> %0s", current_state_q.name(), next_state.name());
      end

      // Debug operation decisions in StateReadTop
      if ((current_state_q == StateReadTop) && (combined_stack_out_valid == 1'b1)) begin
        $display("SIMT Controller: StateReadTop analysis - pop=%b, modify=%b, push1=%b, push2=%b",
                 need_pop_next, need_modify_top_next, need_push_first_next, need_push_second_next);
        if (need_modify_top_next == 1'b1) begin
          $display(
              "SIMT Controller: Will use new_top_pc=0x%h in next cycle",
              (update_with_divergence_q == 1'b0) ? update_next_pc_q : (all_taken == 1'b1) ? update_next_pc_q : (all_not_taken == 1'b1) ? branch_not_taken_pc_q : branch_reconvergence_pc_q);
        end
      end
    end
  end
`endif

endmodule
