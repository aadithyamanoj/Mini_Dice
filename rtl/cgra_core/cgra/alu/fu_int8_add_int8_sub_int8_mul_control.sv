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
            OPCODE_ADD: en = {1'b0, 1'b1};  // Operation(op_type='add', num_operands=2, operand_types=('int8', 'int8', 'int8'))
            OPCODE_SUB: en = {1'b0, 1'b1};  // Operation(op_type='sub', num_operands=2, operand_types=('int8', 'int8', 'int8'))
            OPCODE_MUL: en = {1'b1, 1'b0};  // Operation(op_type='mul', num_operands=2, operand_types=('int8', 'int8', 'int8'))
            default: en = 2'b0;
        endcase
    end

endmodule