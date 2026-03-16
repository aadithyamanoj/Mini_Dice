// alu_8bit_Operation(op_type='add', num_operands=2, operand_types=('int8', 'int8', 'int8'))_Operation(op_type='sub', num_operands=2, operand_types=('int8', 'int8', 'int8')).sv
module alu_add (
    input  logic [7:0] A,
    input  logic [7:0] B,
    input  logic [1:0] opcode,
    input  logic en,
    output logic [7:0] result
);
    // Opcode constants
    localparam [1:0] OPCODE_ADD = 2'b00;
    localparam [1:0] OPCODE_SUB = 2'b01;
    // Internal signals
    logic [7:0] result_internal;
    logic [7:0] _a, _b;
    logic [7:0] add_sub_result;
    logic [7:0] _b_mod;
    logic is_sub;
    logic carry_in;
    always_comb begin
        _a              = A;
        _b              = B;
        result_internal = 8'b0;
        is_sub         = 1'b0;
        _b_mod         = 8'b0;
        carry_in       = 1'b0;
        if (en) begin
            is_sub = (opcode == OPCODE_SUB);
            _b_mod = is_sub ? ~_b : _b;
            carry_in = is_sub ? 1'b1 : 1'b0;
            add_sub_result = _a + _b_mod + { 7'b0, carry_in };
            case (opcode)
                OPCODE_ADD: result_internal = add_sub_result;
                OPCODE_SUB: result_internal = add_sub_result;
                default: result_internal = 8'b0;
            endcase
        end else begin
            result_internal = '0;
            add_sub_result = 8'b0;
        end
    end
    assign result = result_internal;
endmodule