module dice_register_file 
import dice_pkg::*;
import DE_pkg::*;
#(
    parameter int NUM_BANK = DICE_NUM_BANKS,
    parameter int WIDTH = DICE_REG_DATA_WIDTH,
    parameter int DEPTH = DICE_REGS_PER_BANK,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic              clk,
    // Read port
    input  logic [NUM_BANK*ADDR_WIDTH-1:0] rd_addr,
    output logic [NUM_BANK*WIDTH-1:0] rd_data,
    // Write port
    input  logic [NUM_BANK-1:0]    wr_en,
    input  logic [NUM_BANK*ADDR_WIDTH-1:0] wr_addr,
    input  logic [NUM_BANK*WIDTH-1:0] wr_data
);


    
    initial begin
        $display("DICE_NUM_BANKS: %0d", NUM_BANK);
        $display("DICE_REG_DATA_WIDTH: %0d", WIDTH);
        $display("DICE_REGS_PER_BANK: %0d", DEPTH);
    end
    genvar i;
    generate
        for (i = 0; i < NUM_BANK; i++) begin : gen_bank
            bsg_mem_1r1w_sync #(
                .width_p(WIDTH),
                .els_p(DEPTH),
                .read_write_same_addr_p(1)
            ) bank_ram (
                .clk_i   (clk),
                .reset_i (1'b0),
                .w_v_i   (wr_en[i]),
                .w_addr_i(wr_addr[(i+1)*ADDR_WIDTH-1:i*ADDR_WIDTH]),
                .w_data_i(wr_data[(i+1)*WIDTH-1:i*WIDTH]),
                .r_v_i   (1'b1),
                .r_addr_i(rd_addr[(i+1)*ADDR_WIDTH-1:i*ADDR_WIDTH]),
                .r_data_o(rd_data[(i+1)*WIDTH-1:i*WIDTH])
            );
        end
    endgenerate

endmodule
