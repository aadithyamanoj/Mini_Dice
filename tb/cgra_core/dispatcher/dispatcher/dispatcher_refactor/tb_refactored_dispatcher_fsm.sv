// `timescale 1ns/1ps

module dispatcher_fsm_tb;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Top-level outputs
    logic [255:0] current_chunk;
    logic [31:0] gpr_bitmap;
    logic [31:0] const_bitmap;
    logic [1:0] chunk_base_addr;
    logic [1:0] latched_unrolling_factor;
    logic [1:0] pred_bitmap;
    logic dispatcher_busy;
    logic dispatcher_done;
    logic restart;

    // Top-level inputs
    logic [1023:0] active_mask;
    logic [65:0] input_register_bitmap;
    logic [1:0] unrolling_factor;
    logic [1:0] cta_size;
    logic dispatch_valid_0, dispatch_valid_1;
    logic dispatch_valid_2, dispatch_valid_3;
    logic fetch_done;
    logic thread_chunk_done;
    logic dispatch_fifo_empty;

    // Test control
    int error_count = 0;
    int test_count = 0;

    // Clock generation (10ns period = 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    dispatcher_fsm dut (
        .current_chunk(current_chunk),
        .gpr_bitmap(gpr_bitmap),
        .const_bitmap(const_bitmap),
        .chunk_base_addr(chunk_base_addr),
        .latched_unrolling_factor(latched_unrolling_factor),
        .pred_bitmap(pred_bitmap),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done),
        .restart(restart),
        .active_mask(active_mask),
        .input_register_bitmap(input_register_bitmap),
        .unrolling_factor(unrolling_factor),
        .cta_size(cta_size),
        .dispatch_valid_0(dispatch_valid_0),
        .dispatch_valid_1(dispatch_valid_1),
        .dispatch_valid_2(dispatch_valid_2),
        .dispatch_valid_3(dispatch_valid_3),
        .fetch_done(fetch_done),
        .thread_chunk_done(thread_chunk_done),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .clk(clk),
        .rst_n(rst_n)
    );

    // Helper task: Check expected value
    task check(string name, logic [31:0] actual, logic [31:0] expected);
        test_count++;
        if (actual !== expected) begin
            $display("[ERROR] %s: Expected %h, Got %h", name, expected, actual);
            error_count++;
        end else begin
            $display("[PASS] %s: %h", name, actual);
        end
    endtask

    // Helper task: Initialize inputs
    task init_inputs();
        fetch_done = 0;
        thread_chunk_done = 0;
        dispatch_fifo_empty = 1;
        dispatch_valid_0 = 0;
        dispatch_valid_1 = 0;
        dispatch_valid_2 = 0;
        dispatch_valid_3 = 0;
        active_mask = 1024'b0;
        input_register_bitmap = 66'b0;
        unrolling_factor = 2'b0;
        cta_size = 2'b0;
    endtask

    // Helper task: Apply reset
    task apply_reset();
        rst_n = 0;
        init_inputs();
        repeat(2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // Main test sequence
    initial begin
        $display("========================================");
        $display("Dispatcher FSM Testbench Starting");
        $display("========================================\n");

        // Test 1: Reset behavior
        test_reset();

        // Test 2: IDLE -> DISPATCHING transition
        test_idle_to_dispatching();

        // Test 3: Single chunk dispatch (256 threads)
        test_single_chunk_dispatch();

        // Test 4: Two chunk dispatch (512 threads)
        test_two_chunk_dispatch();

        // Test 5: Four chunk dispatch (1024 threads)
        test_four_chunk_dispatch();

        // Test 6: Register bitmap extraction
        test_register_bitmaps();

        // Test 7: Multiple CTA dispatch
        test_multiple_cta();

        // Test 8: Dispatch count updates
        test_dispatch_count();

        // Summary
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Errors: %0d", error_count);
        if (error_count == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("SOME TESTS FAILED!");
        $display("========================================\n");

        $finish;
    end

    // Test 1: Reset behavior
    task test_reset();
        $display("\n--- Test 1: Reset Behavior ---");
        apply_reset();
        
        check("dispatcher_busy after reset", dispatcher_busy, 0);
        check("dispatcher_done after reset", dispatcher_done, 0);
        check("restart after reset", restart, 0);
        
        $display("Test 1 Complete\n");
    endtask

    // Test 2: IDLE -> DISPATCHING transition
    task test_idle_to_dispatching();
        $display("\n--- Test 2: IDLE -> DISPATCHING Transition ---");
        apply_reset();

        // Setup inputs
        active_mask = {256{4'b1010}}; // Pattern for testing
        input_register_bitmap = 66'h3_FFFFFFFF_12345678;
        unrolling_factor = 2'b01;
        cta_size = 2'b00; // 256 threads

        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        // Check transition to DISPATCHING
        @(posedge clk);
        check("dispatcher_busy", dispatcher_busy, 1);
        check("restart asserted", restart, 1);
        
        // Check latched values
        check("latched_unrolling_factor", latched_unrolling_factor, 2'b01);
        
        $display("Test 2 Complete\n");
    endtask

    // Test 3: Single chunk dispatch (256 threads)
    task test_single_chunk_dispatch();
        $display("\n--- Test 3: Single Chunk Dispatch (256 threads) ---");
        apply_reset();

        // Setup for 256 threads (1 chunk)
        active_mask[255:0] = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0;
        cta_size = 2'b00;

        // Start dispatch
        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        @(posedge clk);
        check("chunk_base_addr", chunk_base_addr, 2'b00);
        check("current_chunk[31:0]", current_chunk[31:0], 32'h9ABCDEF0);

        // Signal chunk done
        @(posedge clk);
        thread_chunk_done = 1;
        @(posedge clk);
        thread_chunk_done = 0;

        // Should transition to DONE
        @(posedge clk);
        @(posedge clk);
        check("dispatcher_done", dispatcher_done, 1);
        
        $display("Test 3 Complete\n");
    endtask

    // Test 4: Two chunk dispatch (512 threads)
    task test_two_chunk_dispatch();
        $display("\n--- Test 4: Two Chunk Dispatch (512 threads) ---");
        apply_reset();

        // Setup for 512 threads (2 chunks)
        active_mask[255:0] = 256'hAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA;
        active_mask[511:256] = 256'hBBBBBBBB_BBBBBBBB_BBBBBBBB_BBBBBBBB;
        cta_size = 2'b01;

        // Start dispatch
        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        // Chunk 0
        @(posedge clk);
        check("chunk_base_addr chunk 0", chunk_base_addr, 2'b00);
        check("current_chunk[31:0] chunk 0", current_chunk[31:0], 32'hAAAAAAAA);

        // Complete chunk 0
        @(posedge clk);
        thread_chunk_done = 1;
        @(posedge clk);
        thread_chunk_done = 0;

        // Chunk 1
        @(posedge clk);
        @(posedge clk);
        check("chunk_base_addr chunk 1", chunk_base_addr, 2'b01);
        check("current_chunk[31:0] chunk 1", current_chunk[31:0], 32'hBBBBBBBB);

        // Complete chunk 1
        @(posedge clk);
        thread_chunk_done = 1;
        @(posedge clk);
        thread_chunk_done = 0;

        // Should transition to DONE
        @(posedge clk);
        @(posedge clk);
        check("dispatcher_done after 2 chunks", dispatcher_done, 1);
        
        $display("Test 4 Complete\n");
    endtask

    // Test 5: Four chunk dispatch (1024 threads)
    task test_four_chunk_dispatch();
        $display("\n--- Test 5: Four Chunk Dispatch (1024 threads) ---");
        apply_reset();

        // Setup for 1024 threads (4 chunks)
        active_mask[255:0]   = 256'h1111_1111_1111_1111_1111_1111_1111_1111;
        active_mask[511:256] = 256'h2222_2222_2222_2222_2222_2222_2222_2222;
        active_mask[767:512] = 256'h3333_3333_3333_3333_3333_3333_3333_3333;
        active_mask[1023:768]= 256'h4444_4444_4444_4444_4444_4444_4444_4444;
        cta_size = 2'b10;

        // Start dispatch
        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        // Process all 4 chunks
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            @(posedge clk);
            $display("Processing chunk %0d, base_addr=%b", i, chunk_base_addr);
            
            @(posedge clk);
            thread_chunk_done = 1;
            @(posedge clk);
            thread_chunk_done = 0;
            @(posedge clk);
        end

        // Should transition to DONE
        @(posedge clk);
        check("dispatcher_done after 4 chunks", dispatcher_done, 1);
        
        $display("Test 5 Complete\n");
    endtask

    // Test 6: Register bitmap extraction
    task test_register_bitmaps();
        $display("\n--- Test 6: Register Bitmap Extraction ---");
        apply_reset();

        // Setup specific bitmap pattern
        input_register_bitmap = 66'h3_AAAAAAAA_BBBBBBBB;
    //                          ^^ ^^^^^^^^ ^^^^^^^^ 
    //                          |  const    gpr      
    //                          pred

        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        @(posedge clk);
        check("gpr_bitmap", gpr_bitmap, 32'hBBBBBBBB);      // Fixed: Only 8 hex digits
        check("const_bitmap", const_bitmap, 32'hAAAAAAAA);  // Fixed: Only 8 hex digits
        check("pred_bitmap", pred_bitmap, 2'b11);
        
        $display("Test 6 Complete\n");
    endtask

    // Test 7: Multiple CTA dispatch
    task test_multiple_cta();
        $display("\n--- Test 7: Multiple CTA Dispatch ---");
        apply_reset();

        // First CTA
        active_mask[255:0] = 256'hFEEDFACE_DEADBEEF_CAFEBABE_12345678;
        cta_size = 2'b00;

        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        @(posedge clk);
        @(posedge clk);
        thread_chunk_done = 1;
        @(posedge clk);
        thread_chunk_done = 0;

        // Wait for DONE state
        @(posedge clk);
        @(posedge clk);
        check("First CTA done", dispatcher_done, 1);

        // Second CTA
        active_mask[255:0] = 256'h99999999_88888888_77777777_66666666;
        
        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        @(posedge clk);
        check("Second CTA dispatching", dispatcher_busy, 1);
        check("current_chunk updated", current_chunk[31:0], 32'h66666666);
        
        $display("Test 7 Complete\n");
    endtask

    // Test 8: Dispatch count updates
    task test_dispatch_count();
        $display("\n--- Test 8: Dispatch Count Updates ---");
        apply_reset();

        active_mask = {256{4'b1111}};
        cta_size = 2'b00;

        @(posedge clk);
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;

        // Simulate dispatches with different valid signals
        @(posedge clk);
        dispatch_valid_0 = 1;
        dispatch_valid_1 = 1;
        dispatch_valid_2 = 0;
        dispatch_valid_3 = 1;
        
        @(posedge clk);
        // Count should be 3 (0+1+2+3 valid signals)
        
        @(posedge clk);
        dispatch_valid_0 = 1;
        dispatch_valid_1 = 1;
        dispatch_valid_2 = 1;
        dispatch_valid_3 = 1;
        
        @(posedge clk);
        // Count should be 3+4=7
        
        $display("Dispatch count test executed (check waveform for count=3, then 7)");
        
        $display("Test 8 Complete\n");
    endtask

    // Waveform dump
    initial begin
        $dumpfile("dispatcher_fsm.vcd");
        $dumpvars(0, dispatcher_fsm_tb);
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    initial begin
        // dump fsdb
        $fsdbDumpfile("refactored_dispatcher_fsm.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule