module scoreboard_power_testbench;

    // Clock and reset
    logic clk;
    logic rst_n;
    
    // Test parameters
    parameter CLK_PERIOD = 2.5;
    
    // DUT signals
    logic [33:0] input_regs_map;    // Bitmap of current inputs to CGRA
    logic [7:0]  rd_tid;            // TID to be checked for collision
    logic [7:0]  rsv_tid;           // TID to reserve registers
    logic [255:0] wb_tid_bitmap;    // Bitmap of TIDs to release registers
    logic [6:0]  ld_dest_reg;       // Register number to be released
    logic collision;                // Collision detection result
    logic rd_valid;                 // Valid signal for read operation
    logic rsv_valid;                // Valid signal for reserve operation
    logic wb_valid;                 // Valid signal for write-back operation
    
    // Test tracking variables
    int test_count = 0;
    string current_test_name;
    
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT instantiation
    scoreboard dut (
        .clk(clk),
        .rst_n(rst_n),
        .input_regs_map(input_regs_map),
        .rd_tid(rd_tid),
        .rd_valid(rd_valid),
        .rsv_tid(rsv_tid),
        .rsv_valid(rsv_valid),
        .wb_tid_bitmap(wb_tid_bitmap),
        .wb_valid(wb_valid),
        .ld_dest_reg(ld_dest_reg),
        .collision(collision)
    );
    
    // Task to apply stimulus and measure power
    task automatic apply_stimulus_with_power(
        input string test_name,
        input [33:0] regs_map,
        input [7:0] read_tid,
        input logic read_en,
        input [7:0] reserve_tid,
        input logic reserve_en,
        input [255:0] writeback_bitmap,
        input [6:0] dest_reg,
        input logic writeback_en
    );
        begin
            current_test_name = test_name;
            input_regs_map = regs_map;
            rd_tid = read_tid;
            rd_valid = read_en;
            rsv_tid = reserve_tid;
            rsv_valid = reserve_en;
            wb_tid_bitmap = writeback_bitmap;
            wb_valid = writeback_en;
            ld_dest_reg = dest_reg;
            
            @(posedge clk);
            #1; // Wait for combinational logic to settle
        end
    endtask
    
    // Task to reset the design
    task automatic reset_dut();
        begin
            rst_n = 0;
            input_regs_map = 34'b0;
            rd_tid = 8'b0;
            rd_valid = 0;
            rsv_tid = 8'b0;
            rsv_valid = 0;
            wb_tid_bitmap = 256'b0;
            wb_valid = 0;
            ld_dest_reg = 7'b0;
            
            repeat(3) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask
    
    // Task to run idle cycles for baseline power
    task automatic run_idle_cycles(int num_cycles);
        begin
            for (int i = 0; i < num_cycles; i++) begin
                apply_stimulus_with_power(
                    .test_name($sformatf("IDLE_%0d", i)),
                    .regs_map(34'b0),
                    .read_tid(8'b0),
                    .read_en(1'b0),
                    .reserve_tid(8'b0),
                    .reserve_en(1'b0),
                    .writeback_bitmap(256'b0),
                    .dest_reg(7'b0),
                    .writeback_en(1'b0)
                );
            end
        end
    endtask
    
    // Main test sequence
    initial begin
        // Declare all variables at the beginning of the initial block
        logic [31:0] cycle_logic;
        logic [33:0] random_regs;
        logic [255:0] random_tids;
        logic enable_ops;
        logic [7:0] reserve_tid_val;
        logic [6:0] dest_reg_val;
        
        $display("=== Starting Scoreboard Power Model Testbench ===\n");
        
        reset_dut();
        
        // ============================================================
        // Test 1: Baseline Power (Idle Operation)
        // ============================================================
        $display("=== Test 1: Baseline Power Measurement: %0t ===", $time);
        run_idle_cycles(10);
        //display current time
        $display("Baseline power measurement complete. Current time: %0t", $time);
        // ============================================================
        // Test 2: Read Power Only (Various Scenarios)
        // ============================================================
        $display("\n=== Test 2: Read Power Measurement: %0t ===", $time);
        
        // Single read operations
        for (int tid = 0; tid < 256; tid++) begin
            apply_stimulus_with_power(
                .test_name($sformatf("READ_ONLY_TID_%0d", tid)),
                .regs_map(34'b0),
                .read_tid(tid[7:0]),
                .read_en(1'b1),
                .reserve_tid(8'b0),
                .reserve_en(1'b0),
                .writeback_bitmap(256'b0),
                .dest_reg(7'b0),
                .writeback_en(1'b0)
            );
        end
        //display current time
        $display("Single read operations complete. Current time: %0t", $time);
        
        // ============================================================
        // Test 3: Reserve Power Only (Various Register Counts)
        // ============================================================
        $display("\n=== Test 3: Reserve Power Measurement: %0t ===", $time);
        
        // Test different numbers of registers being reserved
        begin
            logic [33:0] reg_patterns[32] = '{
                34'h000000001,  // 1 register
                34'h000000003,  // 2 registers
                34'h000000007,  // 3 registers
                34'h00000000F,  // 4 registers
                34'h00000001F,  // 5 registers
                34'h00000003F,  // 6 registers
                34'h00000007F,  // 7 registers
                34'h0000000FF,  // 8 registers
                34'h0000001FF,  // 9 registers 
                34'h0000003FF,  // 10 registers
                34'h0000007FF,  // 11 registers
                34'h000000FFF,  // 12 registers
                34'h000001FFF,  // 13 registers
                34'h000003FFF,  // 14 registers
                34'h000007FFF,  // 15 registers
                34'h00000FFFF,  // 16 registers
                34'h00001FFFF,  // 17 registers
                34'h00003FFFF,  // 18 registers
                34'h00007FFFF,  // 19 registers
                34'h0000FFFFF,  // 20 registers
                34'h0001FFFFF,  // 21 registers
                34'h0003FFFFF,  // 22 registers
                34'h0007FFFFF,  // 23 registers
                34'h000FFFFFF,   // 24 registers
                34'h001FFFFFF,   // 25 registers
                34'h003FFFFFF,   // 26 registers
                34'h007FFFFFF,   // 27 registers
                34'h00FFFFFFF,   // 28 registers
                34'h01FFFFFFF,   // 29 registers
                34'h03FFFFFFF,   // 30 registers
                34'h07FFFFFFF,   // 31 registers
                34'h0FFFFFFFF   // 32 registers
            };
            
            for (int i = 0; i < 32; i++) begin
                for(int j=0;j<8;j++) begin
                    apply_stimulus_with_power(
                        .test_name($sformatf("RESERVE_PATTERN_%0d", i)),
                        .regs_map(reg_patterns[i]),
                        .read_tid(8'b0),
                        .read_en(1'b0),
                        .reserve_tid(j[7:0]+{i[4:0], 3'b0}), // Reserve TID based on pattern
                        .reserve_en(1'b1),
                        .writeback_bitmap(256'b0),
                        .dest_reg(7'b0),
                        .writeback_en(1'b0)
                    );
                end
            end
        end
        
        //display current time
        $display("Reserve power measurement complete. Current time: %0t", $time);
        // ============================================================
        // Test 4: Release Power Only (Various TID Counts)
        // ============================================================
        $display("\n=== Test 4: Release Power Measurement : %0t ===", $time);
        
        // Test different numbers of TIDs being released
        for (int tid_count = 1; tid_count <= 32; tid_count++) begin
            for(int j=0;j<8;j++) begin
                logic [255:0] tid_bitmap;
                tid_bitmap = 256'b0; // Initialize bitmap to zero
                for (int i = 31; i >= 32-tid_count; i--) begin
                    tid_bitmap[i*8+j] = 1'b1;
                end

                apply_stimulus_with_power(
                    .test_name($sformatf("RELEASE_%0d_TIDS", tid_count)),
                    .regs_map(34'b0),
                    .read_tid(8'b0),
                    .read_en(1'b0),
                    .reserve_tid(8'd100),
                    .reserve_en(1'b0),
                    .writeback_bitmap(tid_bitmap),
                    .dest_reg(7'd32-tid_count),
                    .writeback_en(1'b1)
                );
            end
        end
        
        //display current time
        $display("Release power measurement complete. Current time: %0t", $time);
        // ============================================================
        // Test 5: Combined Operations (Peak Power Scenarios)
        // ============================================================
        $display("\n=== Test 5: Combined Operations - Peak Power : %0t ===", $time);
        
        // Maximum power scenario: Read + Reserve all registers + Release many TIDs
        apply_stimulus_with_power(
            .test_name("PEAK_POWER_MAX"),
            .regs_map(34'hFF), // 8 registers
            .read_tid(8'd50),
            .read_en(1'b1),
            .reserve_tid(8'd51),
            .reserve_en(1'b1),
            .writeback_bitmap(256'hFFFF_FFFF), // All 32 TIDs
            .dest_reg(7'd5),
            .writeback_en(1'b1)
        );
        
        //display current time
        $display("Combined operations power measurement complete. Current time: %0t", $time);
        
        // ============================================================
        // Test 6: Stress Testing - Rapid Variations
        // ============================================================
        $display("\n=== Test 6: Stress Testing : %0t ===", $time);
        
        // Rapid variation test
        for (int cycle = 0; cycle < 50; cycle++) begin
            // Pseudo-random patterns based on cycle
            cycle_logic = cycle;
            random_regs = 34'h12345678 ^ (cycle_logic * 34'h1B7E151D);
            //random_tids = 256'h123456789ABCDEF ^ {224'b0, cycle_logic[31:0]};
            random_tids = {224'b0, cycle_logic[31:0]};
            enable_ops = (cycle_logic % 3) == 0;
            reserve_tid_val = (cycle_logic + 1);
            dest_reg_val = cycle_logic;
            
            apply_stimulus_with_power(
                .test_name($sformatf("STRESS_%0d", cycle)),
                .regs_map(random_regs & 34'h0F000000), // Mask to valid range
                .read_tid(cycle[7:0]),
                .read_en(enable_ops),
                .reserve_tid(reserve_tid_val),
                .reserve_en(enable_ops),
                .writeback_bitmap(random_tids),
                .dest_reg(dest_reg_val),
                .writeback_en(enable_ops)
            );
        end
        //display current time
        $display("Stress testing power measurement complete. Current time: %0t", $time);
        // ============================================================
        // Statistical Analysis and Power Model Validation
        // ============================================================
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("❌ TIMEOUT: Test took too long");
        $finish;
    end

    // VCD dump for waveform generation
    initial begin
        $dumpfile("scoreboard_power_testbench.vcd");
        $dumpvars(0, scoreboard_power_testbench);
    end

endmodule