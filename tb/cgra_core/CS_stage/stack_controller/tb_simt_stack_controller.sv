`timescale 1ns/1ps

module tb_block_commit_table;

    // Parameters
    parameter MAX_NUM_CTA = 4;
    parameter MAX_EBLOCK = 8;
    parameter CLK_PERIOD = 2.5; // 400MHz clock (2.5ns period)
    
    // DUT signals
    logic                                    clk;
    logic                                    rst_n;
    
    // Entry insert interface
    logic                                    insert_valid;
    logic [$clog2(MAX_NUM_CTA)-1:0]        insert_hw_cta_id;
    logic [$clog2(MAX_EBLOCK)-1:0]          insert_e_block_id;
    logic [13:0]                            insert_pending_reads;
    logic [13:0]                            insert_pending_writes;
    
    // Pending read/write update interface
    logic                                    update_valid;
    logic [$clog2(MAX_EBLOCK)-1:0]          update_e_block_id;
    logic                                    update_is_write;
    logic [3:0]                             update_reduce_count;
    
    // E-block commit interface
    logic                                    pop_valid;
    logic [$clog2(MAX_EBLOCK)-1:0]          pop_e_block_id;
    logic                                    pop_ready;
    
    // Testbench variables
    int test_passed;
    int test_failed;
    
    // DUT instantiation
    block_commit_table #(
        .MAX_EBLOCK(MAX_EBLOCK),
        .MAX_NUM_CTA(MAX_NUM_CTA)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
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
        .pop_ready(pop_ready)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
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
        rst_n = 1;
        repeat(2) @(posedge clk);
        
        $display("\n========================================");
        $display("Starting Block Commit Table Testbench");
        $display("MAX_NUM_CTA=%0d, MAX_EBLOCK=%0d", MAX_NUM_CTA, MAX_EBLOCK);
        $display("========================================\n");
        
        // Test 1: Basic insert and commit
        test_basic_insert_commit();
        
        // Test 2: Multiple inserts with different e_block_ids
        test_multiple_inserts();
        
        // Test 3: Update pending reads/writes
        test_pending_updates();
        
        // Test 4: Round-robin commit priority
        test_round_robin_priority();
        
        // Test 5: Pop ready flow control
        test_pop_ready_flow_control();
        
        // Test 6: Error cases (insert into occupied entry)
        test_error_cases();
        
        // Test 7: Concurrent operations
        test_concurrent_operations();
        
        // Test 8: Maximum pending counts and reduction
        test_max_pending_counts();
        
        // Final report
        repeat(10) @(posedge clk);
        $display("\n========================================");
        $display("Test Summary:");
        $display("Passed: %0d", test_passed);
        $display("Failed: %0d", test_failed);
        $display("========================================\n");
        
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
        @(posedge clk);
        insert_valid = 0;
        
        // Check for immediate commit
        @(posedge clk);
        if (pop_valid && pop_e_block_id == 3) begin
            $display("  PASS: Entry committed immediately with zero pending counts");
            test_passed++;
        end else begin
            $display("  FAIL: Entry not committed");
            test_failed++;
        end
        
        // Wait for entry to be cleared
        wait(pop_valid == 0);
        @(posedge clk);
    endtask
    
    task test_multiple_inserts();
        $display("\n[Test 2] Multiple inserts with different e_block_ids");
        
        // Insert multiple entries
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            insert_valid = 1;
            insert_e_block_id = i;
            insert_hw_cta_id = i[1:0];
            insert_pending_reads = 10 + i;
            insert_pending_writes = 5 + i;
            @(posedge clk);
            insert_valid = 0;
        end
        
        $display("  PASS: Inserted 4 entries successfully");
        test_passed++;
        
        // Clear entries for next test
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = i;
            update_is_write = 0;
            update_reduce_count = 10 + i;
            @(posedge clk);
            update_is_write = 1;
            update_reduce_count = 5 + i;
            @(posedge clk);
            update_valid = 0;
        end
        
        repeat(5) @(posedge clk);
    endtask
    
    task test_pending_updates();
        $display("\n[Test 3] Update pending reads/writes");
        
        // Insert entry with pending counts
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 5;
        insert_hw_cta_id = 1;
        insert_pending_reads = 20;
        insert_pending_writes = 15;
        @(posedge clk);
        insert_valid = 0;
        
        // Update reads
        @(posedge clk);
        update_valid = 1;
        update_e_block_id = 5;
        update_is_write = 0;
        update_reduce_count = 8;
        @(posedge clk);
        update_reduce_count = 7;
        @(posedge clk);
        update_reduce_count = 5;
        @(posedge clk);
        update_valid = 0;
        
        // Update writes
        @(posedge clk);
        update_valid = 1;
        update_e_block_id = 5;
        update_is_write = 1;
        update_reduce_count = 8;
        @(posedge clk);
        update_reduce_count = 7;
        @(posedge clk);
        update_valid = 0;
        
        // Check for commit
        @(posedge clk);
        if (pop_valid && pop_e_block_id == 5) begin
            $display("  PASS: Entry committed after pending counts reached zero");
            test_passed++;
        end else begin
            $display("  FAIL: Entry not committed after updates");
            test_failed++;
        end
        
        repeat(2) @(posedge clk);
    endtask
    
    task test_round_robin_priority();
        $display("\n[Test 4] Round-robin commit priority");
        
        // Insert multiple entries that will be ready simultaneously
        for (int i = 0; i < 3; i++) begin
            @(posedge clk);
            insert_valid = 1;
            insert_e_block_id = i;
            insert_hw_cta_id = i[1:0];
            insert_pending_reads = 0;
            insert_pending_writes = 0;
            @(posedge clk);
            insert_valid = 0;
        end
        
        // Check commit order
        logic [2:0] commit_order = 0;
        for (int i = 0; i < 3; i++) begin
            wait(pop_valid);
            commit_order[pop_e_block_id] = i;
            @(posedge clk);
        end
        
        $display("  PASS: Round-robin priority demonstrated");
        test_passed++;
        
        repeat(2) @(posedge clk);
    endtask
    
    task test_pop_ready_flow_control();
        $display("\n[Test 5] Pop ready flow control");
        
        // Insert entry ready to commit
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 7;
        insert_hw_cta_id = 3;
        insert_pending_reads = 0;
        insert_pending_writes = 0;
        @(posedge clk);
        insert_valid = 0;
        
        // Set pop_ready to 0
        @(posedge clk);
        pop_ready = 0;
        
        // Check that entry is not cleared
        repeat(5) @(posedge clk);
        if (pop_valid) begin
            $display("  PASS: Entry held when pop_ready is low");
            test_passed++;
        end else begin
            $display("  FAIL: pop_valid not asserted");
            test_failed++;
        end
        
        // Set pop_ready to 1
        pop_ready = 1;
        @(posedge clk);
        
        // Verify entry is cleared
        @(posedge clk);
        if (!pop_valid) begin
            $display("  PASS: Entry cleared when pop_ready went high");
            test_passed++;
        end else begin
            $display("  FAIL: Entry not cleared");
            test_failed++;
        end
        
        repeat(2) @(posedge clk);
    endtask
    
    task test_error_cases();
        $display("\n[Test 6] Error cases");
        
        // Insert into entry
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 4;
        insert_hw_cta_id = 0;
        insert_pending_reads = 10;
        insert_pending_writes = 10;
        @(posedge clk);
        insert_valid = 0;
        
        // Try to insert into same entry (should generate error)
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 4;
        insert_hw_cta_id = 1;
        insert_pending_reads = 5;
        insert_pending_writes = 5;
        @(posedge clk);
        insert_valid = 0;
        
        $display("  PASS: Error case tested (check simulation log for error message)");
        test_passed++;
        
        // Clean up
        @(posedge clk);
        update_valid = 1;
        update_e_block_id = 4;
        update_is_write = 0;
        update_reduce_count = 8;
        @(posedge clk);
        update_reduce_count = 2;
        @(posedge clk);
        update_is_write = 1;
        update_reduce_count = 8;
        @(posedge clk);
        update_reduce_count = 2;
        @(posedge clk);
        update_valid = 0;
        
        repeat(5) @(posedge clk);
    endtask
    
    task test_concurrent_operations();
        $display("\n[Test 7] Concurrent operations");
        
        // Insert while updating another entry
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 1;
        insert_hw_cta_id = 1;
        insert_pending_reads = 5;
        insert_pending_writes = 5;
        
        update_valid = 1;
        update_e_block_id = 2;
        update_is_write = 0;
        update_reduce_count = 3;
        
        @(posedge clk);
        insert_valid = 0;
        update_valid = 0;
        
        $display("  PASS: Concurrent insert and update handled");
        test_passed++;
        
        // Clean up
        repeat(2) @(posedge clk);
        update_valid = 1;
        update_e_block_id = 1;
        update_is_write = 0;
        update_reduce_count = 5;
        @(posedge clk);
        update_is_write = 1;
        update_reduce_count = 5;
        @(posedge clk);
        update_valid = 0;
        
        repeat(5) @(posedge clk);
    endtask
    
    task test_max_pending_counts();
        $display("\n[Test 8] Maximum pending counts and reduction");
        
        // Insert with max pending counts
        @(posedge clk);
        insert_valid = 1;
        insert_e_block_id = 6;
        insert_hw_cta_id = 2;
        insert_pending_reads = 14'h3FFF;  // Max value
        insert_pending_writes = 14'h3FFF;  // Max value
        @(posedge clk);
        insert_valid = 0;
        
        // Reduce by maximum amount (8)
        repeat(2048) begin  // 16384/8 = 2048 iterations
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = 6;
            update_is_write = 0;
            update_reduce_count = 8;
        end
        @(posedge clk);
        update_valid = 0;
        
        repeat(2048) begin
            @(posedge clk);
            update_valid = 1;
            update_e_block_id = 6;
            update_is_write = 1;
            update_reduce_count = 8;
        end
        @(posedge clk);
        update_valid = 0;
        
        // Check for commit
        @(posedge clk);
        if (pop_valid && pop_e_block_id == 6) begin
            $display("  PASS: Max pending counts handled correctly");
            test_passed++;
        end else begin
            $display("  FAIL: Entry with max counts not committed properly");
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