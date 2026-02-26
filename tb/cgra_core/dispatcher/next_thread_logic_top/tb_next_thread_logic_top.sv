module next_thread_logic_top_testbench;

    // Clock and reset
    logic clk;
    logic rst_n;
    
    // DUT inputs
    logic [1:0] unrolling_factor;
    logic [255:0] active_mask_chunk;
    logic [1:0] chunk_base_addr;
    logic fifo_pop;
    
    // DUT outputs
    logic [9:0] next_tid_0;
    logic [9:0] next_tid_1;
    logic [9:0] next_tid_2;
    logic [9:0] next_tid_3;
    logic valid_0;
    logic valid_1;
    logic valid_2;
    logic valid_3;
    logic fifo_empty;
    logic fifo_full;
    logic restart; 
    logic fifo_data_valid;
    logic chunk_done;
    
    // Test control
    int threads_popped;
    int expected_threads_count;
    logic [10:0] expected_tids_0 [$];
    logic [10:0] expected_tids_1 [$];
    logic [10:0] expected_tids_2 [$];
    logic [10:0] expected_tids_3 [$];

    
    // Clock generation (400MHz)
    initial begin
        clk = 0;
        forever #1.25 clk = ~clk;
    end
    
    // DUT instantiation
    next_thread_logic_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .unrolling_factor(unrolling_factor),
        .active_mask_chunk(active_mask_chunk),
        .chunk_base_addr(chunk_base_addr),
        .restart(restart),
        .fifo_pop(fifo_pop),
        .next_tid_0(next_tid_0),
        .next_tid_1(next_tid_1),
        .next_tid_2(next_tid_2),
        .next_tid_3(next_tid_3),
        .valid_0(valid_0),
        .valid_1(valid_1),
        .valid_2(valid_2),
        .valid_3(valid_3),
        .fifo_data_valid(fifo_data_valid),
        .fifo_empty(fifo_empty),
        .fifo_full(fifo_full),
        .chunk_done(chunk_done)
    );

    // tid checker
    logic [10:0] expected_tid;
    logic [1:0] randint;

    always @(negedge clk) begin
        fifo_pop <= 1'b0;
        //add random delay to simulate real-world conditions
        randint = $urandom_range(0, 3);
        if (randint < 4) begin
            if (!fifo_empty) begin
                fifo_pop <= 1'b1;
            end
        end
    end
        
    always @(negedge clk) begin
        if (fifo_data_valid) begin
            // For 1-way unrolling, only FIFO 0 should have valid data
            if (valid_0) begin  // Check valid bit
                if(expected_tids_0.size() == 0) begin
                    $display("ERROR: No expected TIDs left to pop in lane 0 with valid bit 1, get %0d", next_tid_0[9:0]);
                    $finish;
                end
                expected_tid = expected_tids_0.pop_front();  // Use pop_front for FIFO order
                $display("Popped TID: %0d (expected: %0d)", next_tid_0[9:0], expected_tid[9:0]);
                if(expected_tid[10]==1'b0) begin
                    $display("ERROR: Expected TID %0d is not valid", expected_tid[9:0]);
                    $finish;
                end
                if (next_tid_0[9:0] == expected_tid[9:0]) begin
                    $display("PASS: Correct TID received");
                    threads_popped++;
                end else begin
                    $display("ERROR: TID mismatch! Expected %0d, got %0d", expected_tid[9:0], next_tid_0[9:0]);
                    $finish;
                end
            end else begin
                if(expected_tids_0.size() == 0) begin
                    $display("ERROR: No expected TIDs left to pop in lane 0 with valid bit 0");
                    $finish;
                end
                expected_tid = expected_tids_0.pop_front();  // Use pop_front for FIFO order
                if(expected_tid[10]==1'b1) begin
                    $display("ERROR: Expected valid TID (%0d) but no data in FIFO 0", expected_tid[9:0]);
                    $finish;
                end
            end
            if (valid_1) begin  // Check valid bit
                if(expected_tids_1.size() == 0) begin
                    $display("ERROR: No expected TIDs left to pop  in lane 1");
                    $finish;
                end
                expected_tid = expected_tids_1.pop_front();  // Use pop_front for FIFO order
                $display("Popped TID: %0d (expected: %0d)", next_tid_1[9:0], expected_tid[9:0]);
                if(expected_tid[10]==1'b0) begin
                    $display("ERROR: Expected TID %0d is not valid", expected_tid[9:0]);
                    $finish;
                end
                if (next_tid_1[9:0] == expected_tid[9:0]) begin
                    $display("PASS: Correct TID received");
                    threads_popped++;
                end else begin
                    $display("ERROR: TID mismatch! Expected %0d, got %0d", expected_tid[9:0], next_tid_1[9:0]);
                    $finish;
                end
            end else begin
                if(unrolling_factor != 2'b00) begin
                    if(expected_tids_1.size() == 0) begin
                        $display("ERROR: No expected TIDs left to pop  in lane 1");
                        $finish;
                    end
                    expected_tid = expected_tids_1.pop_front();  // Use pop_front for FIFO order
                    if(expected_tid==1'b1) begin
                        $display("ERROR: Expected valid TID but no data in FIFO 1");
                        $finish;
                    end
                end
            end
            if (valid_2) begin  // Check valid bit
                if(expected_tids_2.size() == 0) begin
                    $display("ERROR: No expected TIDs left to pop  in lane 2");
                    $finish;
                end
                expected_tid = expected_tids_2.pop_front();  // Use pop_front for FIFO order
                $display("Popped TID: %0d (expected: %0d)", next_tid_2[9:0], expected_tid[9:0]);
                if(expected_tid[10]==1'b0) begin
                    $display("ERROR: Expected TID %0d is not valid", expected_tid[9:0]);
                    $finish;
                end
                if (next_tid_2[9:0] == expected_tid[9:0]) begin
                    $display("PASS: Correct TID received");
                    threads_popped++;
                end else begin
                    $display("ERROR: TID mismatch! Expected %0d, got %0d", expected_tid[9:0], next_tid_2[9:0]);
                    $finish;
                end
            end else begin
                if(unrolling_factor == 2'b10) begin
                    if(expected_tids_2.size() == 0) begin
                        $display("ERROR: No expected TIDs left to pop  in lane 2");
                        $finish;
                    end
                    expected_tid = expected_tids_2.pop_front();  // Use pop_front for FIFO order
                    if(expected_tid[10]==1'b1) begin
                        $display("ERROR: Expected valid TID but no data in FIFO 2");
                        $finish;
                    end
                end
            end
            if (valid_3) begin  // Check valid bit
                if(expected_tids_3.size() == 0) begin
                    $display("ERROR: No expected TIDs left to pop  in lane 3");
                    $finish;
                end
                expected_tid = expected_tids_3.pop_front();  // Use pop_front for FIFO order
                $display("Popped TID: %0d (expected: %0d)", next_tid_3[9:0], expected_tid[9:0]);
                if(expected_tid[10]==1'b0) begin
                    $display("ERROR: Expected TID %0d is not valid", expected_tid[9:0]);
                    $finish;
                end
                if (next_tid_3[9:0] == expected_tid[9:0]) begin
                    $display("PASS: Correct TID received");
                    threads_popped++;
                end else begin
                    $display("ERROR: TID mismatch! Expected %0d, got %0d", expected_tid[9:0], next_tid_3[9:0]);
                    $finish;
                end
            end else begin
                if(unrolling_factor == 2'b10) begin
                    if(expected_tids_3.size() == 0) begin
                        $display("ERROR: No expected TIDs left to pop  in lane 3");
                        $finish;
                    end
                    expected_tid = expected_tids_3.pop_front();  // Use pop_front for FIFO order
                    if(expected_tid[10]==1'b1) begin
                        $display("ERROR: Expected valid TID (%0d) but no data in FIFO 3", expected_tid[9:0]);
                        $finish;
                    end
                end
            end
        end
    end
    
    // Task to reset system
    task reset_system();
        $display("=== Resetting System ===");
        //rst_n = 0;
        unrolling_factor = 2'b00;    // 1-way unrolling
        active_mask_chunk = 256'b0;
        chunk_base_addr = 2'b00;     // Chunk 0 (TIDs 0-255)
        threads_popped = 0;
        expected_threads_count = 0;
        restart = 1;
        expected_tids_0.delete();
        expected_tids_1.delete();
        expected_tids_2.delete();
        expected_tids_3.delete();
    endtask
    
    // Task to display FIFO status
    task display_fifo_status();
        $display("FIFO Status: empty=%b, full=%b", fifo_empty, fifo_full);
        $display("FIFO Data: 0={valid=%b,tid=%0d} 1={valid=%b,tid=%0d} 2={valid=%b,tid=%0d} 3={valid=%b,tid=%0d}", 
                 valid_0, next_tid_0[9:0],
                 valid_1, next_tid_1[9:0],
                 valid_2, next_tid_2[9:0],
                 valid_3, next_tid_3[9:0]);
    endtask
    
    task set_parameters_and_push_expected_tids(
        input logic [255:0] mask,
        input logic [1:0] uf,
        input logic [1:0] chunk_addr
    );
        int i, j;
        logic [9:0] tid_0, tid_1, tid_2, tid_3;
        
        active_mask_chunk = mask;
        unrolling_factor = uf;
        chunk_base_addr = chunk_addr;
        
        $display("Test setup:");
        if(uf == 2'b00) begin
            $display("- Unrolling factor: 1-way");
        end else if (uf == 2'b01) begin
            $display("- Unrolling factor: 2-way");
        end else if (uf == 2'b10) begin
            $display("- Unrolling factor: 4-way");
        end else begin
            $display("ERROR: Invalid unrolling factor %b", uf);
            $finish;
        end

        if(chunk_addr == 2'b00) begin
            $display("- Chunk base: 0 (TIDs 0-255)");
        end else if (chunk_addr == 2'b01) begin
            $display("- Chunk base: 256 (TIDs 256-511)");
        end else if (chunk_addr == 2'b10) begin
            $display("- Chunk base: 512 (TIDs 512-767)");
        end else if (chunk_addr == 2'b11) begin
            $display("- Chunk base: 768 (TIDs 768-1023)");
        end else begin
            $display("ERROR: Invalid chunk address %b", chunk_addr);
            $finish;
        end

        $display("- Active mask: %b", mask);
        //calculate expected TIDs based on active mask
        if(uf == 2'b00) begin // 1-way unrolling
            for(i=0; i<256; i++) begin
                if(mask[i]) begin
                    expected_tids_0.push_back({1'b1, i[9:0]});
                    expected_threads_count++;
                end
            end
        end else if (uf == 2'b01) begin // 2-way unrolling
            for(i=0; i<256; i+=32) begin
                for(j=0; j<16; j++) begin
                    tid_0 = i[9:0] + j[9:0];
                    tid_1 = i[9:0] + j[9:0] + 16;
                    if(mask[tid_0] || mask[tid_1]) begin
                        if(mask[tid_0]) begin
                            expected_tids_0.push_back({1'b1, tid_0});
                            expected_threads_count++;
                        end else begin
                            expected_tids_0.push_back({1'b0, tid_0});
                        end

                        if(mask[tid_1]) begin
                            expected_tids_1.push_back({1'b1, tid_1});
                            expected_threads_count++;
                        end else begin
                            expected_tids_1.push_back({1'b0, tid_1});
                        end
                    end
                end
            end
        end else if (uf == 2'b10) begin // 4-way unrolling
            for(i=0; i<256; i+=32) begin
                for(j=0; j<8; j++) begin
                    tid_0 = i + j;
                    tid_1 = i + j + 8;
                    tid_2 = i + j + 16;
                    tid_3 = i + j + 24;
                    
                    if(mask[tid_0] || mask[tid_1] || mask[tid_2] || mask[tid_3]) begin
                        if(mask[tid_0]) begin
                            expected_tids_0.push_back({1'b1, tid_0});
                            expected_threads_count++;
                        end else begin
                            expected_tids_0.push_back({1'b0, tid_0});
                        end

                        if(mask[tid_1]) begin
                            expected_tids_1.push_back({1'b1, tid_1});
                            expected_threads_count++;
                        end else begin
                            expected_tids_1.push_back({1'b0, tid_1});
                        end

                        if(mask[tid_2]) begin
                            expected_tids_2.push_back({1'b1, tid_2});
                            expected_threads_count++;
                        end else begin
                            expected_tids_2.push_back({1'b0, tid_2});
                        end

                        if(mask[tid_3]) begin
                            expected_tids_3.push_back({1'b1, tid_3});
                            expected_threads_count++;
                        end else begin
                            expected_tids_3.push_back({1'b0, tid_3});
                        end
                    end
                end
            end
        end else begin
            $display("ERROR: Invalid unrolling factor %b", uf);
            $finish;
        end
        $display("Expected threads count: %0d", expected_threads_count);
        $display("Expected TIDs in FIFO 0: %0d", expected_tids_0.size());
        $display("Expected TIDs in FIFO 1: %0d", expected_tids_1.size());
        $display("Expected TIDs in FIFO 2: %0d", expected_tids_2.size());
        $display("Expected TIDs in FIFO 3: %0d", expected_tids_3.size());
        $display("==========================================");
    endtask


    logic [255:0] random_active_mask;


    task random_test();
        input logic [1:0] unrolling_factor;
        $display("==========================================");
        $display("Random Test: Random Active");
        $display("==========================================");
        
        // Initialize
        rst_n=1;
        reset_system();
        rst_n = 0;
        restart = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        for(int i=0;i<256;i++) begin
            random_active_mask[i] = $urandom_range(0, 1); // Randomly set each bit
        end
        set_parameters_and_push_expected_tids(random_active_mask, unrolling_factor, 2'b00);// All threads active, 1-way unrolling, chunk 0

        // Wait for thread generation to start
        repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        rst_n = 1;  // Release reset
        $display("\n Released reset ...");
        
        wait(chunk_done);
        repeat(10)@(negedge clk);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);

    endtask
    // Main test
    initial begin
        $display("==========================================");
        $display("Simple Test: All Active, 1-Way Unrolling");
        $display("==========================================");
        
        // Initialize
        reset_system();
        rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        set_parameters_and_push_expected_tids({256{1'b1}}, 2'b00, 2'b00);// All threads active, 1-way unrolling, chunk 0
        
        // Wait for thread generation to start
        repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        rst_n = 1;  // Release reset
        restart = 0;
        $display("\n Released reset ...");

        wait(chunk_done);
        @(negedge clk);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);



        $display("==========================================");
        $display("Simple Test: All Active, 2-Way Unrolling");
        $display("==========================================");
        
        // Initialize
        reset_system();
        //rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        set_parameters_and_push_expected_tids({256{1'b1}}, 2'b01, 2'b00);// All threads active, 1-way unrolling, chunk 0
        restart = 0;
        // Wait for thread generation to start
        //repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        //rst_n = 1;  // Release reset

        $display("\n Released reset ...");
        
        wait(chunk_done);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);

        $display("==========================================");
        $display("Simple Test: All Active, 4-Way Unrolling");
        $display("==========================================");
        
        // Initialize
        reset_system();
        //rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        set_parameters_and_push_expected_tids({256{1'b1}}, 2'b10, 2'b00);// All threads active, 1-way unrolling, chunk 0
        restart = 0;
        // Wait for thread generation to start
        //repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        //rst_n = 1;  // Release reset
        
        $display("\n Released reset ...");
        
        wait(chunk_done);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);

        $display("==========================================");
        $display("Selective Disaptch Test: Partial Active, 1-Way Unrolling");
        $display("==========================================");
        
        // Initialize
        reset_system();
        //rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        for(int i=0;i<256;i++) begin
            random_active_mask[i] = $urandom_range(0, 1); // Randomly set each bit
        end
        //set_parameters_and_push_expected_tids(random_active_mask, 2'b00, 2'b00);// All threads active, 1-way unrolling, chunk 0
        set_parameters_and_push_expected_tids({8{32'h1}}, 2'b00, 2'b00);// All threads active, 1-way unrolling, chunk 0
        restart = 0;
        // Wait for thread generation to start
        //repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        //rst_n = 1;  // Release reset
        
        $display("\n Released reset ...");
        
        wait(chunk_done);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);

        $display("==========================================");
        $display("Selective Disaptch Test: Partial Active, 2-Way Unrolling with only 1 lane active");
        $display("==========================================");
        
        // Initialize
        reset_system();
        //rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        for(int i=0;i<256;i++) begin
            random_active_mask[i] = $urandom_range(0, 1); // Randomly set each bit
        end
        //set_parameters_and_push_expected_tids(random_active_mask, 2'b00, 2'b00);// All threads active, 1-way unrolling, chunk 0
        set_parameters_and_push_expected_tids({8{32'h1}}, 2'b01, 2'b00);// All threads active, 1-way unrolling, chunk 0
        restart = 0;
        // Wait for thread generation to start
        //repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        //rst_n = 1;  // Release reset
        
        $display("\n Released reset ...");

        wait(chunk_done);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);

        

        $display("==========================================");
        $display("Selective Disaptch Test: Partial Active, 4-Way Unrolling with only 1 lane active");
        $display("==========================================");
        
        // Initialize
        reset_system();
        //rst_n = 0;
        // Set up test: all threads active, 1-way unrolling, chunk 0
        @(negedge clk);
        for(int i=0;i<256;i++) begin
            random_active_mask[i] = $urandom_range(0, 1); // Randomly set each bit
        end
        //set_parameters_and_push_expected_tids(random_active_mask, 2'b00, 2'b00);// All threads active, 1-way unrolling, chunk 0
        set_parameters_and_push_expected_tids({8{32'h1}}, 2'b10, 2'b00);// All threads active, 1-way unrolling, chunk 0
        restart = 0;
        // Wait for thread generation to start
        //repeat(10) @(negedge clk);
        
        $display("\n Starting ...");
        @(negedge clk);
        //rst_n = 1;  // Release reset
        
        $display("\n Released reset ...");
        
        wait(chunk_done);
        wait(expected_threads_count == threads_popped);
        wait(expected_tids_0.size() == 0 && 
             expected_tids_1.size() == 0 && 
             expected_tids_2.size() == 0 && 
             expected_tids_3.size() == 0);


        for (int i = 0; i < 1; i++) begin
            random_test(2'b00); // Random active mask, 1-way unrolling
            random_test(2'b01); // Random active mask, 2-way unrolling
            random_test(2'b10); // Random active mask, 4-way unrolling
        end
        

        $display("\n=== Test Results ===");
        $display("PASS: All threads consumed successfully");
        $display("Total threads processed: %0d", threads_popped);
        $display("\n==========================================");
        $display("Test Completed");
        //a very big PASS message
        $display("=================================================================================");
        $display("  PPPPP      A      SSSSSS  SSSSSS ");
        $display("  P    P    A A     S       S      ");
        $display("  PPPPP    A   A    SSSSSS  SSSSSS ");
        $display("  P       AAAAAAA        S       S  ");
        $display("  P      A       A  SSSSSS  SSSSSS ");
        $display("=================================================================================");
        $display("PASS: All threads consumed successfully");
        $display("=================================================================================");
        
        $finish;
    end
    
    // Timeout protection
    initial begin
        #2000000;  // 2ms timeout
        $display("ERROR: Testbench timeout!");
        $display("Total threads processed: %0d", threads_popped);
        $display("Expected threads process: %0d", expected_threads_count);
        $display("Lane 0 remaining expected TIDs: %0d", expected_tids_0.size());
        $display("Lane 1 remaining expected TIDs: %0d", expected_tids_1.size());
        $display("Lane 2 remaining expected TIDs: %0d", expected_tids_2.size());
        $display("Lane 3 remaining expected TIDs: %0d", expected_tids_3.size());
        $display("==========================================");
        $display("Test Failed: Timeout occurred before completion");
        $display("\n==========================================");
        display_fifo_status();
        $finish;
    end
    
    // Generate waveform dump
    //initial begin
    //    $dumpfile("next_thread_logic_top.vcd");
    //    $dumpvars(0, next_thread_logic_top_testbench);
    //end

    initial begin
        // dump fsdb
        $fsdbDumpfile("next_thread_logic_top.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule