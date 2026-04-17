// General-purpose rising-edge detector
// Outputs a single-cycle pulse on the first cycle `sig_i` is high
// after having been low (or after reset).

module rising_edge_detector (
    input  logic clk_i,
    input  logic rst_i,
    input  logic sig_i,
    output logic rise_o
);

  logic sig_prev_q;

  always_ff @(posedge clk_i) begin
      if (rst_i)
          sig_prev_q <= 1'b0;
      else
          sig_prev_q <= sig_i;
  end

  assign rise_o = sig_i & ~sig_prev_q;

endmodule
