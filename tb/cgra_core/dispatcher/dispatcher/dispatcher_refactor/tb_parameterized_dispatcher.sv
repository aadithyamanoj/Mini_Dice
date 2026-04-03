`include "dice_define.vh"

module tb_parameterized_dispatcher
    import dice_pkg::*,
           dice_frontend_pkg::*,
           DE_pkg::*;  // Import all necessary packages for parameters and types
();
    // Clock and reset
    logic clk;
    logic rst;  // Active-high reset

    // DUT signals - flat ports matching dispatcher interface
    logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs;
    logic [REG_NUM-1:0] input_register_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;
    logic fetch_done;
    logic wb_valid;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] wb_tid_bitmap;
    logic dispatch_fifo_pop;

    // DUT outputs
    logic [NUM_LANES*DICE_TID_WIDTH-1:0] dispatch_tid_o;
    logic [NUM_LANES-1:0] dispatch_valid_o;
    logic [`DICE_GPR_NUM-1:0] gpr_bitmap_o;
    logic dispatch_fifo_empty;
    logic dispatcher_busy, dispatcher_done;

    // Extract lane 0 output from combined signal
    logic [DICE_TID_WIDTH-1:0] dispatch_tid_0;
    logic dispatch_valid_0;

    assign dispatch_tid_0   = dispatch_tid_o[DICE_TID_WIDTH-1:0];
    assign dispatch_valid_0 = dispatch_valid_o[0];

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

    // DUT instantiation
    dispatcher dut (
        .clk_i(clk),
        .rst(rst),
        .ld_dest_regs(ld_dest_regs),
        .input_register_bitmap(input_register_bitmap),
        .active_mask(active_mask),
        .fetch_done(fetch_done),
        .wb_valid(wb_valid),
        .wb_tid_bitmap(wb_tid_bitmap),
        .dispatch_fifo_pop(dispatch_fifo_pop),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .dispatch_tid_o(dispatch_tid_o),
        .dispatch_valid_o(dispatch_valid_o),
        .gpr_bitmap_o(gpr_bitmap_o),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done)
    );

    // Task to reset system
    task reset_system();
        @(negedge clk);
        $display("=== Resetting System ===");
        rst = 1;  // Assert active-high reset
        fetch_done = 0;

        // Initialize flat input signals
        input_register_bitmap = '0;
        ld_dest_regs = '0;
        active_mask = '0;
        wb_valid = 0;
        wb_tid_bitmap = '0;
        dispatch_fifo_pop = 1'b0;
        dispatched_count = 0;

        repeat(3) @(negedge clk);
        rst = 0;  // Deassert active-high reset
        repeat(2) @(negedge clk);
        $display("Reset complete");
    endtask

    // Task to start CTA dispatch
    task start_cta(logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask, logic [REG_NUM-1:0] regs);
        $display("Starting CTA");

        active_mask = mask;
        input_register_bitmap = regs;

        fetch_done = 1;
        @(negedge clk);
        fetch_done = 0;

        // Wait for dispatcher to become busy
        while (!dispatcher_busy) @(negedge clk);
        $display("Dispatcher is now busy");
        repeat (10) @(negedge clk);
    endtask

    // Task to pop from dispatch FIFO and count
    task pop_and_count();
        if (!dispatch_fifo_empty) begin
            dispatch_fifo_pop = 1'b1;
            @(posedge clk);  // Pop happens here

            // Count and display dispatched threads
            if (dispatch_valid_0) begin
                $display("Lane 0 dispatched TID: %0d", dispatch_tid_0);
                dispatched_count++;
            end

            dispatch_fifo_pop = 1'b0;
        end
    endtask

    // Task to simulate write-back
    task writeback_register(logic [REG_NUM-1:0] reg_bitmap, logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] tid_mask);
        $display("Write-back: reg_bitmap=0x%0h for TID mask", reg_bitmap);
        wb_valid = 1;
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

        // Stage 1: Wait for dispatcher to finish (busy goes low)
        while (dispatcher_busy && timeout > 0) begin
            // Pop whenever ANY data is available
            if (!dispatch_fifo_empty) begin
                pop_and_count();
                idle_cycles = 0;
            end else begin
                @(negedge clk);
                idle_cycles++;

                // If idle for too long but not done, something is stuck
                if (idle_cycles > 100 && dispatcher_busy) begin
                    $display("WARNING: Idle for 100 cycles but not done");
                    $display("  dispatcher_busy=%b, dispatch_fifo_empty=%b",
                            dispatcher_busy, dispatch_fifo_empty);
                    $display("  ready_fifo_empty=%b", dut.ready_fifo_empty[0]);
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
        $display("DEBUG: ready_fifo_empty=%b", dut.ready_fifo_empty[0]);
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

    // Test 1: Simple all-thread dispatch
    task test_simple_dispatch();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] simple_mask;

        $display("\n=== Test %0d: Simple All-Thread Dispatch ===", ++test_num);

        simple_mask = '1;  // All threads active

        start_cta(simple_mask, REG_NUM'(1));  // 1 GPR, all threads
        wait_for_completion();

        if (dispatched_count == DICE_NUM_MAX_THREADS_PER_CORE) begin
            $display("PASS: Dispatched exactly %0d threads", DICE_NUM_MAX_THREADS_PER_CORE);
            tests_passed++;
        end else begin
            $display("ERROR: Expected %0d threads, got %0d", DICE_NUM_MAX_THREADS_PER_CORE, dispatched_count);
            tests_failed++;
        end

        dispatched_count = 0;
    endtask

    // Test 2: Test with register conflicts
    task test_register_conflicts();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask;

        $display("\n=== Test %0d: Register Conflict Test ===", ++test_num);

        mask = '0;
        mask[7:0] = 8'hFF;  // Enable first 8 threads

        // Start with register dependencies
        start_cta(mask, REG_NUM'('h7));  // 3 GPRs needed

        // Let some threads get stuck on register conflicts
        repeat(20) begin
            pop_and_count();
            @(negedge clk);
        end

        $display("Threads dispatched before writeback: %0d", dispatched_count);

        // Release register 0 for some threads
        writeback_register(REG_NUM'(0), {{(DICE_NUM_MAX_THREADS_PER_CORE-4){1'b0}}, 4'hF});

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

    // Test: Back-to-back CTA dispatch without reset
    task test_back_to_back_cta();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask1, mask2, mask3;
        logic [REG_NUM-1:0] regs1, regs2, regs3;
        int cta1_count, cta2_count, cta3_count;

        $display("\n=== Test %0d: Back-to-Back CTA Dispatch (No Reset) ===", ++test_num);

        // First CTA: all threads, 2 GPRs
        mask1 = '1;
        regs1 = REG_NUM'('h3);  // GPR 0 and 1

        $display("\n--- CTA 1: all threads, 2 GPRs ---");
        start_cta(mask1, regs1);
        wait_for_completion();
        cta1_count = dispatched_count;
        $display("CTA 1 completed: %0d threads dispatched", cta1_count);

        // Verify state before next CTA
        if (dispatcher_busy) begin
            $display("ERROR: dispatcher should not be busy after CTA 1");
            tests_failed++;
        end else begin
            $display("PASS: dispatcher idle after CTA 1");
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

        // Second CTA: all threads, 1 GPR
        mask2 = '1;
        regs2 = REG_NUM'(1);  // GPR 0 only

        $display("\n--- CTA 2: all threads, 1 GPR ---");
        start_cta(mask2, regs2);
        wait_for_completion();
        cta2_count = dispatched_count;
        $display("CTA 2 completed: %0d threads dispatched", cta2_count);

        // Verify state before next CTA
        if (dispatcher_busy) begin
            $display("ERROR: dispatcher should not be busy after CTA 2");
            tests_failed++;
        end else begin
            $display("PASS: dispatcher idle after CTA 2");
            tests_passed++;
        end

        dispatched_count = 0;

        // Third CTA: 8 threads, mixed registers
        mask3 = '0;
        mask3[7:0] = 8'hFF;
        regs3 = '0;
        regs3[1:0] = 2'b11;                             // GPR 0-1
        regs3[`DICE_GPR_NUM +: 2] = 2'b11;              // Constant 0-1 (offset = DICE_GPR_NUM)
        regs3[`DICE_GPR_NUM + `DICE_CR_NUM] = 1'b1;     // Predicate 0 (offset = DICE_GPR_NUM + DICE_CR_NUM)

        $display("\n--- CTA 3: 8 threads, mixed regs ---");
        start_cta(mask3, regs3);
        wait_for_completion();
        cta3_count = dispatched_count;
        $display("CTA 3 completed: %0d threads dispatched", cta3_count);

        // Final verification
        $display("\n--- Back-to-Back CTA Results ---");
        $display("CTA 1: %0d/%0d threads", cta1_count, DICE_NUM_MAX_THREADS_PER_CORE);
        $display("CTA 2: %0d/%0d threads", cta2_count, DICE_NUM_MAX_THREADS_PER_CORE);
        $display("CTA 3: %0d/8 threads", cta3_count);

        if (cta1_count == DICE_NUM_MAX_THREADS_PER_CORE &&
            cta2_count == DICE_NUM_MAX_THREADS_PER_CORE &&
            cta3_count == 8) begin
            $display("PASS: All CTAs dispatched correctly without reset");
            tests_passed++;
        end else begin
            $display("FAIL: Expected %0d, %0d, 8 threads",
                     DICE_NUM_MAX_THREADS_PER_CORE, DICE_NUM_MAX_THREADS_PER_CORE);
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
