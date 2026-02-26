`timescale 1ns/1ps

module tb_block_commit_table;
import dice_pkg::*;
    // Parameters
    parameter R_W = 14;
    parameter CLK_PERIOD = 2.5; // 400MHz clock (2.5ns period)
    
    // DUT signals
    logic                                    clk;
    logic                                    rst;
    
    // Entry insert interface
    logic                                    insert_valid;
    logic [DICE_HW_CTA_ID_WIDTH-1:0]        insert_hw_cta_id;
    logic [DICE_EBLOCK_ID_WIDTH-1:0]          insert_e_block_id;
    logic [R_W-1:0]                            insert_pending_reads;
    logic [R_W-1:0]                            insert_pending_writes;
    
    // Pending read/write update interface
    logic                                    update_valid;
    logic [DICE_EBLOCK_ID_WIDTH-1:0]          update_e_block_id;
    logic                                    update_is_write;
    logic [2**DICE_HW_CTA_ID_WIDTH-1:0]                             update_reduce_count;
    
    // E-block commit interface
    logic                                    pop_valid;
    logic [DICE_EBLOCK_ID_WIDTH-1:0]          pop_e_block_id;
    logic                                    pop_ready;
    
    // Testbench variables
    int test_passed;
    int test_failed;
    logic [2**DICE_HW_CTA_ID_WIDTH-1:0]         hw_cta_pending;
    
    // DUT instantiation
    block_commit_table #(
    ) dut (
        .clk(clk),
        .rst(rst),
        .insert_valid(insert_valid),
        .insert_hw_cta_id(insert_hw_cta_id),
        .insert_e_block_id(insert_e_block_id),
        .insert_pending_reads(insert_pending_reads),
        .insert_pending_writes(insert_pending_writes),
        .update_valid(update_valid),
        .update_e_block_id(update_e_block_id),
        .update_is_write(update_is_write),
        .update_reduce_count(update_reduce_count),
        .pop_valid(pop_valid),
        .pop_e_block_id(pop_e_block_id),
        .pop_ready(pop_ready),
        .hw_cta_pending(hw_cta_pending)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        rst = 1;
        insert_valid = 0;
        insert_hw_cta_id = 0;
        insert_e_block_id = 0;
        insert_pending_reads = 0;
        insert_pending_writes = 0;
        update_valid = 0;
        update_e_block_id = 0;
        update_is_write = 0;
        update_reduce_count = 0;
        pop_ready = 1;
        test_passed = 0;
        test_failed = 0;
        
        // Reset
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        $display("\n========================================");
        $display("Starting Block Commit Table Testbench");
        $display("MAX_NUM_CTA=%0d, EBLOCK_ID_WIDTH=%0d", DICE_HW_CTA_ID_WIDTH, DICE_EBLOCK_ID_WIDTH);
        $display("========================================\n");
        
        // Test 1: Basic insert and commit
        test_basic_insert_commit();
        
        // Test 2: Multiple inserts with different e_block_ids
        test_multiple_inserts();
        
        // Test 4: Round-robin commit priority
        test_round_robin_priority();
        
        // Test 5: Pop ready flow control
        test_pop_ready_flow_control();
        
        // Final report
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("Test Summary:");
        $display("Passed: %0d", test_passed);
        $display("Failed: %0d", test_failed);
        $display("========================================\n");
        if (test_failed > 0) begin
            $display("ERROR: Some tests failed!");
        end else begin
            $display("Great! All tests passed successfully!\n\n");
        end
        $finish;
    end
    
    // Test tasks
    task test_basic_insert_commit();
        $display("\n[Test 1] Basic insert and commit");
        
        // Insert entry with zero pending counts (should commit immediately)
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 3;
        insert_hw_cta_id = 2;
        insert_pending_reads = 0;
        insert_pending_writes = 0;
        // Check for immediate commit
        @(posedge clk);
        if (pop_valid && pop_e_block_id == 3) begin
            $display("  PASS: Entry committed immediately with zero pending counts");
            test_passed++;
        end else begin
            $display("  FAIL: Entry not committed");
            test_failed++;
        end
        insert_valid = 0;
        @(posedge clk);
    endtask
    
    task test_multiple_inserts();
        $display("\n[Test 2] Multiple inserts with different e_block_ids");
        
        // Insert multiple entries
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            @(posedge clk);
            insert_valid = 1;
            insert_e_block_id = i;
            insert_hw_cta_id = i[1:0];
            insert_pending_reads = 10 + i;
            insert_pending_writes = 5 + i;
            @(posedge clk);
            insert_valid = 0;
            if (hw_cta_pending[i]) begin
                $display("  PASS: Entry successfully inserted with pending counts");
                test_passed++;
            end else begin
                $display("  FAIL: Entry not inserted correctly");
                test_failed++;
            end
        end

        // Clear entries for next test - reduce by max of 8 at a time
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            // Reduce reads
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = i;
            update_is_write = 0;
            update_reduce_count = 8;  // First reduction of 8
            @(posedge clk);
            update_reduce_count = (10 + i) - 8;  // Remaining amount (2, 3, 4, 5)
            @(posedge clk);
            update_valid = 0;
            
            // Reduce writes
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = i;
            update_is_write = 1;
            update_reduce_count = 5 + i;  // All writes are <= 8
            @(posedge clk);
            update_valid = 0;
            @(posedge clk);
            if (!hw_cta_pending[i]) begin
                $display("  PASS: Entry successfully popped after pending counts reached zero");
                test_passed++;
            end else begin
                $display("  FAIL: Entry not popped correctly");
                test_failed++;
            end
        end
        
        repeat(5) @(posedge clk);
    endtask
    
    task test_round_robin_priority();
        logic [2:0] commit_order;
        
        $display("\n[Test 4] Round-robin commit priority");
        
        commit_order = 0;
        
        // Insert multiple entries that will be ready simultaneously
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            @(posedge clk);
            insert_valid = 1;
            insert_e_block_id = i;
            insert_hw_cta_id = i[1:0];
            insert_pending_reads = 8;
            insert_pending_writes = 8;
            @(posedge clk);
            insert_valid = 0;
        end
        
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            if (hw_cta_pending[i]) begin
                $display("  PASS: Entry successfully inserted with pending counts");
                test_passed++;
            end else begin
                $display("  FAIL: Entry not inserted correctly");
                test_failed++;
            end
        end

        @(posedge clk);
        pop_ready = 0;
        // Clear entries for next test - reduce by max of 8 at a time
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            // Reduce reads
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = i;
            update_is_write = 0;
            update_reduce_count = 8;  // First reduction of 8
            @(posedge clk);
            update_valid = 0;
            
            // Reduce writes
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = i;
            update_is_write = 1;
            update_reduce_count = 8;  // All writes are <= 8
            @(posedge clk);
            update_valid = 0;
        end

        @(posedge clk);
        pop_ready = 1;
        // Check commit order
        for (int i = 0; i < 2**DICE_HW_CTA_ID_WIDTH; i++) begin
            @(posedge clk)
            if (!hw_cta_pending[i]) begin
                $display("  PASS: Entry successfully popped in round-robin order");
                test_passed++;
            end else begin
                $display("  FAIL: Entry not popped correctly");
                test_failed++;
            end
        end
        
        repeat(2) @(posedge clk);
    endtask
    
    task test_pop_ready_flow_control();
        $display("\n[Test 5] Pop ready flow control");
        // Set pop_ready to 0
        @(posedge clk);
        pop_ready = 0;

        // Insert entry ready to commit
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 7;
        insert_hw_cta_id = 3;
        insert_pending_reads = 0;
        insert_pending_writes = 0;
        @(posedge clk);
        insert_valid = 0;
        

        
        // Check that entry is not cleared
        repeat(5) @(posedge clk);
        if (pop_valid && hw_cta_pending[3]) begin
            $display("  PASS: Entry held when pop_ready is low");
            test_passed++;
        end else begin
            $display("  FAIL: pop_valid not asserted");
            test_failed++;
        end
        

        @(posedge clk);
        // Set pop_ready to 1
        pop_ready = 1;
        
        // Verify entry is cleared
        @(posedge clk);
        if (!pop_valid && !hw_cta_pending[3]) begin
            $display("  PASS: Entry cleared when pop_ready went high");
            test_passed++;
        end else begin
            $display("  FAIL: Entry not cleared");
            test_failed++;
        end
        
        repeat(2) @(posedge clk);
    endtask

    
    // Timeout watchdog
    initial begin
        #2500000;  // 2.5ms timeout for 400MHz clock
        $display("\nERROR: Testbench timeout!");
        $finish;
    end
    
    // VCD dump for waveform viewing
    initial begin
        `ifdef XCELIUM
            $recordfile("block_commit_table.trn");
            $recordvars("");
        `endif
        
        $dumpfile("block_commit_table.vcd");
        $dumpvars(0, tb_block_commit_table);
    end

endmodule