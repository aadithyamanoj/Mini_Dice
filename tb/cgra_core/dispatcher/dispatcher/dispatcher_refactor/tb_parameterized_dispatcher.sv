module tb_parameterized_dispatcher
    import dice_pkg::*, 
           dice_frontend_pkg::*;
();
    // Clock and reset
    logic clk;
    logic rst_n;

    // DUT signals - using package parameters
    pgraph_meta_t pgraph_meta_i;  // Structured metadata input
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;  // 1024-bit from package
    cta_size_e cta_size;  // Enum type from package
    logic fetch_done;
    logic wb_valid;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] wb_tid_bitmap;  // 1024-bit from package
    logic dispatch_fifo_pop;

    // DUT outputs - combined format
    logic [4*DICE_TID_WIDTH-1:0] dispatch_tid_o;  // 40 bits total (4 lanes × 10 bits)
    logic dispatch_valid_o;
    logic dispatch_fifo_empty;
    logic dispatcher_busy, dispatcher_done;

    // Extract individual lane outputs from combined signal
    logic [DICE_TID_WIDTH-1:0] dispatch_tid_0, dispatch_tid_1, dispatch_tid_2, dispatch_tid_3;
    logic dispatch_valid_0, dispatch_valid_1, dispatch_valid_2, dispatch_valid_3;

    assign dispatch_tid_0 = dispatch_tid_o[DICE_TID_WIDTH-1:0];
    assign dispatch_tid_1 = dispatch_tid_o[2*DICE_TID_WIDTH-1:DICE_TID_WIDTH];
    assign dispatch_tid_2 = dispatch_tid_o[3*DICE_TID_WIDTH-1:2*DICE_TID_WIDTH];
    assign dispatch_tid_3 = dispatch_tid_o[4*DICE_TID_WIDTH-1:3*DICE_TID_WIDTH];

    // Valid signals need to be checked from ready FIFOs (accessing internal signals)
    assign dispatch_valid_0 = dut.dispatch_valid_0;
    assign dispatch_valid_1 = dut.dispatch_valid_1;
    assign dispatch_valid_2 = dut.dispatch_valid_2;
    assign dispatch_valid_3 = dut.dispatch_valid_3;

    // Test control
    int test_num;
    int dispatched_count;
    int tests_passed;
    int tests_failed;

    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation - NEW parameterized interface
    dispatcher dut (
        .clk(clk),
        .rst_n(rst_n),
        .pgraph_meta_i(pgraph_meta_i),          // Structured input
        .active_mask(active_mask),
        .cta_size(cta_size),
        .fetch_done(fetch_done),
        .wb_valid(wb_valid),
        .wb_tid_bitmap(wb_tid_bitmap),
        .dispatch_fifo_pop(dispatch_fifo_pop),
        .dispatch_tid_o(dispatch_tid_o),        // Combined output
        .dispatch_valid_o(dispatch_valid_o),
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

        // Initialize pgraph_meta_i structure
        pgraph_meta_i.unrolling_factor = 2'b10;  // 4-way unrolling
        pgraph_meta_i.in_regs_bitmap = '0;
        pgraph_meta_i.ld_dest_regs = '0;

        active_mask = '0;
        cta_size = CTA_SIZE_1;  // Use enum from package
        wb_valid = 0;
        wb_tid_bitmap = '0;
        dispatch_fifo_pop = 1'b0;
        dispatched_count = 0;

        repeat(3) @(negedge clk);
        rst_n = 1;
        repeat(2) @(negedge clk);
        $display("Reset complete");
    endtask

    // Task to start CTA dispatch
    task start_cta(logic [1023:0] mask, logic [65:0] regs, cta_size_e size, logic [1:0] unroll);
        $display("Starting CTA - Size: %0d, Unroll: %0d",
                 (size == CTA_SIZE_1) ? 256 : (size == CTA_SIZE_2) ? 512 : (size == CTA_SIZE_4) ? 1024 : 0,
                 (unroll == 2'b00) ? 1 : (unroll == 2'b01) ? 2 : 4);

        active_mask = mask;
        pgraph_meta_i.in_regs_bitmap = regs;  // Set register bitmap in structure
        cta_size = size;
        pgraph_meta_i.unrolling_factor = unroll;

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

        if (!dispatch_fifo_empty) begin
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
    task writeback_register(logic [REG_NUM-1:0] reg_bitmap, logic [1023:0] tid_mask);
        $display("Write-back: reg_bitmap=0x%0h for TID mask", reg_bitmap);
        wb_valid = 1;
        // Set ld_dest_regs such that the assembled bitmap matches reg_bitmap
        // You need to reverse-engineer which ld_dest_regs entries produce the desired bitmap
        wb_tid_bitmap = tid_mask;
        @(negedge clk);
        wb_valid = 0;
        wb_tid_bitmap = '0;
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

        // Stage 2: Allow pipeline to flush
        extra_drain_cycles = 0;

        while ((extra_drain_cycles < 10 || !dispatch_fifo_empty) && timeout > 0) begin
            if (!dispatch_fifo_empty) begin
                pop_and_count();
                extra_drain_cycles = 0;
            end else begin
                @(negedge clk);
                extra_drain_cycles++;
            end
            timeout--;
        end

        // Stage 3: Final check
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
            tests_failed++;
        end else begin
            $display("PASS: Dispatcher idle initially");
            tests_passed++;
        end

        if (dispatcher_done) begin
            $display("ERROR: Dispatcher should not be done initially");
            tests_failed++;
        end else begin
            $display("PASS: Dispatcher not done initially");
            tests_passed++;
        end

        if (!dispatch_fifo_empty) begin
            $display("ERROR: Dispatch FIFOs should be empty initially");
            tests_failed++;
        end else begin
            $display("PASS: All dispatch FIFOs empty initially");
            tests_passed++;
        end
    endtask

    // Test 1: Simple 128-thread dispatch (first half of chunk 0)
    task test_simple_dispatch();
        logic [1023:0] simple_mask;

        $display("\n=== Test %0d: Simple 128-Thread Dispatch ===", ++test_num);

        simple_mask = '1;  // All threads active

        start_cta(simple_mask, 66'h1, CTA_SIZE_1, 2'b10);  // 1 GPR, 256 threads, 4-way
        wait_for_completion();

        if (dispatched_count == 128) begin
            $display("PASS: Dispatched exactly 128 threads");
            tests_passed++;
        end else begin
            $display("ERROR: Expected 128 threads, got %0d", dispatched_count);
            tests_failed++;
        end

        dispatched_count = 0;
    endtask

    // Test 2: Test with register conflicts
    task test_register_conflicts();
        logic [1023:0] mask;

        $display("\n=== Test %0d: Register Conflict Test ===", ++test_num);

        mask = '0;
        mask[7:0] = 8'hFF;  // Enable first 8 threads

        // Start with register dependencies
        start_cta(mask, 66'h7, CTA_SIZE_1, 2'b10);  // 3 GPRs needed

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
            tests_passed++;
        end else begin
            $display("FAIL: Dispatched %0d/8 threads", dispatched_count);
            tests_failed++;
        end

        dispatched_count = 0;
    endtask

    // Test 3: Different unrolling factors
    task test_unrolling_factors();
        logic [31:0] mask;
        int count_1way, count_2way, count_4way;

        $display("\n=== Test %0d: Unrolling Factor Test ===", ++test_num);

        mask = 32'hFFFFFFFF;

        // Test 1-way
        $display("--- Testing 1-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, CTA_SIZE_1, 2'b00);
        wait_for_completion();
        $display("1-way dispatched: %0d threads", dispatched_count);
        count_1way = dispatched_count;

        // Test 2-way
        $display("--- Testing 2-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, CTA_SIZE_1, 2'b01);
        wait_for_completion();
        $display("2-way dispatched: %0d threads", dispatched_count);
        count_2way = dispatched_count;

        // Test 4-way
        $display("--- Testing 4-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, CTA_SIZE_1, 2'b10);
        wait_for_completion();
        $display("4-way dispatched: %0d threads", dispatched_count);
        count_4way = dispatched_count;

        // Check results
        if (count_1way == 32 && count_2way == 32 && count_4way == 32) begin
            $display("PASS: All unrolling factors dispatch correct thread count");
            tests_passed++;
        end else begin
            $display("ERROR: Unrolling factor test failed");
            $display("  Expected: 32, 32, 32");
            $display("  Got: %0d, %0d, %0d", count_1way, count_2way, count_4way);
            tests_failed++;
        end

        dispatched_count = 0;
    endtask

    // Test 6: Back-to-back CTA dispatch without reset
    task test_back_to_back_cta();
        logic [1023:0] mask1, mask2, mask3;
        logic [65:0] regs1, regs2, regs3;
        int cta1_count, cta2_count, cta3_count;

        $display("\n=== Test %0d: Back-to-Back CTA Dispatch (No Reset) ===", ++test_num);

        // First CTA: 32 threads, 2 GPRs, 4-way unrolling
        mask1 = 1024'b0;
        mask1[31:0] = 32'hFFFFFFFF;
        regs1 = 66'h3;  // GPR 0 and 1

        $display("\n--- CTA 1: 32 threads, 2 GPRs, 4-way ---");
        start_cta(mask1, regs1, CTA_SIZE_1, 2'b10);
        wait_for_completion();
        cta1_count = dispatched_count;
        $display("CTA 1 completed: %0d threads dispatched", cta1_count);

        // Verify state before next CTA
        if (!dispatcher_done) begin
            $display("ERROR: dispatcher_done should be asserted after CTA 1");
            tests_failed++;
        end else begin
            $display("PASS: dispatcher_done asserted after CTA 1");
            tests_passed++;
        end

        if (!dispatch_fifo_empty) begin
            $display("ERROR: FIFOs should be empty before CTA 2");
            tests_failed++;
        end else begin
            $display("PASS: FIFOs empty before CTA 2");
            tests_passed++;
        end

        dispatched_count = 0;

        // Second CTA: 32 threads, 1 GPR, 2-way unrolling (different config)
        mask2 = 1024'b0;
        mask2[31:0] = 32'hFFFFFFFF;
        regs2 = 66'h1;  // GPR 0 only

        $display("\n--- CTA 2: 32 threads, 1 GPR, 2-way ---");
        start_cta(mask2, regs2, CTA_SIZE_1, 2'b01);
        wait_for_completion();
        cta2_count = dispatched_count;
        $display("CTA 2 completed: %0d threads dispatched", cta2_count);

        // Verify state before next CTA
        if (!dispatcher_done) begin
            $display("ERROR: dispatcher_done should be asserted after CTA 2");
            tests_failed++;
        end else begin
            $display("PASS: dispatcher_done asserted after CTA 2");
            tests_passed++;
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
        start_cta(mask3, regs3, CTA_SIZE_1, 2'b00);
        wait_for_completion();
        cta3_count = dispatched_count;
        $display("CTA 3 completed: %0d threads dispatched", cta3_count);

        // Final verification
        $display("\n--- Back-to-Back CTA Results ---");
        $display("CTA 1: %0d/32 threads", cta1_count);
        $display("CTA 2: %0d/32 threads", cta2_count);
        $display("CTA 3: %0d/8 threads", cta3_count);

        if (cta1_count == 32 && cta2_count == 32 && cta3_count == 8) begin
            $display("PASS: All CTAs dispatched correctly without reset");
            tests_passed++;
        end else begin
            $display("FAIL: Expected 32, 32, 8 threads");
            $display("      Got %0d, %0d, %0d", cta1_count, cta2_count, cta3_count);
            tests_failed++;
        end

        dispatched_count = 0;
    endtask

    // Main test sequence
    initial begin
        $display("========================================");
        $display("Dispatcher Parameterized Testbench");
        $display("========================================");
        $display("Using DICE_NUM_MAX_THREADS_PER_CORE = %0d", DICE_NUM_MAX_THREADS_PER_CORE);
        $display("Using DICE_TID_WIDTH = %0d", DICE_TID_WIDTH);

        test_num     = 0;
        tests_passed = 0;
        tests_failed = 0;

        // Initialize and check initial state
        reset_system();
        check_initial_state();

        // Run basic functionality tests
        test_simple_dispatch();

        reset_system();
        test_register_conflicts();

        test_unrolling_factors();

        reset_system();
        test_back_to_back_cta();

        // Final summary
        $display("\n========================================");
        $display("Parameterized Tests Completed");
        $display("%0d/%0d checks passed", tests_passed, tests_passed + tests_failed);
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
        $fsdbDumpfile("refactored_dispatcher_param.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule
