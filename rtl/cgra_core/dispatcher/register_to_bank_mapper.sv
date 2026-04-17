module register_to_bank_mapper
    import dice_pkg::*,
           DE_pkg::*;
(
    input  logic [DICE_TOTAL_REGS-1:0] reg_bitmap,
    input  logic [DICE_TID_WIDTH-1:0]  tid,
    output logic [DICE_NUM_BANKS-1:0]  bank_bitmap
);

    always_comb begin
        bank_bitmap = '0;

        for (int reg_num = 0; reg_num < DICE_NUM_REGS; reg_num++) begin
            if (reg_bitmap[reg_num]) begin
                bank_bitmap[bank_select(tid, $clog2(DICE_NUM_REGS)'(reg_num))] = 1'b1;
            end
        end
    end

endmodule
