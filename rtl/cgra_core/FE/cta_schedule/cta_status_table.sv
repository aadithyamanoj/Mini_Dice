module cta_status_table
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // From branch handler / branch predictor
    input branch_predict_interface_t branch_predict_info_i,
    input logic                      branch_predict_info_we_i,

    // BRT-owned pending e-block state
    input logic has_pending_eblock_i,

    // Scheduler-owned live e-block state
    input logic eblock_in_flight_i,

    // From cta controller
    input logic clear_entry_valid_i,

    // Exposed status for the single CTA
    output dice_cta_status_t cta_status_o
);

  dice_cta_status_t cta_status_q, cta_status_d;

  always_comb begin
    cta_status_d = cta_status_q;
    cta_status_d.has_pending_eblock = has_pending_eblock_i;
    cta_status_d.eblock_in_flight = eblock_in_flight_i;
    if (branch_predict_info_we_i) begin
      if (branch_predict_info_i.valid_edits_bitmap[2])
        cta_status_d.unresolved_control_divergence = branch_predict_info_i.unresolved_control_divergence;
      if (branch_predict_info_i.valid_edits_bitmap[1])
        cta_status_d.predict_pc = branch_predict_info_i.predict_pc;
      if (branch_predict_info_i.valid_edits_bitmap[0])
        cta_status_d.is_return = branch_predict_info_i.is_return;
    end
    if (clear_entry_valid_i) begin
      cta_status_d.unresolved_control_divergence = 1'b0;
      cta_status_d.is_return = 1'b0;
      cta_status_d.predict_pc = '0;
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cta_status_q <= '0;
    end else begin
      cta_status_q <= cta_status_d;
    end
  end

  assign cta_status_o = cta_status_q;

endmodule
