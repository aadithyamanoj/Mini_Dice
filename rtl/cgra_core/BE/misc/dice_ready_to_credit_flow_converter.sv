`include "bsg_defines.v"

module dice_ready_to_credit_flow_converter #(
    parameter `BSG_INV_PARAM(credit_initial_p),
    parameter `BSG_INV_PARAM(credit_max_val_p),
    parameter `BSG_INV_PARAM(max_step_p),

    parameter step_width_lp = `BSG_WIDTH(max_step_p),
    parameter ptr_width_lp = `BSG_WIDTH(credit_max_val_p)
) (
    input clk_i,
    input reset_i,

    input v_i,
    output logic ready_o,

    output logic v_o,
    input [step_width_lp-1:0] credit_i,
    input [step_width_lp-1:0] credit_need_i
);

  logic [step_width_lp-1:0] up_li, down_li;
  logic [ptr_width_lp-1:0] credit_cnt;

  assign ready_o = credit_cnt >= ptr_width_lp'(credit_need_i);
  assign v_o = v_i & ready_o;

  assign up_li = credit_i;
  assign down_li = v_o ? credit_need_i : '0;

  bsg_counter_up_down_variable #(
      .max_val_p(credit_max_val_p),
      .init_val_p(credit_initial_p),
      .max_step_p(max_step_p)
  ) credit_counter (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .up_i(up_li),
      .down_i(down_li),
      .count_o(credit_cnt)
  );

endmodule

`BSG_ABSTRACT_MODULE(dice_ready_to_credit_flow_converter)
