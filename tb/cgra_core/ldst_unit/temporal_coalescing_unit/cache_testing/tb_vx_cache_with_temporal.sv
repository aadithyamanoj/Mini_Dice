module tb_vx_cache_with_temporal;
import dice_pkg::*;

    // --- Simulation Parameters ---
    parameter CLK_PERIOD = 2.5;
    
    // --- Cache Configuration Parameters ---
    parameter int NUM_REQS = 1; 
    parameter int MEM_PORTS = 1;
    parameter int MSHR_SIZE = 16;
    parameter int MSHR_BITS = $clog2(MSHR_SIZE);

    // --- Derived Parameters using DICE_PKG ---
    // Calculate Tag Width based on packed struct layout:
    // {BlockID, BaseTID, Bitmap, DestReg, AddrMap}
    parameter int OUTCMD_TAG_WIDTH = DICE_EBLOCK_ID_WIDTH + 
                                     DICE_TID_WIDTH + 
                                     DICE_TID_BITMAP_WIDTH + 
                                     DICE_MAX_REG_WIDTH + 
                                     (DICE_NUMBER_OF_MAX_COALESCED_COMMANDS * DICE_BASE_ADDRESS_OFFSET);

    parameter int MEM_TAG_WIDTH = OUTCMD_TAG_WIDTH + MSHR_BITS;
    parameter int MEM_ADDR_WIDTH = DICE_ADDR_WIDTH - DICE_BASE_ADDRESS_OFFSET; 

    // --- Signals ---
    bit clk, rst;
    
    // Input Command Interface
    bit incmd_valid;
    bit [DICE_EBLOCK_ID_WIDTH-1:0] incmd_block_id;
    bit [DICE_TID_WIDTH-1:0] incmd_tid;
    bit incmd_write_enable;
    bit [DICE_DATA_WIDTH-1:0] incmd_write_data;
    bit [(DICE_DATA_WIDTH/8)-1:0] incmd_write_mask; 
    bit [DICE_ADDR_WIDTH-1:0] incmd_address;
    bit [1:0] incmd_size;
    bit [DICE_MAX_REG_WIDTH-1:0] incmd_ld_dest_reg;
    bit outcmd_ready, core_rsp_ready;

    // Memory Interface
    bit mem_req_ready;
    bit mem_rsp_valid;
    bit [DICE_CACHE_LINE_SIZE*8-1:0] mem_rsp_data; // Assuming 256-bit wide memory interface
    bit [MEM_TAG_WIDTH-1:0] mem_rsp_tag;

    logic [DICE_CACHE_LINE_SIZE*8-1:0] core_rsp_data; 
    logic core_rsp_valid;
    logic [OUTCMD_TAG_WIDTH-1:0] core_rsp_tag;

    logic mem_req_valid, mem_req_rw;
    logic [DICE_CACHE_LINE_SIZE-1:0] mem_req_byteen;
    logic [MEM_ADDR_WIDTH-1:0] mem_req_addr;
    logic [DICE_CACHE_LINE_SIZE*8-1:0] mem_req_data;
    logic [MEM_TAG_WIDTH-1:0] mem_req_tag;
    logic mem_rsp_ready;

    // --- Clock generation ---
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // --- Memory Instance ---
    smem #(
        .DATA_W(256),
        .ADDR_W(MEM_ADDR_WIDTH),
        .TAG_W(MEM_TAG_WIDTH)
    ) mem_inst (
        .clk(clk), .rst(rst),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_rw(mem_req_rw), .mem_req_addr(mem_req_addr),
        .mem_req_data(mem_req_data), .mem_req_byteen(mem_req_byteen),
        .mem_req_tag(mem_req_tag), .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_ready(mem_rsp_ready), .mem_rsp_data(mem_rsp_data),
        .mem_rsp_tag(mem_rsp_tag)
    );

    // --- DUT Instance ---
    // Only passing parameters that differ from defaults or are local to TB
    VX_cache_with_temporal #(
        .NUM_REQS(NUM_REQS),
        .MEM_PORTS(MEM_PORTS),
        .OUTCMD_TAG_WIDTH(OUTCMD_TAG_WIDTH),
        .MSHR_SIZE(MSHR_SIZE)
    ) dut (
        .clk(clk), .rst(rst),
        .incmd_valid(incmd_valid), .incmd_block_id(incmd_block_id),
        .incmd_tid(incmd_tid), .incmd_write_enable(incmd_write_enable),
        .incmd_write_data(incmd_write_data), .incmd_write_mask(incmd_write_mask),
        .incmd_address(incmd_address), .incmd_size(incmd_size),
        .incmd_ld_dest_reg(incmd_ld_dest_reg), .outcmd_ready(outcmd_ready),
        .core_rsp_data(core_rsp_data), .core_rsp_valid(core_rsp_valid),
        .core_rsp_tag(core_rsp_tag), .core_rsp_ready(core_rsp_ready),
        .mem_req_valid(mem_req_valid), .mem_req_rw(mem_req_rw),
        .mem_req_byteen(mem_req_byteen), .mem_req_addr(mem_req_addr),
        .mem_req_data(mem_req_data), .mem_req_tag(mem_req_tag),
        .mem_req_ready(mem_req_ready), .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_data(mem_rsp_data), .mem_rsp_tag(mem_rsp_tag),
        .mem_rsp_ready(mem_rsp_ready)
    );

    // --- Read Task ---
    task send_read_request(input [DICE_ADDR_WIDTH-1:0] addr, input [DICE_TID_WIDTH-1:0] tid);
    begin
        @(posedge clk);
        incmd_valid   = 1;
        incmd_address = addr;
        incmd_tid     = tid;
        incmd_write_enable = 0;
        incmd_size    = 2'b10; // 4-byte read
        
        wait(dut.incmd_ready == 1'b1); 
        @(posedge clk);
        incmd_valid   = 0;

        fork
            begin
                wait(core_rsp_valid == 1'b1);
                @(posedge clk); 
            end
            begin
                #(CLK_PERIOD * 300);
                $display("[TB] TIMEOUT waiting for read response addr=%h", addr);
            end
        join_any
        disable fork;
    end
    endtask

    // --- TASK: WRITE REQUEST ---
    task send_write_request(
        input [DICE_ADDR_WIDTH-1:0] addr, 
        input [DICE_DATA_WIDTH-1:0] data, 
        input [(DICE_DATA_WIDTH/8)-1:0] mask, 
        input [DICE_TID_WIDTH-1:0] tid
    );
    begin
        @(posedge clk);
        incmd_valid        = 1;
        incmd_address      = addr;
        incmd_tid          = tid;
        incmd_write_enable = 1;
        incmd_write_data   = data;
        incmd_write_mask   = mask;
        incmd_size         = 2'b10; // 4 Bytes
        
        wait(dut.incmd_ready == 1'b1);
        @(posedge clk);
        incmd_valid        = 0;
        incmd_write_enable = 0;
    end
    endtask

    // --- Monitor Logic ---
    // Calculating offsets based on struct packing order (MSB -> LSB):
    // {BlockID, BaseTID, Bitmap, DestReg, AddrMap}
    localparam int BITMAP_OFFSET = (DICE_NUMBER_OF_MAX_COALESCED_COMMANDS * DICE_BASE_ADDRESS_OFFSET) + DICE_MAX_REG_WIDTH;
    localparam int BASE_TID_OFFSET = BITMAP_OFFSET + DICE_TID_BITMAP_WIDTH;

    wire [DICE_TID_WIDTH-1:0] rsp_base_tid = core_rsp_tag[BASE_TID_OFFSET +: DICE_TID_WIDTH];
    wire [DICE_TID_BITMAP_WIDTH-1:0] rsp_bitmap = core_rsp_tag[BITMAP_OFFSET +: DICE_TID_BITMAP_WIDTH];

    always @(posedge clk) begin
        if (core_rsp_valid && core_rsp_ready) begin
            $display("[MONITOR] Time: %0t | BaseTID: %0d | Bitmap: %b | Full Line Data: %h", 
                     $time, rsp_base_tid, rsp_bitmap, core_rsp_data);
        end
    end

    initial begin
        incmd_valid = 0;
        outcmd_ready = 1;
        core_rsp_ready = 1; 
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        repeat(5) @(posedge clk);

        $display("--- Starting Write Coalescing Test (Addr 0x100) ---");
        // Address offsets increment by 4 for 32-bit words
        send_write_request(32'h0000_0100, 32'h1111_1111, 4'h0, 0); 
        send_write_request(32'h0000_0104, 32'h2222_2222, 4'h0, 1); 
        send_write_request(32'h0000_0108, 32'h3333_3333, 4'h0, 2); 
        send_write_request(32'h0000_010C, 32'h4444_4444, 4'h0, 3); 
        send_write_request(32'h0000_0110, 32'h5555_5555, 4'h0, 4); 
        send_write_request(32'h0000_0114, 32'h6666_6666, 4'h0, 5); 
        send_write_request(32'h0000_0118, 32'h7777_7777, 4'h0, 6); 
        send_write_request(32'h0000_011C, 32'h8888_8888, 4'h0, 7); 

        #(CLK_PERIOD * 100);

        $display("--- Reading back Addr 0x100 ---");
        fork
            begin
                send_read_request(32'h0000_0100, 0);
                send_read_request(32'h0000_0104, 0);
                send_read_request(32'h0000_0108, 0);
            end
            begin
                #(CLK_PERIOD * 2000); 
                if (core_rsp_valid == 0) begin
                    $display("[TB] CRITICAL TIMEOUT: Memory did not respond in time for Addr 0x100");
                end
            end
        join_any
        disable fork;

        #(CLK_PERIOD * 100);
        
        $display("--- Starting Linear Word Sweep ---");
        for (int j = 0; j < 8; j++) begin
            send_read_request(.addr(j * 4), .tid(j)); // Increments by 4
            #(CLK_PERIOD * 50); 
        end

        #(CLK_PERIOD * 100);

        $display("Temporal timeout");
        // Adjusted literal and mask for 32-bit
        send_write_request(32'h0000_0200, 32'hABCD_DCBA, 4'h0, 3);
        #(CLK_PERIOD * 1000);

        send_read_request(32'h0000_0200, 0);
        #(CLK_PERIOD * 1000);

        $display("--- All Tests Complete ---");
        $finish;
    end

    initial begin
        $fsdbDumpfile("tb_vx_cache_with_temporal.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule