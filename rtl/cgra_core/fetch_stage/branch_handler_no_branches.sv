// DUMMY BRANCH HANDLER THAT DOESN'T ALLOW BRANCHES

/*
NOTES:

-NO BRANCHES
-NO PREFETCHES
-MASK IS ALWAYS CORRECT
-WILL NEVER FLUSH
*/

module branch_handler_no_branches
  import dice_frontend_pkg::*;
  import dice_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Valid Check
    // input logic fire_eblock_i,

    // Status table
    output branch_predict_interface_t branch_predict_info_o,

    // Decode
    input branch_meta_t branch_meta_i,
    input logic branch_meta_valid_i, // stays valid for many cycles
    output thread_mask_t real_active_thread_mask_o,


    // CS -> FDR Stage buffer
    input thread_mask_t cs_active_mask_i,
    input logic [DICE_ADDR_WIDTH-1:0] pc_i,


    // SIMT Stacks
    output logic update_valid_o,
    input logic update_ready_i,
    output simt_stack_update_t simt_stack_update_o
);

  //--- Rising edge detection for branch_meta_valid_i ---
  logic branch_meta_valid_rise;
  logic update_stack_fire;

  rising_edge_detector u_branch_meta_valid_rise (
      .clk_i  (clk_i),
      .rst_i  (rst_i),
      .sig_i  (branch_meta_valid_i),
      .rise_o (branch_meta_valid_rise)
  );

  // No prefetching so this is always true
 assign real_active_thread_mask_o = cs_active_mask_i;



 // STACK UPDATE -> VALUES HARDCODED AND SVA WILL CHECK
 always_comb begin
    simt_stack_update_o.update_with_divergence = 1'b0;
    simt_stack_update_o.update_next_pc = pc_i + DICE_METADATA_WIDTH;
    simt_stack_update_o.predicate_regs_value = '0;
    simt_stack_update_o.branch_not_taken_pc = '0;
    simt_stack_update_o.branch_reconvergence_pc = '0;
 end


typedef enum logic [1:0] {
  IDLE,
  UPDATE_STACK,
  UPDATE_STATUS
} update_state_e;

update_state_e update_state_q, update_state_d;

always_comb begin
  update_state_d = update_state_q;
  case (update_state_q)
    IDLE: begin
      if(branch_meta_valid_rise) begin
        update_state_d = UPDATE_STACK;
      end else begin
        update_state_d = IDLE;
      end
    end
    UPDATE_STACK: begin
      if(update_stack_fire && branch_meta_i.is_return) begin
        update_state_d = UPDATE_STATUS;
      end else if (update_stack_fire) begin
        update_state_d = IDLE;
      end
    end
    UPDATE_STATUS: begin
        update_state_d = IDLE;
    end
  endcase
end


// Status table updates -> only thing that can be updated is the return bit
assign branch_predict_info_o.valid_edits_bitmap = {2'b00, (update_state_q == UPDATE_STATUS)};
assign branch_predict_info_o.is_return = branch_meta_i.is_return;
assign branch_predict_info_o.predict_pc = '0;
assign branch_predict_info_o.unresolved_control_divergence = 1'b0;
assign update_valid_o = (update_state_q == UPDATE_STACK);
assign update_stack_fire = update_valid_o && update_ready_i;


 always_ff @(posedge clk_i) begin
    if (rst_i) begin
        update_state_q <= IDLE;
    end else begin
        update_state_q <= update_state_d;
    end
 end


 // Ensures that we never have branches
 `ifndef SYNTHESIS
    assert property (@(posedge clk_i)
      branch_meta_valid_rise |-> (branch_meta_i.branch_ena == 1'b0)
      );
 `endif

endmodule
