// 1 Read/Write RAM - Single port that can read or write
module dice_ram_1rw #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 1024,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter string INIT_FILE = ""   // <-- ADD THIS
)(
    input logic clk,
    
    // Single read/write port
    input logic en,
    input logic we,  // 1 = write, 0 = read
    input logic [ADDR_WIDTH-1:0] addr,
    input logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
);

    // RAM storage array
    logic [DATA_WIDTH-1:0] ram_array [DEPTH-1:0];
    logic [DATA_WIDTH-1:0] rdata_reg;
    
    assign rdata = rdata_reg;
    
    // Initialize RAM
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram_array);
        end else begin
            for (int i = 0; i < DEPTH; i++) begin
                ram_array[i] = '0;
            end
        end
    end
    
    // Read/Write operation
    always_ff @(posedge clk) begin
        if (en && !we) rdata_reg <= ram_array[addr];
    end

    always @(posedge clk) begin
        if (en && we) ram_array[addr] <= wdata;
    end


endmodule
