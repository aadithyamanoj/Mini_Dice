// Single 16-bit CSR register: io_csr_cta_desc_info
// Synchronous write (active-high reset), combinatorial read.
module io_csr_cta_desc_info (
  input  logic        clk_i,
  input  logic        reset_i,
  input  logic        wr_en_i,
  input  logic [15:0] wr_data_i,
  input  logic        rd_en_i,
  output logic [15:0] rd_data_o,
  output logic        rd_valid_o
);
  logic [15:0] reg_r;
  always_ff @(posedge clk_i) begin
    if (reset_i) reg_r <= 16'h0;
    else if (wr_en_i) reg_r <= wr_data_i;
  end
  assign rd_data_o  = reg_r;
  assign rd_valid_o = rd_en_i;
endmodule
