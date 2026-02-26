/**
 * Valid Checker Module
 * Checks if e-block can be passed from FDR to DE stage.
 * On predict-miss, fdr_top sends flush notification to the scheduler.


 I DON'T THINK THAT THIS NEEDS A SIGNAL FROM THE BH ABOUT THE CORRECT MASK BECAUSE THE WILL ALWAYS HAPPEN WHEN THE EBLOCK'S DIVERGENCE IS RESOLVED
 */
module valid_check
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    // Inputs
    input logic barrier_indicator_i,  // P-graph requires barrier
    input logic decode_done_i,        // Decode done
    input logic [DICE_ADDR_WIDTH-1:0] eblock_pc_i,
    input logic prefetch_block_i,
    input logic [DICE_ADDR_WIDTH-1:0] simt_stack_pc_i,
    input logic bitstream_loaded_i,
    input logic unresolved_div_i,     // Unresolved divergence
    input logic barrier_complete_i,   // Barrier met
    input logic prefetch_cleared_i,   // Prefetch resolved
    input logic ex_ready_i,

    // Outputs
    output logic fdr_valid_o,
    output logic fire_eblock_o,       // Handshake complete
    output logic clear_prefetch_o,    // Predict hit
    output logic predict_miss_o       // Predict miss (flush)
);

  logic pc_match, pc_match_required, pc_check_pass;
  logic prefetch_ok, barrier_ok, can_issue;

  // Basic Checks
  assign prefetch_ok = !prefetch_block_i || prefetch_cleared_i;
  assign barrier_ok  = !barrier_indicator_i || barrier_complete_i;

  // PC Verification (only for prefetch blocks after divergence resolved)
  assign pc_match          = (eblock_pc_i == simt_stack_pc_i);
  assign pc_match_required = prefetch_block_i && !unresolved_div_i && !prefetch_cleared_i;
  assign pc_check_pass     = !pc_match_required || pc_match;

  // Final Valid Condition
  assign can_issue = bitstream_loaded_i &&
                     prefetch_ok        &&
                     decode_done_i      &&
                     barrier_ok         &&
                     !unresolved_div_i  &&
                     pc_check_pass;

  // Outputs
  assign fdr_valid_o      = can_issue;
  assign fire_eblock_o    = can_issue && ex_ready_i;
  assign clear_prefetch_o = pc_match_required && pc_match && can_issue; //This would clear it in status table
  assign predict_miss_o   = pc_match_required && !pc_match;

endmodule
