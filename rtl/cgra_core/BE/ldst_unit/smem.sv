module smem #(
    parameter DATA_W = 256,
    parameter ADDR_W = 27,
    parameter TAG_W  = 48,
    parameter MEM_DEPTH = 4096
)(
    input  logic clk,
    input  logic rst,

    // Memory request interface
    input  logic mem_req_valid,
    output logic mem_req_ready,
    input  logic mem_req_rw,
    input  logic [ADDR_W-1:0] mem_req_addr,
    input  logic [DATA_W-1:0] mem_req_data,
    input  logic [DATA_W/8-1:0] mem_req_byteen,
    input  logic [TAG_W-1:0] mem_req_tag,

    // Memory response interface
    output logic mem_rsp_valid,
    input  logic mem_rsp_ready,
    output logic [DATA_W-1:0] mem_rsp_data,
    output logic [TAG_W-1:0] mem_rsp_tag
);
 
    logic [DATA_W-1:0] mem [0:MEM_DEPTH-1];

    // Control Registers
    logic rd_valid, pending_valid;
    logic [DATA_W-1:0] read_data, pending_data;
    logic [TAG_W-1:0] rd_tag, pending_tag;

    assign mem_req_ready = 1'b1;

    // ---------------------------------------------------------
    // COMBINED MEMORY BLOCK: Using a single block for everything
    // ---------------------------------------------------------

    initial begin
        for (int i = 0; i < 4096; i = i + 1) begin
            // Replicating your Python logic: W3 | W2 | W1 | W0
            mem[i] = {64'h3333333333333333, 
                    64'h2222222222222222, 
                    64'h1111111111111111, 
                    64'h00000000deadbeef};
        end
    end

    // Use a standard 'always' instead of 'always_ff' for the memory array 
    // to satisfy strict tool check rules for memory modeling.
    always @(posedge clk) begin
        if (mem_req_valid && mem_req_rw) begin
            for (int i = 0; i < DATA_W/8; i++) begin
                if (mem_req_byteen[i])
                    mem[mem_req_addr][8*i +: 8] <= mem_req_data[8*i +: 8];
            end
        end
    end

    // ---------------------------------------------------------
    // CONTROL LOGIC: Stay in always_ff
    // ---------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            rd_valid      <= 1'b0;
            pending_valid <= 1'b0;
            mem_rsp_valid <= 1'b0;
            read_data     <= '0;
            pending_data  <= '0;
            mem_rsp_data  <= '0;
            rd_tag        <= '0;
            pending_tag   <= '0;
            mem_rsp_tag   <= '0;
        end else begin
            // Read handling
            if (mem_req_valid && !mem_req_rw) begin
                if (!rd_valid) begin
                    rd_valid   <= 1'b1;
                    read_data  <= mem[mem_req_addr];
                    rd_tag     <= mem_req_tag;
                end else if (!pending_valid) begin
                    pending_valid <= 1'b1;
                    pending_data  <= mem[mem_req_addr];
                    pending_tag   <= mem_req_tag;
                end
            end

            // Response Handshake
            if (!mem_rsp_valid && rd_valid) begin
                mem_rsp_valid <= 1'b1;
                mem_rsp_data  <= read_data;
                mem_rsp_tag   <= rd_tag;
                if (pending_valid) begin
                    read_data     <= pending_data;
                    rd_tag        <= pending_tag;
                    pending_valid <= 1'b0;
                    rd_valid      <= 1'b1;
                end else begin
                    rd_valid      <= 1'b0;
                end
            end

            if (mem_rsp_valid && mem_rsp_ready) begin
                mem_rsp_valid <= 1'b0;
            end
        end
    end

endmodule