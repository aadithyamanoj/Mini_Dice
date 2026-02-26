module dice_2_32_router (
    input  logic clk,
    input  logic rst_n,
    input  logic overload_en_N_t0,
    input  logic overload_ctrl_N_t0,
    input  logic overload_en_N_t1,
    input  logic overload_ctrl_N_t1,
    input  logic overload_en_E_t0,
    input  logic overload_ctrl_E_t0,
    input  logic overload_en_E_t1,
    input  logic overload_ctrl_E_t1,
    input  logic overload_en_S_t0,
    input  logic overload_ctrl_S_t0,
    input  logic overload_en_S_t1,
    input  logic overload_ctrl_S_t1,
    input  logic overload_en_W_t0,
    input  logic overload_ctrl_W_t0,
    input  logic overload_en_W_t1,
    input  logic overload_ctrl_W_t1,
    input  logic overload_en_L_t0,
    input  logic overload_ctrl_L_t0,
    input  logic overload_en_L_t1,
    input  logic overload_ctrl_L_t1,
    input  logic overload_en_L_t2,
    input  logic overload_ctrl_L_t2,
    input  logic overload_en_L_t3,
    input  logic overload_ctrl_L_t3,
    input  logic registered_mode_N_t0,
    input  logic registered_mode_N_t1,
    input  logic registered_mode_E_t0,
    input  logic registered_mode_E_t1,
    input  logic registered_mode_S_t0,
    input  logic registered_mode_S_t1,
    input  logic registered_mode_W_t0,
    input  logic registered_mode_W_t1,
    input  logic registered_mode_L_t0,
    input  logic registered_mode_L_t1,
    input  logic registered_mode_L_t2,
    input  logic registered_mode_L_t3,
    input  logic [31:0] N_in_t0,
    input  logic [31:0] N_in_t1,
    input  logic [31:0] E_in_t0,
    input  logic [31:0] E_in_t1,
    input  logic [31:0] S_in_t0,
    input  logic [31:0] S_in_t1,
    input  logic [31:0] W_in_t0,
    input  logic [31:0] W_in_t1,
    input  logic [31:0] L_in_t0,
    input  logic [31:0] L_in_t1,
    output logic [31:0] N_out_t0,
    output logic [31:0] N_out_t1,
    output logic [31:0] E_out_t0,
    output logic [31:0] E_out_t1,
    output logic [31:0] S_out_t0,
    output logic [31:0] S_out_t1,
    output logic [31:0] W_out_t0,
    output logic [31:0] W_out_t1,
    output logic [31:0] L_out_t0,
    output logic [31:0] L_out_t1,
    output logic [31:0] L_out_t2,
    output logic [31:0] L_out_t3,
    input  logic [3:0] sel_N_t0,
    input  logic [3:0] sel_N_t1,
    input  logic [3:0] sel_E_t0,
    input  logic [3:0] sel_E_t1,
    input  logic [3:0] sel_S_t0,
    input  logic [3:0] sel_S_t1,
    input  logic [3:0] sel_W_t0,
    input  logic [3:0] sel_W_t1,
    input  logic [3:0] sel_L_t0,
    input  logic [3:0] sel_L_t1,
    input  logic [3:0] sel_L_t2,
    input  logic [3:0] sel_L_t3
);

  logic [31:0] N_sel_t0;
  logic [31:0] N_mux_t0;
  logic [31:0] N_reg_t0;
  logic [31:0] N_sel_t1;
  logic [31:0] N_mux_t1;
  logic [31:0] N_reg_t1;
  logic [31:0] E_sel_t0;
  logic [31:0] E_mux_t0;
  logic [31:0] E_reg_t0;
  logic [31:0] E_sel_t1;
  logic [31:0] E_mux_t1;
  logic [31:0] E_reg_t1;
  logic [31:0] S_sel_t0;
  logic [31:0] S_mux_t0;
  logic [31:0] S_reg_t0;
  logic [31:0] S_sel_t1;
  logic [31:0] S_mux_t1;
  logic [31:0] S_reg_t1;
  logic [31:0] W_sel_t0;
  logic [31:0] W_mux_t0;
  logic [31:0] W_reg_t0;
  logic [31:0] W_sel_t1;
  logic [31:0] W_mux_t1;
  logic [31:0] W_reg_t1;
  logic [31:0] L_sel_t0;
  logic [31:0] L_mux_t0;
  logic [31:0] L_reg_t0;
  logic [31:0] L_sel_t1;
  logic [31:0] L_mux_t1;
  logic [31:0] L_reg_t1;
  logic [31:0] L_sel_t2;
  logic [31:0] L_mux_t2;
  logic [31:0] L_reg_t2;
  logic [31:0] L_sel_t3;
  logic [31:0] L_mux_t3;
  logic [31:0] L_reg_t3;

  always_comb begin
    unique case (sel_N_t0)
      4'd0: N_sel_t0 = N_in_t0;
      4'd1: N_sel_t0 = N_in_t1;
      4'd2: N_sel_t0 = E_in_t0;
      4'd3: N_sel_t0 = E_in_t1;
      4'd4: N_sel_t0 = S_in_t0;
      4'd5: N_sel_t0 = S_in_t1;
      4'd6: N_sel_t0 = W_in_t0;
      4'd7: N_sel_t0 = W_in_t1;
      4'd8: N_sel_t0 = L_in_t0;
      4'd9: N_sel_t0 = L_in_t1;
      default: N_sel_t0 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_N_t1)
      4'd0: N_sel_t1 = N_in_t0;
      4'd1: N_sel_t1 = N_in_t1;
      4'd2: N_sel_t1 = E_in_t0;
      4'd3: N_sel_t1 = E_in_t1;
      4'd4: N_sel_t1 = S_in_t0;
      4'd5: N_sel_t1 = S_in_t1;
      4'd6: N_sel_t1 = W_in_t0;
      4'd7: N_sel_t1 = W_in_t1;
      4'd8: N_sel_t1 = L_in_t0;
      4'd9: N_sel_t1 = L_in_t1;
      default: N_sel_t1 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_E_t0)
      4'd0: E_sel_t0 = N_in_t0;
      4'd1: E_sel_t0 = N_in_t1;
      4'd2: E_sel_t0 = E_in_t0;
      4'd3: E_sel_t0 = E_in_t1;
      4'd4: E_sel_t0 = S_in_t0;
      4'd5: E_sel_t0 = S_in_t1;
      4'd6: E_sel_t0 = W_in_t0;
      4'd7: E_sel_t0 = W_in_t1;
      4'd8: E_sel_t0 = L_in_t0;
      4'd9: E_sel_t0 = L_in_t1;
      default: E_sel_t0 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_E_t1)
      4'd0: E_sel_t1 = N_in_t0;
      4'd1: E_sel_t1 = N_in_t1;
      4'd2: E_sel_t1 = E_in_t0;
      4'd3: E_sel_t1 = E_in_t1;
      4'd4: E_sel_t1 = S_in_t0;
      4'd5: E_sel_t1 = S_in_t1;
      4'd6: E_sel_t1 = W_in_t0;
      4'd7: E_sel_t1 = W_in_t1;
      4'd8: E_sel_t1 = L_in_t0;
      4'd9: E_sel_t1 = L_in_t1;
      default: E_sel_t1 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_S_t0)
      4'd0: S_sel_t0 = N_in_t0;
      4'd1: S_sel_t0 = N_in_t1;
      4'd2: S_sel_t0 = E_in_t0;
      4'd3: S_sel_t0 = E_in_t1;
      4'd4: S_sel_t0 = S_in_t0;
      4'd5: S_sel_t0 = S_in_t1;
      4'd6: S_sel_t0 = W_in_t0;
      4'd7: S_sel_t0 = W_in_t1;
      4'd8: S_sel_t0 = L_in_t0;
      4'd9: S_sel_t0 = L_in_t1;
      default: S_sel_t0 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_S_t1)
      4'd0: S_sel_t1 = N_in_t0;
      4'd1: S_sel_t1 = N_in_t1;
      4'd2: S_sel_t1 = E_in_t0;
      4'd3: S_sel_t1 = E_in_t1;
      4'd4: S_sel_t1 = S_in_t0;
      4'd5: S_sel_t1 = S_in_t1;
      4'd6: S_sel_t1 = W_in_t0;
      4'd7: S_sel_t1 = W_in_t1;
      4'd8: S_sel_t1 = L_in_t0;
      4'd9: S_sel_t1 = L_in_t1;
      default: S_sel_t1 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_W_t0)
      4'd0: W_sel_t0 = N_in_t0;
      4'd1: W_sel_t0 = N_in_t1;
      4'd2: W_sel_t0 = E_in_t0;
      4'd3: W_sel_t0 = E_in_t1;
      4'd4: W_sel_t0 = S_in_t0;
      4'd5: W_sel_t0 = S_in_t1;
      4'd6: W_sel_t0 = W_in_t0;
      4'd7: W_sel_t0 = W_in_t1;
      4'd8: W_sel_t0 = L_in_t0;
      4'd9: W_sel_t0 = L_in_t1;
      default: W_sel_t0 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_W_t1)
      4'd0: W_sel_t1 = N_in_t0;
      4'd1: W_sel_t1 = N_in_t1;
      4'd2: W_sel_t1 = E_in_t0;
      4'd3: W_sel_t1 = E_in_t1;
      4'd4: W_sel_t1 = S_in_t0;
      4'd5: W_sel_t1 = S_in_t1;
      4'd6: W_sel_t1 = W_in_t0;
      4'd7: W_sel_t1 = W_in_t1;
      4'd8: W_sel_t1 = L_in_t0;
      4'd9: W_sel_t1 = L_in_t1;
      default: W_sel_t1 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_L_t0)
      4'd0: L_sel_t0 = N_in_t0;
      4'd1: L_sel_t0 = N_in_t1;
      4'd2: L_sel_t0 = E_in_t0;
      4'd3: L_sel_t0 = E_in_t1;
      4'd4: L_sel_t0 = S_in_t0;
      4'd5: L_sel_t0 = S_in_t1;
      4'd6: L_sel_t0 = W_in_t0;
      4'd7: L_sel_t0 = W_in_t1;
      4'd8: L_sel_t0 = L_in_t0;
      4'd9: L_sel_t0 = L_in_t1;
      default: L_sel_t0 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_L_t1)
      4'd0: L_sel_t1 = N_in_t0;
      4'd1: L_sel_t1 = N_in_t1;
      4'd2: L_sel_t1 = E_in_t0;
      4'd3: L_sel_t1 = E_in_t1;
      4'd4: L_sel_t1 = S_in_t0;
      4'd5: L_sel_t1 = S_in_t1;
      4'd6: L_sel_t1 = W_in_t0;
      4'd7: L_sel_t1 = W_in_t1;
      4'd8: L_sel_t1 = L_in_t0;
      4'd9: L_sel_t1 = L_in_t1;
      default: L_sel_t1 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_L_t2)
      4'd0: L_sel_t2 = N_in_t0;
      4'd1: L_sel_t2 = N_in_t1;
      4'd2: L_sel_t2 = E_in_t0;
      4'd3: L_sel_t2 = E_in_t1;
      4'd4: L_sel_t2 = S_in_t0;
      4'd5: L_sel_t2 = S_in_t1;
      4'd6: L_sel_t2 = W_in_t0;
      4'd7: L_sel_t2 = W_in_t1;
      4'd8: L_sel_t2 = L_in_t0;
      4'd9: L_sel_t2 = L_in_t1;
      default: L_sel_t2 = '0;
    endcase
  end
  always_comb begin
    unique case (sel_L_t3)
      4'd0: L_sel_t3 = N_in_t0;
      4'd1: L_sel_t3 = N_in_t1;
      4'd2: L_sel_t3 = E_in_t0;
      4'd3: L_sel_t3 = E_in_t1;
      4'd4: L_sel_t3 = S_in_t0;
      4'd5: L_sel_t3 = S_in_t1;
      4'd6: L_sel_t3 = W_in_t0;
      4'd7: L_sel_t3 = W_in_t1;
      4'd8: L_sel_t3 = L_in_t0;
      4'd9: L_sel_t3 = L_in_t1;
      default: L_sel_t3 = '0;
    endcase
  end

  assign N_mux_t0 = (overload_en_N_t0 & overload_ctrl_N_t0) ? L_in_t0 : N_sel_t0;
  assign N_mux_t1 = (overload_en_N_t1 & overload_ctrl_N_t1) ? L_in_t0 : N_sel_t1;
  assign E_mux_t0 = (overload_en_E_t0 & overload_ctrl_E_t0) ? L_in_t0 : E_sel_t0;
  assign E_mux_t1 = (overload_en_E_t1 & overload_ctrl_E_t1) ? L_in_t0 : E_sel_t1;
  assign S_mux_t0 = (overload_en_S_t0 & overload_ctrl_S_t0) ? L_in_t0 : S_sel_t0;
  assign S_mux_t1 = (overload_en_S_t1 & overload_ctrl_S_t1) ? L_in_t0 : S_sel_t1;
  assign W_mux_t0 = (overload_en_W_t0 & overload_ctrl_W_t0) ? L_in_t0 : W_sel_t0;
  assign W_mux_t1 = (overload_en_W_t1 & overload_ctrl_W_t1) ? L_in_t0 : W_sel_t1;
  assign L_mux_t0 = (overload_en_L_t0 & overload_ctrl_L_t0) ? L_in_t0 : L_sel_t0;
  assign L_mux_t1 = (overload_en_L_t1 & overload_ctrl_L_t1) ? L_in_t0 : L_sel_t1;
  assign L_mux_t2 = (overload_en_L_t2 & overload_ctrl_L_t2) ? L_in_t0 : L_sel_t2;
  assign L_mux_t3 = (overload_en_L_t3 & overload_ctrl_L_t3) ? L_in_t0 : L_sel_t3;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      N_reg_t0 <= '0;
      N_reg_t1 <= '0;
      E_reg_t0 <= '0;
      E_reg_t1 <= '0;
      S_reg_t0 <= '0;
      S_reg_t1 <= '0;
      W_reg_t0 <= '0;
      W_reg_t1 <= '0;
      L_reg_t0 <= '0;
      L_reg_t1 <= '0;
      L_reg_t2 <= '0;
      L_reg_t3 <= '0;
    end else begin
      N_reg_t0 <= N_mux_t0;
      N_reg_t1 <= N_mux_t1;
      E_reg_t0 <= E_mux_t0;
      E_reg_t1 <= E_mux_t1;
      S_reg_t0 <= S_mux_t0;
      S_reg_t1 <= S_mux_t1;
      W_reg_t0 <= W_mux_t0;
      W_reg_t1 <= W_mux_t1;
      L_reg_t0 <= L_mux_t0;
      L_reg_t1 <= L_mux_t1;
      L_reg_t2 <= L_mux_t2;
      L_reg_t3 <= L_mux_t3;
    end
  end

  assign N_out_t0 = registered_mode_N_t0 ? N_reg_t0 : N_mux_t0;
  assign N_out_t1 = registered_mode_N_t1 ? N_reg_t1 : N_mux_t1;
  assign E_out_t0 = registered_mode_E_t0 ? E_reg_t0 : E_mux_t0;
  assign E_out_t1 = registered_mode_E_t1 ? E_reg_t1 : E_mux_t1;
  assign S_out_t0 = registered_mode_S_t0 ? S_reg_t0 : S_mux_t0;
  assign S_out_t1 = registered_mode_S_t1 ? S_reg_t1 : S_mux_t1;
  assign W_out_t0 = registered_mode_W_t0 ? W_reg_t0 : W_mux_t0;
  assign W_out_t1 = registered_mode_W_t1 ? W_reg_t1 : W_mux_t1;
  assign L_out_t0 = registered_mode_L_t0 ? L_reg_t0 : L_mux_t0;
  assign L_out_t1 = registered_mode_L_t1 ? L_reg_t1 : L_mux_t1;
  assign L_out_t2 = registered_mode_L_t2 ? L_reg_t2 : L_mux_t2;
  assign L_out_t3 = registered_mode_L_t3 ? L_reg_t3 : L_mux_t3;

endmodule : dice_2_32_router
