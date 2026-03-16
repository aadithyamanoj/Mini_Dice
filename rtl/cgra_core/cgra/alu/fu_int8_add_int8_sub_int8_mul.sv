module fu_int8_add_int8_sub_int8_mul (
  input  logic        clk_i,
  input  logic [7:0]  A,
  input  logic [7:0]  B,
  input  logic [1:0] prog_data_i,
  input  logic        prog_done_i,
  output logic [7:0]  out
);

  logic [7:0] temp [1:0];
  logic [1:0] en;
  logic [7:0] out_internal;

  // Registered inputs
  logic [7:0] A_data;
  logic [7:0] B_data;

  // Optional ready-controlled input sampling (for future multi-cycle ops)
  always_ff @(posedge clk_i) begin
    // if (ready) begin (for future multi-cycle ops)
      A_data <= A;
      B_data <= B;
    // end
  end

  // Instantiate control module
  fu_int8_add_int8_sub_int8_mul_control control_inst (
    .op_code (prog_data_i),
    .en      (en)
  );

  // ALU group instantiations
  alu_add alu_add_inst_0 (
    .A     (A_data),
    .B     (B_data),
    .opcode(prog_data_i),
    .en    (en[0]),
    .result(temp[0])
  );
  alu_mul alu_mul_inst_1 (
    .A     (A_data),
    .B     (B_data),
    .opcode(prog_data_i),
    .en    (en[1]),
    .result(temp[1])
  );

  // Output mux
  mux_generic mux_generic_inst (
    .in_add   ( temp[0] ),
    .in_mul   ( temp[1] ),
    .en           ( en ),
    .clk_i          ( clk_i ),
    .out          ( out_internal )
  );

  // Gate output with prog_done
  assign out = prog_done_i ? out_internal : 8'b0;

endmodule