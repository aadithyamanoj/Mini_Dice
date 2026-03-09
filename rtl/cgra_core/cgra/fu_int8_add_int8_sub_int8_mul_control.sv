module fu_int8_add_int8_sub_int8_mul_control (
    input  logic [1:0] op_code,
    output logic [1:0] en
);

    // define every opcode as a named constant
    localparam logic [1:0] OPCODE_ADD = 2'b00;
    localparam logic [1:0] OPCODE_SUB = 2'b01;
    localparam logic [1:0] OPCODE_MUL = 2'b10;

    always_comb begin
        // default: all groups disabled
        en = 2'b0;
        unique case (op_code)
            OPCODE_ADD: en = {1'b0, 1'b1};  // Operation(op_type=<OpType.ADD: 1>, num_operands=2, operand_types=(ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True)))
            OPCODE_SUB: en = {1'b0, 1'b1};  // Operation(op_type=<OpType.SUB: 2>, num_operands=2, operand_types=(ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True)))
            OPCODE_MUL: en = {1'b1, 1'b0};  // Operation(op_type=<OpType.MUL: 3>, num_operands=2, operand_types=(ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True), ArchIntegerType(name='int8', bit_width=8, signed=True)))
            default: en = 2'b0;
        endcase
    end

endmodule