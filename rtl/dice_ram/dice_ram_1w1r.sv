`include "dice_pkg.sv"
`include "dice_define.vh"
`define ASIC_FP45
module dice_ram_1w1r
import dice_pkg::*;

#
(

    parameter DATA_WIDTH = DICE_ADDR_WIDTH,
    parameter DEPTH = `DICE_NUM_MAX_THREADS_PER_CORE,
    parameter ADDR_WIDTH = DICE_TID_WIDTH
)(
    input logic clk,

    // Write port
    input logic                  wr_en,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [DATA_WIDTH-1:0] wr_data,

    // Read port
    input logic [ADDR_WIDTH-1:0]  rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);



`ifdef XILINX

// xpm_memory_sdpram: Simple Dual Port RAM
// Xilinx Parameterized Macro, version 2025.1

xpm_memory_sdpram #(
   .ADDR_WIDTH_A(ADDR_WIDTH),               // DECIMAL
   .ADDR_WIDTH_B(ADDR_WIDTH),               // DECIMAL
   .AUTO_SLEEP_TIME(0),            // DECIMAL
   .BYTE_WRITE_WIDTH_A(DATA_WIDTH),        // DECIMAL
   .CASCADE_HEIGHT(0),             // DECIMAL
   .CLOCKING_MODE("common_clock"), // String
   .ECC_BIT_RANGE("7:0"),          // String
   .ECC_MODE("no_ecc"),            // String
   .ECC_TYPE("none"),              // String
   .IGNORE_INIT_SYNTH(0),          // DECIMAL
   .MEMORY_INIT_FILE("none"),      // String
   .MEMORY_INIT_PARAM("0"),        // String
   .MEMORY_OPTIMIZATION("true"),   // String
   .MEMORY_PRIMITIVE("auto"),      // String
   .MEMORY_SIZE(DEPTH),             // DECIMAL
   .MESSAGE_CONTROL(0),            // DECIMAL
   .RAM_DECOMP("auto"),            // String
   .READ_DATA_WIDTH_B(DATA_WIDTH),         // DECIMAL
   .READ_LATENCY_B(1),             // DECIMAL
   .READ_RESET_VALUE_B("0"),       // String
   .RST_MODE_A("SYNC"),            // String
   .RST_MODE_B("SYNC"),            // String
   .SIM_ASSERT_CHK(0),             // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
   .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
   .USE_MEM_INIT(1),               // DECIMAL
   .USE_MEM_INIT_MMI(0),           // DECIMAL
   .WAKEUP_TIME("disable_sleep"),  // String
   .WRITE_DATA_WIDTH_A(DATA_WIDTH),        // DECIMAL
   .WRITE_MODE_B("read_first"),     // String
   .WRITE_PROTECT(1)               // DECIMAL
)
xpm_memory_sdpram_inst (
   .dbiterrb(),             // 1-bit output: Status signal to indicate double bit error occurrence on the data output of port B.
   .doutb(rd_data),                   // READ_DATA_WIDTH_B-bit output: Data output for port B read operations.
   .sbiterrb(),             // 1-bit output: Status signal to indicate single bit error occurrence on the data output of port B.
   .addra(wr_addr),                   // ADDR_WIDTH_A-bit input: Address for port A write operations.
   .addrb(rd_addr),                   // ADDR_WIDTH_B-bit input: Address for port B read operations.
   .clka(clk),                     // 1-bit input: Clock signal for port A. Also clocks port B when parameter CLOCKING_MODE is "common_clock".
   .clkb(clk),                     // 1-bit input: Clock signal for port B when parameter CLOCKING_MODE is "independent_clock". Unused when
                                    // parameter CLOCKING_MODE is "common_clock".

   .dina(wr_data),                     // WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
   .ena(1),                       // 1-bit input: Memory enable signal for port A. Must be high on clock cycles when write operations are
                                    // initiated. Pipelined internally.

   .enb(1),                       // 1-bit input: Memory enable signal for port B. Must be high on clock cycles when read operations are
                                    // initiated. Pipelined internally.

   .injectdbiterra(), // 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection capability
                                    // is not available in "decode_only" mode).

   .injectsbiterra(), // 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection capability
                                    // is not available in "decode_only" mode).

   .regceb(1),                 // 1-bit input: Clock Enable for the last register stage on the output data path.
   .rstb(0),                     // 1-bit input: Reset signal for the final port B output register stage. Synchronously resets output port
                                    // doutb to the value specified by parameter READ_RESET_VALUE_B.

   .sleep(0),                   // 1-bit input: sleep signal to enable the dynamic power saving feature.
   .wea(wr_en)                        // WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1 bit
                                    // wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing one
                                    // byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                    // WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.

);

// End of xpm_memory_sdpram_inst instantiation


// `elsif ASIC_FP45
// TODO: add macro from sram compiler for FP45

    // $display("INSTANTIATING SRAM MACRO");

logic [ADDR_WIDTH-1:0] addr_macro;

assign addr_macro = wr_en ? wr_addr : rd_addr;

sram_512x32 
sram_512x32_inst 
    (
        .clk0(clk)
        ,.csb0(1'b0)
        ,.web0(~wr_en)
        ,.addr0(addr_macro)
        ,.din0(wr_data)
        ,.dout0(rd_data)
    );

`else
// simulation
    // RAM storage array

    logic [DATA_WIDTH-1:0] ram_array [DEPTH-1:0];
    logic [DATA_WIDTH-1:0] rd_data_reg;

    assign rd_data = rd_data_reg;

    // Write operation
    always_ff @(posedge clk) begin
        if (wr_en) begin
            ram_array[wr_addr] <= wr_data;
        end
    end

    // Read operation
    always_ff @(posedge clk) begin
        rd_data_reg <= ram_array[rd_addr];
    end
`endif
endmodule
