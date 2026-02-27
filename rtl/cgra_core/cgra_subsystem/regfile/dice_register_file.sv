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
            dice_ram_1w1r #(
                .DATA_WIDTH(WIDTH),
                .DEPTH(DEPTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) bank_ram (
                .clk     (clk),
                .wr_en   (wr_en[i]),
                .wr_addr (wr_addr[(i+1)*ADDR_WIDTH-1:i*ADDR_WIDTH]),
                .wr_data (wr_data[(i+1)*WIDTH-1:i*WIDTH]),
                .rd_addr (rd_addr[(i+1)*ADDR_WIDTH-1:i*ADDR_WIDTH]),
                .rd_data (rd_data[(i+1)*WIDTH-1:i*WIDTH])
            );
        end
    endgenerate

endmodule
