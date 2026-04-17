/**
 * Valid Checker Module
 * Checks if e-block can be passed from FDR to DE stage.
 * On predict-miss, fdr_top sends flush notification to the scheduler.
 *
 * PC-match check and flush/mispredict logic have been moved to branch_handler.
 * branch_handler asserts bh_done_i only after all divergence concerns are
 * settled, so unresolved_div no longer needs to be checked here.
 */
module valid_check
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    // Inputs
    input logic barrier_indicator_i,  // P-graph requires barrier
    input logic decode_done_i,        // Decode done (branch metadata valid)
    input logic bh_done_i,            // Branch handler finished pre-fire work
    input logic bitstream_loaded_i,   // Bitstream fully loaded into CM
    input logic barrier_complete_i,   // Barrier met
    input logic ex_ready_i,           // Execute stage ready

    // Outputs
    output logic fdr_valid_o,         // E-block ready to issue
    output logic fire_eblock_o        // Handshake complete (eblock fired)
);

  logic barrier_ok, can_issue;

  assign barrier_ok  = !barrier_indicator_i || barrier_complete_i;

  assign can_issue = bitstream_loaded_i &&
                     decode_done_i      &&
                     bh_done_i          &&
                     barrier_ok;

  assign fdr_valid_o   = can_issue;
  assign fire_eblock_o = can_issue && ex_ready_i;
   
endmodule
