module dispatcher_power_testbench;

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
    logic [3:0] dispatch_fifo_pop;
    
    // DUT outputs
    logic [9:0] dispatch_tid_0, dispatch_tid_1, dispatch_tid_2, dispatch_tid_3;
    logic dispatch_valid_0, dispatch_valid_1, dispatch_valid_2, dispatch_valid_3;
    logic dispatch_empty_0, dispatch_empty_1, dispatch_empty_2, dispatch_empty_3;
    logic dispatcher_busy, dispatcher_done;
    
    // Test control variables
    int test_case;
    int active_thread_counts[] = {32, 64, 128, 256, 512, 1024};  // Different thread counts
    int input_reg_counts[] = {1, 4, 8, 16, 32};                 // Different register usage patterns
    int cycle_count;
    int total_dispatched_threads;
    
    // Power evaluation metrics
    real switching_activity;
    int fifo_operations;
    int scoreboard_operations;
    int collision_checks;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #1.25 clk = ~clk;  // 2.50ns period = 400MHz
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
        .dispatch_empty_0(dispatch_empty_0),
        .dispatch_tid_1(dispatch_tid_1),
        .dispatch_valid_1(dispatch_valid_1),
        .dispatch_empty_1(dispatch_empty_1),
        .dispatch_tid_2(dispatch_tid_2),
        .dispatch_valid_2(dispatch_valid_2),
        .dispatch_empty_2(dispatch_empty_2),
        .dispatch_tid_3(dispatch_tid_3),
        .dispatch_valid_3(dispatch_valid_3),
        .dispatch_empty_3(dispatch_empty_3),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done)
    );
    
    // Task to reset the system
    task reset_system();
        rst_n = 0;
        fetch_done = 0;
        unrolling_factor = 2'b10;  // Default 4-way unrolling
        input_register_bitmap = 66'b0;
        active_mask = 1024'b0;
        cta_size = 2'b10;  // 1024 threads
        wb_valid = 0;
        wb_tid_bitmap = 1024'b0;
        ld_dest_reg = 8'b0;
        dispatch_fifo_pop = 4'b0;
        cycle_count = 0;
        total_dispatched_threads = 0;
        
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask
    
    // Task to create active mask with specified number of threads
    task create_active_mask(int num_threads);
        active_mask = 1024'b0;
        for (int i = 0; i < num_threads && i < 1024; i++) begin
            active_mask[i] = 1'b1;
        end
        
        // Set appropriate CTA size
        if (num_threads <= 256) cta_size = 2'b00;
        else if (num_threads <= 512) cta_size = 2'b01;
        else cta_size = 2'b10;
    endtask
    
    // Task to create input register bitmap with specified pattern
    task create_register_pattern(int num_regs, int pattern_type);
        input_register_bitmap = 66'b0;
        
        case (pattern_type)
            0: begin // Sequential GPR registers
                for (int i = 0; i < num_regs && i < 32; i++) begin
                    input_register_bitmap[i] = 1'b1;
                end
            end
            1: begin // Sequential constant registers
                for (int i = 0; i < num_regs && i < 32; i++) begin
                    input_register_bitmap[32 + i] = 1'b1;
                end
            end
            2: begin // Mixed GPR and constant
                for (int i = 0; i < num_regs/2 && i < 16; i++) begin
                    input_register_bitmap[i] = 1'b1;          // GPR
                    input_register_bitmap[32 + i] = 1'b1;     // Constant
                end
            end
            3: begin // Sparse pattern (every 4th register)
                for (int i = 0; i < num_regs*4 && i < 32; i += 4) begin
                    input_register_bitmap[i] = 1'b1;
                end
            end
            4: begin // Include predicates
                for (int i = 0; i < num_regs && i < 30; i++) begin
                    input_register_bitmap[i] = 1'b1;
                end
                input_register_bitmap[64] = 1'b1;  // Predicate 0
                input_register_bitmap[65] = 1'b1;  // Predicate 1
            end
        endcase
    endtask
    
    // Task to simulate write-back operations
    task simulate_writeback();
        wb_valid = 1;
        wb_tid_bitmap = $random;  // Random thread completion pattern
        ld_dest_reg = $random % 66;  // Random register
        @(posedge clk);
        wb_valid = 0;
        wb_tid_bitmap = 1024'b0;
    endtask
    
    // Task to pop from dispatch FIFOs
    task pop_dispatch_fifos();
        dispatch_fifo_pop = 4'b1111;  // Pop all lanes
        @(posedge clk);
        dispatch_fifo_pop = 4'b0000;
        
        // Count dispatched threads
        if (dispatch_valid_0) total_dispatched_threads++;
        if (dispatch_valid_1) total_dispatched_threads++;
        if (dispatch_valid_2) total_dispatched_threads++;
        if (dispatch_valid_3) total_dispatched_threads++;
    endtask
    
    // Monitor switching activity for power estimation
    logic [65:0] prev_input_bitmap;
    logic [1023:0] prev_active_mask;
    logic [3:0] prev_dispatch_valid;
    
    always @(posedge clk) begin
        if (rst_n) begin
            // Monitor input changes (indicative of switching activity)
            switching_activity += $countones(input_register_bitmap ^ prev_input_bitmap);
            switching_activity += $countones(active_mask ^ prev_active_mask);
            switching_activity += $countones({dispatch_valid_3, dispatch_valid_2, dispatch_valid_1, dispatch_valid_0} ^ prev_dispatch_valid);
            
            prev_input_bitmap <= input_register_bitmap;
            prev_active_mask <= active_mask;
            prev_dispatch_valid <= {dispatch_valid_3, dispatch_valid_2, dispatch_valid_1, dispatch_valid_0};
            
            cycle_count++;
        end
    end
    
    // Task to run a power evaluation test case
    task run_power_test(int num_threads, int num_regs, int pattern_type, int unroll_factor);
        automatic string test_name;
        automatic int start_cycle, end_cycle;
        automatic real power_metric;
        
        test_name = $sformatf("Threads=%0d, Regs=%0d, Pattern=%0d, Unroll=%0d", 
                             num_threads, num_regs, pattern_type, unroll_factor);
        
        $display("\n=== Starting Power Test: %s ===", test_name);
        
        reset_system();
        
        // Configure test parameters
        create_active_mask(num_threads);
        create_register_pattern(num_regs, pattern_type);
        unrolling_factor = unroll_factor;
        
        // Start test
        start_cycle = cycle_count;
        switching_activity = 0;
        total_dispatched_threads = 0;
        
        // Initiate dispatch
        fetch_done = 1;
        @(posedge clk);
        fetch_done = 0;
        
        // Wait for dispatcher to become busy
        while (!dispatcher_busy) @(posedge clk);
        
        // Run until completion with periodic write-backs and pops
        while (!dispatcher_done) begin
            // Simulate realistic system behavior
            repeat ($random % 5 + 1) @(posedge clk);
            
            // Occasionally simulate write-back
            if ($random % 10 < 3) simulate_writeback();
            
            // Pop dispatch FIFOs
            if (!dispatch_empty_0 || !dispatch_empty_1 || !dispatch_empty_2 || !dispatch_empty_3) begin
                pop_dispatch_fifos();
            end
            
            @(posedge clk);
        end
        
        end_cycle = cycle_count;
        
        // Calculate power metrics
        power_metric = switching_activity / (end_cycle - start_cycle);
        
        // Report results
        $display("Test Results for %s:", test_name);
        $display("  Cycles: %0d", end_cycle - start_cycle);
        $display("  Threads Dispatched: %0d", total_dispatched_threads);
        $display("  Switching Activity: %0.2f", switching_activity);
        $display("  Power Metric (switches/cycle): %0.4f", power_metric);
        $display("  Throughput (threads/cycle): %0.4f", real'(total_dispatched_threads) / (end_cycle - start_cycle));
        
        // Log to file for analysis
        $fdisplay(log_file, "%0d,%0d,%0d,%0d,%0d,%0.4f,%0.4f,%0.4f", 
                 num_threads, num_regs, pattern_type, unroll_factor,
                 end_cycle - start_cycle, switching_activity, power_metric,
                 real'(total_dispatched_threads) / (end_cycle - start_cycle));
    endtask
    
    // File handle for logging results
    int log_file;
    
    // Main test sequence
    initial begin
        // Open log file
        log_file = $fopen("dispatcher_power_results.csv", "w");
        $fdisplay(log_file, "Threads,Registers,Pattern,Unrolling,Cycles,SwitchingActivity,PowerMetric,Throughput");
        
        $display("Starting Dispatcher Power Evaluation Testbench");
        $display("==============================================");
        
        // Test various combinations
        foreach (active_thread_counts[i]) begin
            foreach (input_reg_counts[j]) begin
                // Test different register patterns
                for (int pattern = 0; pattern < 5; pattern++) begin
                    // Test different unrolling factors
                    for (int unroll = 0; unroll < 3; unroll++) begin
                        run_power_test(active_thread_counts[i], input_reg_counts[j], pattern, unroll);
                    end
                end
            end
        end
        
        // Stress test with maximum configuration
        $display("\n=== Stress Test: Maximum Configuration ===");
        run_power_test(1024, 32, 2, 2);  // 1024 threads, 32 registers, mixed pattern, 4-way unroll
        
        // Power efficiency test with minimal configuration
        $display("\n=== Efficiency Test: Minimal Configuration ===");
        run_power_test(32, 1, 0, 0);     // 32 threads, 1 register, sequential pattern, 1-way unroll
        
        $fclose(log_file);
        $display("\n=== Power Evaluation Complete ===");
        $display("Results saved to dispatcher_power_results.csv");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #1000000;  // 1ms timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end
    
    // Signal dump for power analysis tools
    initial begin
        $dumpfile("dispatcher_power.vcd");
        $dumpvars(0, dispatcher_power_testbench);
    end

endmodule