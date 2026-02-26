module dispatcher_basic_testbench;

    // Clock and reset
    logic clk;
    logic rst_n;
    
    // DUT signals
    logic [1:0] unrolling_factor;
    logic [65:0] input_register_bitmap;
    logic [1023:0] active_mask;
    logic [1:0] cta_size;
    logic fetch_done;
    logic wb_valid;
    logic [1023:0] wb_tid_bitmap;
    logic [7:0] ld_dest_reg;
    logic dispatch_fifo_pop;
    
    // DUT outputs
    logic [9:0] dispatch_tid_0, dispatch_tid_1, dispatch_tid_2, dispatch_tid_3;
    logic dispatch_valid_0, dispatch_valid_1, dispatch_valid_2, dispatch_valid_3;
    logic dispatch_fifo_empty;
    logic dispatcher_busy, dispatcher_done;

    logic [3:0] ready_fifo_empty;
    
    // Test control
    int test_num;
    int dispatched_count;
    
    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // DUT instantiation
    dispatcher dut (
        .clk(clk),
        .rst_n(rst_n),
        .unrolling_factor(unrolling_factor),
        .input_register_bitmap(input_register_bitmap),
        .active_mask(active_mask),
        .cta_size(cta_size),
        .fetch_done(fetch_done),
        .wb_valid(wb_valid),
        .wb_tid_bitmap(wb_tid_bitmap),
        .ld_dest_reg(ld_dest_reg),
        .dispatch_fifo_pop(dispatch_fifo_pop),
        .dispatch_tid_0(dispatch_tid_0),
        .dispatch_valid_0(dispatch_valid_0),
        .dispatch_tid_1(dispatch_tid_1),
        .dispatch_valid_1(dispatch_valid_1),
        .dispatch_tid_2(dispatch_tid_2),
        .dispatch_valid_2(dispatch_valid_2),
        .dispatch_tid_3(dispatch_tid_3),
        .dispatch_valid_3(dispatch_valid_3),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done)
    );
    
    // Task to reset system
    task reset_system();
        @(negedge clk);
        $display("=== Resetting System ===");
        rst_n = 0;
        fetch_done = 0;
        unrolling_factor = 2'b10;  // 4-way unrolling
        input_register_bitmap = 66'b0;
        active_mask = 1024'b0;
        cta_size = 2'b00;  // 256 threads
        wb_valid = 0;
        wb_tid_bitmap = 1024'b0;
        ld_dest_reg = 8'b0;
        dispatch_fifo_pop = 1'b0;
        dispatched_count = 0;
        
        repeat(3) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);
        $display("Reset complete");
    endtask
    
    // Task to start CTA dispatch
    task start_cta(logic [1023:0] mask, logic [65:0] regs, logic [1:0] size, logic [1:0] unroll);
        $display("Starting CTA - Size: %0d, Unroll: %0d", 
                 (size == 2'b00) ? 256 : (size == 2'b01) ? 512 : 1024, 
                 (unroll == 2'b00) ? 1 : (unroll == 2'b01) ? 2 : 4);
        
        active_mask = mask;
        input_register_bitmap = regs;
        cta_size = size;
        unrolling_factor = unroll;
        
        fetch_done = 1;
        @(negedge clk);
        fetch_done = 0;
        
        // Wait for dispatcher to become busy
        while (!dispatcher_busy) @(negedge clk);
        $display("Dispatcher is now busy");
        repeat (10) @(negedge clk);
    endtask
    
    // Task to pop from dispatch FIFOs and count
    task pop_and_count();
        logic [3:0] valid_mask = {dispatch_valid_3, dispatch_valid_2, dispatch_valid_1, dispatch_valid_0};
        
        if (!dispatch_fifo_empty) begin  // Changed: check if data available
            dispatch_fifo_pop = 1'b1;
            @(posedge clk);  // Pop happens here
            
            // Count and display dispatched threads
            if (dispatch_valid_0) begin
                $display("Lane 0 dispatched TID: %0d", dispatch_tid_0);
                dispatched_count++;
            end
            if (dispatch_valid_1) begin
                $display("Lane 1 dispatched TID: %0d", dispatch_tid_1);
                dispatched_count++;
            end
            if (dispatch_valid_2) begin
                $display("Lane 2 dispatched TID: %0d", dispatch_tid_2);
                dispatched_count++;
            end
            if (dispatch_valid_3) begin
                $display("Lane 3 dispatched TID: %0d", dispatch_tid_3);
                dispatched_count++;
            end

            dispatch_fifo_pop = 1'b0;
        end
    endtask
    
    // Task to simulate write-back
    task writeback_register(logic [7:0] reg_num, logic [1023:0] tid_mask);
        $display("Write-back: Register %0d for TIDs", reg_num);
        wb_valid = 1;
        ld_dest_reg = reg_num;
        wb_tid_bitmap = tid_mask;
        @(negedge clk);
        wb_valid = 0;
        wb_tid_bitmap = 1024'b0;
    endtask
    
    // Wait for completion
    task wait_for_completion();
        int timeout = 10000;
        int idle_cycles = 0;
        int extra_drain_cycles;
        
        // Stage 1: Wait for dispatcher_done
        while (!dispatcher_done && timeout > 0) begin
            // Pop whenever ANY data is available
            if (!dispatch_fifo_empty) begin
                pop_and_count();
                idle_cycles = 0;
            end else begin
                @(negedge clk);
                idle_cycles++;
                
                // If idle for too long but not done, something is stuck
                if (idle_cycles > 100 && !dispatcher_done) begin
                    $display("WARNING: Idle for 100 cycles but not done");
                    $display("  dispatcher_done=%b, dispatch_fifo_empty=%b", 
                            dispatcher_done, dispatch_fifo_empty);
                    $display("  ready_fifo_empty=%b", {dut.ready_fifo_empty[3], dut.ready_fifo_empty[2], 
                                                        dut.ready_fifo_empty[1], dut.ready_fifo_empty[0]});
                end
            end
            timeout--;
        end
        
        if (timeout == 0) begin
            $display("ERROR: Timeout waiting for dispatcher_done!");
            $finish;
        end
        
        $display("Dispatcher signaled done. Starting pipeline flush...");
        
        // Stage 2: CRITICAL - Allow pipeline to flush
        // Give extra cycles for thread_fifo -> ready_fifo -> dispatch_tid pipeline
        // Based on your observation: 4 cycles minimum for propagation
        extra_drain_cycles = 0;
        
        // Keep draining as long as we're seeing new data OR haven't given enough cycles
        while ((extra_drain_cycles < 10 || !dispatch_fifo_empty) && timeout > 0) begin
            if (!dispatch_fifo_empty) begin
                pop_and_count();
                extra_drain_cycles = 0;  // Reset counter when we pop data
            end else begin
                @(negedge clk);
                extra_drain_cycles++;
            end
            timeout--;
        end
        
        // Stage 3: Final check - make absolutely sure FIFOs are empty
        repeat(5) @(negedge clk);
        
        if (!dispatch_fifo_empty) begin
            $display("WARNING: FIFOs still have data after drain period!");
            while (!dispatch_fifo_empty && timeout > 0) begin
                pop_and_count();
                timeout--;
            end
        end
        
        if (timeout == 0) begin
            $display("ERROR: Timeout during pipeline flush!");
            $finish;
        end else begin
            $display("CTA dispatch completed. Total dispatched: %0d", dispatched_count);
        end

        $display("DEBUG: thread_fifo_empty=%b, thread_chunk_done=%b", 
                 dut.thread_fifo_empty, dut.thread_chunk_done);
        $display("DEBUG: All ready_fifo_empty=%b", 
                 {dut.ready_fifo_empty[3], dut.ready_fifo_empty[2], 
                  dut.ready_fifo_empty[1], dut.ready_fifo_empty[0]});
    endtask
    
    // Check basic functionality
    task check_initial_state();
        $display("=== Test %0d: Initial State Check ===", ++test_num);
        
        if (dispatcher_busy) begin
            $display("ERROR: Dispatcher should not be busy initially");
        end else begin
            $display("PASS: Dispatcher idle initially");
        end
        
        if (dispatcher_done) begin
            $display("ERROR: Dispatcher should not be done initially");
        end else begin
            $display("PASS: Dispatcher not done initially");
        end
        
        if (!dispatch_fifo_empty) begin
            $display("ERROR: Dispatch FIFOs should be empty initially");
        end else begin
            $display("PASS: All dispatch FIFOs empty initially");
        end
    endtask
    
    // Test 1: Simple 4-thread dispatch
    task test_simple_dispatch();
        logic [1023:0] simple_mask;
        
        $display("\n=== Test %0d: Simple 4-Thread Dispatch ===", ++test_num);
        
        simple_mask = '1;
        //simple_mask = 1024'b0;
        //simple_mask[3:0] = 4'b1111;  // Enable first 4 threads
        
        start_cta(simple_mask, 66'h1, 2'b00, 2'b10);  // 1 GPR, 256 threads, 4-way
        wait_for_completion();
        
        if (dispatched_count == 4) begin
            $display("PASS: Dispatched exactly 4 threads");
        end else begin
            $display("ERROR: Expected 4 threads, got %0d", dispatched_count);
        end
        
        dispatched_count = 0;
    endtask
    
    // Test 2: Test with register conflicts
    task test_register_conflicts();
        logic [1023:0] mask;
        
        $display("\n=== Test %0d: Register Conflict Test ===", ++test_num);
        
        mask = 1024'b0;
        mask[7:0] = 8'hFF;  // Enable first 8 threads
        
        // Start with register dependencies
        start_cta(mask, 66'h7, 2'b00, 2'b10);  // 3 GPRs needed
        
        // Let some threads get stuck on register conflicts
        repeat(20) begin
            pop_and_count();
            @(negedge clk);
        end
        
        $display("Threads dispatched before writeback: %0d", dispatched_count);
        
        // Release register 0 for some threads
        writeback_register(8'd0, 8'h0F);
        
        // Continue until completion
        wait_for_completion();
        
        if (dispatched_count == 8) begin
            $display("PASS: All 8 threads eventually dispatched");
        end else begin
            $display("WARNING: Dispatched %0d/8 threads", dispatched_count);
        end
        
        dispatched_count = 0;
    endtask
    
    // Test 3: Different unrolling factors
    task test_unrolling_factors();
        logic [31:0] mask;
        int count_1way, count_2way, count_4way;
        
        $display("\n=== Test %0d: Unrolling Factor Test ===", ++test_num);
        
        // CHANGE: Use more threads to ensure all lanes get work
        // Set multiple chunks worth of threads
        // mask = '1;
        mask = 32'b0;
        mask[31:0] = 32'hFFFFFFFF;
        
        // Test 1-way - expect 32 threads dispatched
        $display("--- Testing 1-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, 2'b00, 2'b00);
        wait_for_completion();
        $display("1-way dispatched: %0d threads", dispatched_count);
        count_1way = dispatched_count;
        
        // Test 2-way - expect 32 threads dispatched
        $display("--- Testing 2-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, 2'b00, 2'b01);
        wait_for_completion();
        $display("2-way dispatched: %0d threads", dispatched_count);
        count_2way = dispatched_count;

        // Test 4-way - expect 32 threads dispatched
        $display("--- Testing 4-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, 2'b00, 2'b10);
        wait_for_completion();
        $display("4-way dispatched: %0d threads", dispatched_count);
        count_4way = dispatched_count;
        
        // Check results
        if (count_1way == 32 && count_2way == 32 && count_4way == 32) begin
            $display("PASS: All unrolling factors dispatch correct thread count");
        end else begin
            $display("ERROR: Unrolling factor test failed");
            $display("  Expected: 32, 32, 32");
            $display("  Got: %0d, %0d, %0d", count_1way, count_2way, count_4way);
        end
        
        dispatched_count = 0;
    endtask
    
    // Test 4: Constant register conflicts
    task test_constant_conflicts();
        logic [1023:0] mask;
        logic [65:0] const_regs;
        
        $display("\n=== Test %0d: Constant Register Conflict Test ===", ++test_num);
        
        mask = 1024'b0;
        mask[3:0] = 4'b1111;  // Enable first 4 threads
        
        // Use constant registers (bits 32-63)
        const_regs = 66'b0;
        const_regs[35:32] = 4'b1111;  // Use constant registers 0-3
        
        start_cta(mask, const_regs, 2'b00, 2'b10);
        
        // Should dispatch all at once since constants are shared
        repeat(10) begin
            pop_and_count();
            @(negedge clk);
        end
        
        if (dispatched_count == 4) begin
            $display("PASS: All threads with constant dependencies dispatched");
        end else begin
            $display("Result: %0d/4 threads dispatched with constants", dispatched_count);
        end
        
        wait_for_completion();
        dispatched_count = 0;
    endtask
    
    // Test 5: Mixed register types
    task test_mixed_registers();
        logic [1023:0] mask;
        logic [65:0] mixed_regs;
        
        $display("\n=== Test %0d: Mixed Register Types Test ===", ++test_num);
        
        mask = 1024'b0;
        mask[7:0] = 8'hFF;  // Enable first 8 threads
        
        // Use GPR, constant, and predicate registers
        mixed_regs = 66'b0;
        mixed_regs[2:0] = 3'b111;      // GPR 0-2
        mixed_regs[34:32] = 3'b111;    // Constant 0-2
        mixed_regs[65:64] = 2'b11;     // Both predicates
        
        start_cta(mask, mixed_regs, 2'b00, 2'b10);
        wait_for_completion();
        
        if (dispatched_count == 8) begin
            $display("PASS: All threads with mixed register types dispatched");
        end else begin
            $display("Result: %0d/8 threads dispatched with mixed registers", dispatched_count);
        end
        
        dispatched_count = 0;
    endtask

    // Test 6: Back-to-back CTA dispatch without reset
    task test_back_to_back_cta();
        logic [1023:0] mask1, mask2, mask3;
        logic [65:0] regs1, regs2, regs3;
        int cta1_count, cta2_count, cta3_count;

        $display("\n=== Test %0d: Back-to-Back CTA Dispatch (No Reset) ===", ++test_num);

        // First CTA: 16 threads, 2 GPRs, 4-way unrolling
        mask1 = 1024'b0;
        mask1[15:0] = 16'hFFFF;
        regs1 = 66'h3;  // GPR 0 and 1

        $display("\n--- CTA 1: 16 threads, 2 GPRs, 4-way ---");
        start_cta(mask1, regs1, 2'b00, 2'b10);
        wait_for_completion();
        cta1_count = dispatched_count;
        $display("CTA 1 completed: %0d threads dispatched", cta1_count);

        // Verify state before next CTA
        if (!dispatcher_done) begin
            $display("ERROR: dispatcher_done should be asserted after CTA 1");
        end else begin
            $display("PASS: dispatcher_done asserted after CTA 1");
        end

        if (!dispatch_fifo_empty) begin
            $display("ERROR: FIFOs should be empty before CTA 2");
        end else begin
            $display("PASS: FIFOs empty before CTA 2");
        end

        dispatched_count = 0;

        // Second CTA: 32 threads, 1 GPR, 2-way unrolling (different config)
        mask2 = 1024'b0;
        mask2[31:0] = 32'hFFFFFFFF;
        regs2 = 66'h1;  // GPR 0 only

        $display("\n--- CTA 2: 32 threads, 1 GPR, 2-way ---");
        start_cta(mask2, regs2, 2'b00, 2'b01);
        wait_for_completion();
        cta2_count = dispatched_count;
        $display("CTA 2 completed: %0d threads dispatched", cta2_count);

        // Verify state before next CTA
        if (!dispatcher_done) begin
            $display("ERROR: dispatcher_done should be asserted after CTA 2");
        end else begin
            $display("PASS: dispatcher_done asserted after CTA 2");
        end

        dispatched_count = 0;

        // Third CTA: 8 threads, mixed registers, 1-way unrolling
        mask3 = 1024'b0;
        mask3[7:0] = 8'hFF;
        regs3 = 66'b0;
        regs3[1:0] = 2'b11;      // GPR 0-1
        regs3[33:32] = 2'b11;    // Constant 0-1
        regs3[64] = 1'b1;        // Predicate 0

        $display("\n--- CTA 3: 8 threads, mixed regs, 1-way ---");
        start_cta(mask3, regs3, 2'b00, 2'b00);
        wait_for_completion();
        cta3_count = dispatched_count;
        $display("CTA 3 completed: %0d threads dispatched", cta3_count);

        // Final verification
        $display("\n--- Back-to-Back CTA Results ---");
        $display("CTA 1: %0d/16 threads", cta1_count);
        $display("CTA 2: %0d/32 threads", cta2_count);
        $display("CTA 3: %0d/8 threads", cta3_count);

        if (cta1_count == 16 && cta2_count == 32 && cta3_count == 8) begin
            $display("PASS: All CTAs dispatched correctly without reset");
        end else begin
            $display("FAIL: Expected 16, 32, 8 threads");
            $display("      Got %0d, %0d, %0d", cta1_count, cta2_count, cta3_count);
        end

        dispatched_count = 0;
    endtask

    // Main test sequence
    initial begin
        $display("========================================");
        $display("Dispatcher Basic Functional Testbench");
        $display("========================================");
        
        test_num = 0;
        
        // Initialize and check initial state
        reset_system();
        check_initial_state();
        
        // Run basic functionality tests
        test_simple_dispatch();
        
        reset_system();
        test_register_conflicts();
        
        test_unrolling_factors();
        
        reset_system();
        test_constant_conflicts();
        
        reset_system();
        test_mixed_registers();

        reset_system();
        test_back_to_back_cta();

        // Final summary
        $display("\n========================================");
        $display("Basic Functional Tests Completed");
        $display("========================================");
        
        $finish;
    end
    
    // Timeout protection
    initial begin
        #100000;  // 100us timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    initial begin
        // dump fsdb
        $fsdbDumpfile("refactored_dispatcher.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule