module scoreboard_testbench;

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
    int pass_count = 0;
    int fail_count = 0;
    
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
    
    // Task to check test result
    task automatic check_result(
        input string test_name,
        input logic expected_collision,
        input string description
    );
        begin
            test_count++;
            
            if (collision === expected_collision) begin
                $display("✅ PASS: %s - %s", test_name, description);
                $display("   Expected collision: %b, Got: %b", expected_collision, collision);
                pass_count++;
            end else begin
                $display("❌ FAIL: %s - %s", test_name, description);
                $display("   Expected collision: %b, Got: %b", expected_collision, collision);
                fail_count++;
            end
            $display("");
        end
    endtask
    
    // Task to apply stimulus and wait
    task automatic apply_stimulus(
        input [33:0] regs_map,
        input [7:0] read_tid,
        input [7:0] reserve_tid,
        input [255:0] writeback_bitmap,
        input [6:0] dest_reg
    );
        begin
            input_regs_map = regs_map;
            rd_tid = read_tid;
            rd_valid = 1; // Always valid for read operation
            rsv_tid = reserve_tid;
            rsv_valid = 1; // Always valid for reserve operation
            wb_tid_bitmap = writeback_bitmap;
            wb_valid = (writeback_bitmap != 256'b0); // Valid if any TID is set in bitmap
            ld_dest_reg = dest_reg;
            
            // Wait for one clock cycle and then check combinational result
            @(posedge clk);
            #1; // Wait for combinational logic to settle
        end
    endtask

    task automatic reset_valid();
        begin
            rd_valid = 0;
            rsv_valid = 0;
            wb_valid = 0;
            @(posedge clk);
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
    
    // Main test sequence
    initial begin
        $display("=== Starting Scoreboard Testbench ===\n");
        
        // Initialize
        reset_dut();
        
        // ============================================================
        // Test 1: Basic reservation without collision
        // ============================================================
        $display("=== Test 1: Basic Reservation ===");
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0111), // Reserve regs 0,1,2
            .read_tid(8'd10),
            .reserve_tid(8'd5),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 1a", 1'b0, "No collision on fresh reservation");
        reset_valid();
        // ============================================================
        // Test 2: Read collision detection
        // ============================================================
        $display("=== Test 2: Read Collision Detection ===");
        
        // First reserve some registers for TID 5
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_1111), // Reserve regs 0,1,2,3
            .read_tid(8'd10),
            .reserve_tid(8'd5),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        // Now try to read from TID 5 with overlapping registers
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0110), // Want to use regs 1,2
            .read_tid(8'd5),  // Reading from TID 5 which has regs 0,1,2,3 reserved
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 2a", 1'b1, "Collision detected on overlapping registers");
        reset_valid();
        // Try reading with non-overlapping registers
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_1111_0000), // Want to use regs 4,5,6,7
            .read_tid(8'd5),  // Reading from TID 5 which has regs 0,1,2,3 reserved
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 2b", 1'b0, "No collision on non-overlapping registers");
        reset_valid();
        // ============================================================
        // Test 3: Write-back register release
        // ============================================================
        $display("=== Test 3: Write-back Register Release ===");
        
        // Release register 1 from TID 5
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0010), // Want to use reg 1
            .read_tid(8'd5),
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b1 << 5), // Release from TID 5
            .dest_reg(7'd1) // Release register 1
        );
        check_result("Test 3a", 1'b1, "Collision due to wb_tid_bitmap conflict");
        reset_valid();
        // After write-back, check if register 1 is released
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0010), // Want to use reg 1
            .read_tid(8'd5),
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 3b", 1'b0, "No collision after register 1 released");
        reset_valid();
        // ============================================================
        // Test 4: Fusion case (rsv_tid overlaps with wb_tid_bitmap)
        // ============================================================
        $display("=== Test 4: Fusion Case ===");
        
        // Set up TID 7 with some registers
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_1111_0000), // Reserve regs 4,5,6,7
            .read_tid(8'd10),
            .reserve_tid(8'd7),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        // Fusion: Reserve new registers for TID 7 while releasing register 5
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_1111), // Reserve regs 0,1,2,3
            .read_tid(8'd10),
            .reserve_tid(8'd7), // Same TID for reservation
            .writeback_bitmap(256'b1 << 7), // Release from TID 7
            .dest_reg(7'd5) // Release register 5
        );
        
        // Check if TID 7 now has regs 0,1,2,3,4,6,7 (reg 5 should be released)
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0010_0000), // Want to use reg 5
            .read_tid(8'd7),
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 4a", 1'b0, "Register 5 should be released in fusion");
        reset_valid();
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0001), // Want to use reg 0
            .read_tid(8'd7),
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 4b", 1'b1, "Register 0 should be reserved in fusion");
        reset_valid();
        // ============================================================
        // Test 5: Multiple TID write-backs
        // ============================================================
        $display("=== Test 5: Multiple TID Write-backs ===");
        
        // Set up multiple TIDs with registers
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_1111), // Reserve regs 0,1,2,3
            .read_tid(8'd10),
            .reserve_tid(8'd10),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_1111_0000), // Reserve regs 4,5,6,7
            .read_tid(8'd10),
            .reserve_tid(8'd11),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        // Release register 2 from multiple TIDs
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0100), // Want to use reg 2
            .read_tid(8'd10),
            .reserve_tid(8'd12),
            .writeback_bitmap((256'b1 << 10) | (256'b1 << 11)), // Release from TID 10 and 11
            .dest_reg(7'd2)
        );
        check_result("Test 5a", 1'b1, "Collision due to wb_tid_bitmap for read TID");
        reset_valid();
        // ============================================================
        // Test 6: Special registers (CR=32, PR=33)
        // ============================================================
        $display("=== Test 6: Special Registers ===");
        
        // Reserve condition register (CR)
        apply_stimulus(
            .regs_map(34'b0100_0000_0000_0000_0000_0000_0000_0000), // Reserve CR (bit 32)
            .read_tid(8'd10),
            .reserve_tid(8'd20),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        // Check collision on CR
        apply_stimulus(
            .regs_map(34'b0100_0000_0000_0000_0000_0000_0000_0000), // Want to use CR
            .read_tid(8'd20),
            .reserve_tid(8'd21),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 6a", 1'b1, "Collision on condition register (CR)");
        reset_valid();
        // Reserve predicate register (PR)
        apply_stimulus(
            .regs_map(34'b1000_0000_0000_0000_0000_0000_0000_0000), // Reserve PR (bit 33)
            .read_tid(8'd10),
            .reserve_tid(8'd22),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        // Release PR
        apply_stimulus(
            .regs_map(34'b1000_0000_0000_0000_0000_0000_0000_0000), // Want to use PR
            .read_tid(8'd22),
            .reserve_tid(8'd23),
            .writeback_bitmap(256'b1 << 22), // Release from TID 22
            .dest_reg(7'd33) // Release PR
        );
        check_result("Test 6b", 1'b1, "wb_tid_bitmap conflict on PR release");
        reset_valid();
        // ============================================================
        // Test 7: Edge cases
        // ============================================================
        $display("=== Test 7: Edge Cases ===");
        
        // Test with all registers reserved
        apply_stimulus(
            .regs_map(34'h3_FFFF_FFFF), // All 34 bits set
            .read_tid(8'd10),
            .reserve_tid(8'd50),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        
        apply_stimulus(
            .regs_map(34'b0000_0000_0000_0000_0000_0000_0000_0001), // Want to use reg 0
            .read_tid(8'd50),
            .reserve_tid(8'd51),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 7a", 1'b1, "Collision when all registers reserved");
        reset_valid();
        // Test with no registers reserved
        apply_stimulus(
            .regs_map(34'h3_FFFF_FFFF), // Want all registers
            .read_tid(8'd100), // Fresh TID
            .reserve_tid(8'd51),
            .writeback_bitmap(256'b0),
            .dest_reg(7'd0)
        );
        check_result("Test 7b", 1'b0, "No collision on fresh TID");
        reset_valid();
        // ============================================================
        // Final Results
        // ============================================================
        $display("\n=== Test Summary ===");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("🎉 ALL TESTS PASSED!");
        end else begin
            $display("💥 %0d TESTS FAILED", fail_count);
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 1000);
        $display("❌ TIMEOUT: Test took too long");
        $finish;
    end

        // VCD dump for waveform generation
    initial begin
        $dumpfile("scoreboard_testbench.vcd");
        $dumpvars(0, scoreboard_testbench);
    end

endmodule