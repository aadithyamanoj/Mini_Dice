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
    
    // Test control
    int test_num;
    int dispatched_count;
    logic [1:0] randint;  // For random delays
    
    // Clock generation (100MHz) - matching frequency with next_thread_logic if needed
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
    
    // Add random delay logic similar to next_thread_logic testbench
    always @(negedge clk) begin
        dispatch_fifo_pop <= 1'b0;
        // Add random delay to simulate real-world conditions
        randint = $urandom_range(0, 3);
        if (randint < 4) begin
            if (!dispatch_fifo_empty) begin
                dispatch_fifo_pop <= 1'b1;
            end
        end
    end
    
    // Task to reset system - ALIGNED WITH next_thread_logic_top
    task reset_system();
        $display("=== Resetting System ===");
        rst_n = 1;  // Start with reset high
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
        
        // Apply reset - matching next_thread_logic timing
        @(negedge clk);
        rst_n = 0;
        
        // Wait 10 cycles like next_thread_logic
        repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        rst_n = 1;  // Release reset
        $display("\n Released reset ...");
        
        repeat(2) @(negedge clk);
        $display("Reset complete");
    endtask
    
    // Task to start CTA dispatch - TIMING ALIGNED
    task start_cta(logic [1023:0] mask, logic [65:0] regs, logic [1:0] size, logic [1:0] unroll);
        $display("Starting CTA - Size: %0d, Unroll: %0d", 
                 (size == 2'b00) ? 256 : (size == 2'b01) ? 512 : 1024, 
                 (unroll == 2'b00) ? 1 : (unroll == 2'b01) ? 2 : 4);
        
        // Set parameters at negedge like next_thread_logic
        @(negedge clk);
        active_mask = mask;
        input_register_bitmap = regs;
        cta_size = size;
        unrolling_factor = unroll;
        
        // Pulse fetch_done
        @(negedge clk);
        fetch_done = 1;
        @(negedge clk);
        fetch_done = 0;
        
        // Wait for dispatcher to become busy
        while (!dispatcher_busy) @(negedge clk);
        $display("Dispatcher is now busy");
    endtask
    
    // Task to pop from dispatch FIFOs and count - MANUAL MODE (disable automatic)
    task pop_and_count_manual();
        logic [3:0] valid_mask = {dispatch_valid_3, dispatch_valid_2, dispatch_valid_1, dispatch_valid_0};
        
        if (valid_mask != 4'b0000) begin
            @(negedge clk);
            dispatch_fifo_pop = 1'b1;
            @(negedge clk);
            dispatch_fifo_pop = 1'b0;
            
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
        end
    endtask
    
    // Task to simulate write-back
    task writeback_register(logic [7:0] reg_num, logic [1023:0] tid_mask);
        $display("Write-back: Register %0d for TIDs", reg_num);
        @(negedge clk);
        wb_valid = 1;
        ld_dest_reg = reg_num;
        wb_tid_bitmap = tid_mask;
        @(negedge clk);
        wb_valid = 0;
        wb_tid_bitmap = 1024'b0;
    endtask
    
    // Wait for completion - WITH AUTOMATIC POPPING DISABLED
    task wait_for_completion_auto_pop();
        int timeout = 10000;
        while (!dispatcher_done && timeout > 0) begin
            @(negedge clk);
            timeout--;
            
            // Count valid outputs even with automatic popping
            if (dispatch_valid_0) dispatched_count++;
            if (dispatch_valid_1) dispatched_count++;
            if (dispatch_valid_2) dispatched_count++;
            if (dispatch_valid_3) dispatched_count++;
        end
        
        if (timeout == 0) begin
            $display("ERROR: Timeout waiting for completion!");
            $finish;
        end else begin
            $display("CTA dispatch completed. Total dispatched: %0d", dispatched_count);
        end
    endtask
    
    // Wait for completion - MANUAL POPPING
    task wait_for_completion_manual();
        int timeout = 10000;
        while (!dispatcher_done && timeout > 0) begin
            pop_and_count_manual();
            @(negedge clk);
            timeout--;
        end
        
        if (timeout == 0) begin
            $display("ERROR: Timeout waiting for completion!");
            $finish;
        end else begin
            $display("CTA dispatch completed. Total dispatched: %0d", dispatched_count);
        end
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
        
        $display("\n=== Test %0d: Simple All-Thread Dispatch ===", ++test_num);
        
        simple_mask = '1;  // All threads active
        
        start_cta(simple_mask, 66'h1, 2'b00, 2'b10);  // 1 GPR, 256 threads, 4-way
        wait_for_completion_auto_pop();
        
        if (dispatched_count == 256) begin
            $display("PASS: Dispatched all 256 threads");
        end else begin
            $display("ERROR: Expected 256 threads, got %0d", dispatched_count);
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
        repeat(20) @(negedge clk);
        
        $display("Threads dispatched before writeback: %0d", dispatched_count);
        
        // Release register 0 for some threads
        writeback_register(8'd0, 8'h0F);
        
        // Continue until completion
        wait_for_completion_auto_pop();
        
        if (dispatched_count == 8) begin
            $display("PASS: All 8 threads eventually dispatched");
        end else begin
            $display("WARNING: Dispatched %0d/8 threads", dispatched_count);
        end
        
        dispatched_count = 0;
    endtask
    
    // Test 3: Different unrolling factors
    task test_unrolling_factors();
        logic [1023:0] mask;
        int count_1way, count_2way, count_4way;
        
        $display("\n=== Test %0d: Unrolling Factor Test ===", ++test_num);
        
        mask = 1024'b0;
        mask[15:0] = 16'hFFFF;  // Enable first 16 threads
        
        // Test 1-way unrolling
        $display("--- Testing 1-way unrolling ---");
        reset_system();
        start_cta(mask, 66'h1, 2'b00, 2'b00);  // 1-way
        wait_for_completion_auto_pop();
        $display("1-way dispatched: %0d threads", dispatched_count);
        count_1way = dispatched_count;
        
        // Test 2-way unrolling
        $display("--- Testing 2-way unrolling ---");
        reset_system();
        dispatched_count = 0;
        start_cta(mask, 66'h1, 2'b00, 2'b01);  // 2-way
        wait_for_completion_auto_pop();
        $display("2-way dispatched: %0d threads", dispatched_count);
        count_2way = dispatched_count;
        
        // Test 4-way unrolling
        $display("--- Testing 4-way unrolling ---");
        reset_system();
        dispatched_count = 0;
        start_cta(mask, 66'h1, 2'b00, 2'b10);  // 4-way
        wait_for_completion_auto_pop();
        $display("4-way dispatched: %0d threads", dispatched_count);
        count_4way = dispatched_count;
        
        if (count_1way == 16 && count_2way == 16 && count_4way == 16) begin
            $display("PASS: All unrolling factors dispatch correct thread count");
        end else begin
            $display("ERROR: Unrolling factor test failed");
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
        repeat(20) @(negedge clk);
        
        if (dispatched_count == 4) begin
            $display("PASS: All threads with constant dependencies dispatched");
        end else begin
            $display("Result: %0d/4 threads dispatched with constants", dispatched_count);
        end
        
        wait_for_completion_auto_pop();
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
        wait_for_completion_auto_pop();
        
        if (dispatched_count == 8) begin
            $display("PASS: All threads with mixed register types dispatched");
        end else begin
            $display("Result: %0d/8 threads dispatched with mixed registers", dispatched_count);
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
    
    // Generate waveform dump
    initial begin
        $fsdbDumpfile("dispatcher_basic.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule