`include "dice_pkg.sv"

module sync_fifo_read_unreg #(
    parameter int DATA_WIDTH = 8,           // Width of data bus
    parameter int DEPTH = 8,               // FIFO depth (must be power of 2)
    parameter int ADDR_WIDTH = $clog2(DEPTH) // Address width (automatically calculated)
)(
    input logic clk_i,                        // Clock
    input logic rst,                      // Active-low reset
    
    // Write interface
    input logic push,                       // Push enable
    input logic [DATA_WIDTH-1:0] push_data, // Data to push
    
    // Read interface  
    input logic pop,                        // Pop enable
    output logic [DATA_WIDTH-1:0] pop_data, // Data output (valid next cycle after pop)
    output logic pop_data_valid,            // Indicates pop_data is valid
    
    // Status signals
    output logic empty,                     // FIFO is empty
    output logic full,                      // FIFO is full
    output logic [ADDR_WIDTH:0] count       // Number of entries in FIFO
);

    // Internal memory array
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // Internal pointers
    logic [ADDR_WIDTH:0] write_ptr;         // Write pointer (extra bit for full/empty detection)
    logic [ADDR_WIDTH:0] read_ptr;          // Read pointer (extra bit for full/empty detection)
    
    // Internal control signals
    logic push_enable;
    logic pop_enable;
    
    // Push and pop enable logic (prevent overflow/underflow)
    assign push_enable = push && !full;
    assign pop_enable = pop && !empty;
    
    // Write pointer logic
    always_ff @(posedge clk_i) begin
        if (rst) begin
            write_ptr <= '0;
        end else if (push_enable) begin
            write_ptr <= write_ptr + 1'b1;
        end
    end
    
    // Read pointer logic
    always_ff @(posedge clk_i) begin
        if (rst) begin
            read_ptr <= '0;
        end else if (pop_enable) begin
            read_ptr <= read_ptr + 1'b1;
        end
    end
    
    // Memory write logic
    always_ff @(posedge clk_i) begin
        if (rst) begin
            // Reset memory contents (optional, can be omitted)
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= '0;
            end
        end else if (push_enable) begin
            mem[write_ptr[ADDR_WIDTH-1:0]] <= push_data;
        end
    end
    
    
    // Output assignments
    assign pop_data = mem[read_ptr[ADDR_WIDTH-1:0]];
    assign pop_data_valid = !empty;
    
    // Status flags
    assign empty = (write_ptr == read_ptr);
    assign full = (write_ptr[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]) && 
                  (write_ptr[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]);
    
    // Count calculation
    always_comb begin
        if (write_ptr >= read_ptr) begin
            count = write_ptr - read_ptr;
        end else begin
            count = (DEPTH - read_ptr) + write_ptr;
        end
    end
    
    // Assertions for debugging (synthesis will ignore these)
    //`ifdef SIMULATION
    //    // Check for overflow
    //    assert property (@(posedge clk_i) disable iff (!rst_n)
    //        push |-> !full)
    //    else $error("FIFO overflow: push asserted when FIFO is full");
    //    
    //    // Check for underflow  
    //    assert property (@(posedge clk_i) disable iff (!rst_n)
    //        pop |-> !empty)
    //    else $error("FIFO underflow: pop asserted when FIFO is empty");
    //    
    //    // Check pointer consistency
    //    assert property (@(posedge clk_i) disable iff (!rst_n)
    //        count <= DEPTH)
    //    else $error("FIFO count exceeds depth");
    //    
    //    // Check pop_data_valid timing
    //    assert property (@(posedge clk_i) disable iff (!rst_n)
    //        $rose(pop_data_valid) |-> $past(pop_enable))
    //    else $error("pop_data_valid asserted without previous pop_enable");
    //`endif

endmodule