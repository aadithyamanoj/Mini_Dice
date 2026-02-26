module tb_parameterized_dispatcher
    import dice_pkg::*, 
           dice_frontend_pkg::*;
();
    // =========================================================
    // From dice_config.vh / packages:
    //   DICE_NUM_MAX_THREADS_PER_CORE = 512
    //   DICE_TID_WIDTH                = $clog2(512) = 9
    //   REG_NUM                       = 16+8+8 = 32
    //   REG_INDEX_WIDTH               = $clog2(32) = 5
    //   DICE_CGRA_MEM_PORTS           = 4
    //   NUM_LD_DEST_REGS              = $clog2(4-1)+1 = 3
    //   ld_dest_regs type             = logic [2:0][4:0]  (3 entries × 5 bits)
    //   wb_tid_bitmap width           = 512 bits
    // =========================================================

    // Clock and reset
    logic clk;
    logic rst_n;

    // DUT signals
    pgraph_meta_t pgraph_meta_i;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;  // 512-bit
    cta_size_e    cta_size;
    logic         fetch_done;
    logic         wb_valid;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] wb_tid_bitmap; // 512-bit
    logic         dispatch_fifo_pop;

    // DUT outputs
    logic [4*DICE_TID_WIDTH-1:0] dispatch_tid_o;  // 36 bits (4 × 9)
    logic         dispatch_valid_o;
    logic         dispatch_fifo_empty;
    logic         dispatcher_busy;
    logic         dispatcher_done;

    // Extract individual lane TIDs from combined bus
    logic [DICE_TID_WIDTH-1:0] dispatch_tid_0, dispatch_tid_1,
                                dispatch_tid_2, dispatch_tid_3;
    logic dispatch_valid_0, dispatch_valid_1, dispatch_valid_2, dispatch_valid_3;

    assign dispatch_tid_0 = dispatch_tid_o[  DICE_TID_WIDTH-1:0              ];
    assign dispatch_tid_1 = dispatch_tid_o[2*DICE_TID_WIDTH-1:  DICE_TID_WIDTH];
    assign dispatch_tid_2 = dispatch_tid_o[3*DICE_TID_WIDTH-1:2*DICE_TID_WIDTH];
    assign dispatch_tid_3 = dispatch_tid_o[4*DICE_TID_WIDTH-1:3*DICE_TID_WIDTH];

    assign dispatch_valid_0 = dut.dispatch_valid_0;
    assign dispatch_valid_1 = dut.dispatch_valid_1;
    assign dispatch_valid_2 = dut.dispatch_valid_2;
    assign dispatch_valid_3 = dut.dispatch_valid_3;

    // Test control
    int test_num;
    int dispatched_count;

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // DUT instantiation
    dispatcher dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .pgraph_meta_i    (pgraph_meta_i),
        .active_mask      (active_mask),
        .cta_size         (cta_size),
        .fetch_done       (fetch_done),
        .wb_valid         (wb_valid),
        .wb_tid_bitmap    (wb_tid_bitmap),
        .dispatch_fifo_pop(dispatch_fifo_pop),
        .dispatch_tid_o   (dispatch_tid_o),
        .dispatch_valid_o (dispatch_valid_o),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .dispatcher_busy  (dispatcher_busy),
        .dispatcher_done  (dispatcher_done)
    );

    // =========================================================
    // bitmap_to_ld_dest_regs
    //
    // ld_dest_regs is logic[2:0][4:0] in pgraph_meta_t:
    //   - 3 entries ($clog2(DICE_CGRA_MEM_PORTS-1)+1 = 3)
    //   - each entry is 5 bits (REG_INDEX_WIDTH = $clog2(REG_NUM) = $clog2(32) = 5)
    //
    // The dispatcher's always_comb assembles ld_dest_regs_bitmap by iterating
    // over ld_dest_regs[k] and setting bit [ld_dest_regs[k]] in the flat bitmap.
    // This function reverses that: find each set bit in flat_bitmap and store
    // its index (0-31) into successive ld_dest_regs entries.
    //
    // Return type exactly matches the struct field to avoid IUDA/ICTA errors.
    // =========================================================
    localparam int NUM_LD_DEST_REGS   = $clog2(`DICE_CGRA_MEM_PORTS-1) + 1; // = 3
    localparam int REG_INDEX_W        = $clog2(REG_NUM);                     // = 5

    function automatic logic [NUM_LD_DEST_REGS-1:0][REG_INDEX_W-1:0] bitmap_to_ld_dest_regs(
        input logic [REG_NUM-1:0] flat_bitmap
    );
        int idx;
        logic [NUM_LD_DEST_REGS-1:0][REG_INDEX_W-1:0] result;
        result = '0;
        idx    = 0;
        for (int b = 0; b < REG_NUM; b++) begin
            if (flat_bitmap[b] && idx < NUM_LD_DEST_REGS) begin
                result[idx] = b[REG_INDEX_W-1:0];
                idx++;
            end
        end
        return result;
    endfunction

    // =========================================================
    // Task: reset_system
    // =========================================================
    task reset_system();
        @(negedge clk);
        $display("=== Resetting System ===");
        rst_n             = 1'b0;
        fetch_done        = 1'b0;
        active_mask       = '0;
        cta_size          = CTA_SIZE_1;
        wb_valid          = 1'b0;
        wb_tid_bitmap     = '0;
        dispatch_fifo_pop = 1'b0;
        dispatched_count  = 0;

        pgraph_meta_i.unrolling_factor = 2'b10;
        pgraph_meta_i.in_regs_bitmap   = '0;
        pgraph_meta_i.ld_dest_regs     = '0;

        repeat(3) @(negedge clk);
        rst_n = 1'b1;
        repeat(2) @(negedge clk);
        $display("Reset complete");
    endtask

    // =========================================================
    // Task: start_cta
    // in_regs is REG_NUM-wide (32 bits) matching in_regs_bitmap
    // =========================================================
    task start_cta(
        input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask,
        input logic [REG_NUM-1:0]                        regs,
        input cta_size_e                                 size,
        input logic [1:0]                                unroll
    );
        $display("Starting CTA - Size: %0d, Unroll: %0d",
                 (size == CTA_SIZE_1) ? 256 : (size == CTA_SIZE_2) ? 512 : 1024,
                 (unroll == 2'b00) ? 1 : (unroll == 2'b01) ? 2 : 4);

        active_mask                    = mask;
        pgraph_meta_i.in_regs_bitmap   = regs;
        cta_size                       = size;
        pgraph_meta_i.unrolling_factor = unroll;

        fetch_done = 1'b1;
        @(negedge clk);
        fetch_done = 1'b0;

        while (!dispatcher_busy) @(negedge clk);
        $display("Dispatcher is now busy");
        repeat(10) @(negedge clk);
    endtask

    // =========================================================
    // Task: pop_and_count
    // =========================================================
    task pop_and_count();
        if (!dispatch_fifo_empty) begin
            dispatch_fifo_pop = 1'b1;
            @(posedge clk);

            if (dispatch_valid_0) begin
                $display("  Lane 0 TID: %0d", dispatch_tid_0);
                dispatched_count++;
            end
            if (dispatch_valid_1) begin
                $display("  Lane 1 TID: %0d", dispatch_tid_1);
                dispatched_count++;
            end
            if (dispatch_valid_2) begin
                $display("  Lane 2 TID: %0d", dispatch_tid_2);
                dispatched_count++;
            end
            if (dispatch_valid_3) begin
                $display("  Lane 3 TID: %0d", dispatch_tid_3);
                dispatched_count++;
            end

            dispatch_fifo_pop = 1'b0;
        end
    endtask

    // =========================================================
    // Task: writeback_register
    //
    // Takes a flat REG_NUM (32)-wide bitmap of registers to release
    // and converts it to the packed ld_dest_regs array the dispatcher
    // expects. Both the old single-reg-number interface and the
    // undriven ld_dest_regs issue are fixed here.
    // =========================================================
    task writeback_register(
        input logic [REG_NUM-1:0]                        reg_bitmap,
        input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0]  tid_mask
    );
        $display("  Write-back: reg_bitmap=0x%0h tid_mask=0x%0h", reg_bitmap, tid_mask);
        wb_valid                   = 1'b1;
        wb_tid_bitmap              = tid_mask;
        pgraph_meta_i.ld_dest_regs = bitmap_to_ld_dest_regs(reg_bitmap);
        @(negedge clk);
        wb_valid                   = 1'b0;
        wb_tid_bitmap              = '0;
        pgraph_meta_i.ld_dest_regs = '0;
    endtask

    // =========================================================
    // Task: wait_for_completion
    // =========================================================
    task wait_for_completion();
        int timeout         = 10000;
        int idle_cycles     = 0;
        int extra_drain_cycles;

        // Stage 1: wait for done, keep draining
        while (!dispatcher_done && timeout > 0) begin
            if (!dispatch_fifo_empty) begin
                pop_and_count();
                idle_cycles = 0;
            end else begin
                @(negedge clk);
                idle_cycles++;
                if (idle_cycles > 100 && !dispatcher_done) begin
                    $display("WARNING: 100 idle cycles, not done");
                    $display("  done=%b fifo_empty=%b",
                             dispatcher_done, dispatch_fifo_empty);
                    $display("  ready_fifo_empty=%b%b%b%b",
                             dut.ready_fifo_empty[3], dut.ready_fifo_empty[2],
                             dut.ready_fifo_empty[1], dut.ready_fifo_empty[0]);
                end
            end
            timeout--;
        end

        if (timeout == 0) begin
            $display("ERROR: Timeout waiting for dispatcher_done!");
            $finish;
        end

        $display("Dispatcher done. Flushing pipeline...");

        // Stage 2: drain remaining entries
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

        // Stage 3: final settle
        repeat(5) @(negedge clk);
        if (!dispatch_fifo_empty) begin
            $display("WARNING: FIFOs not empty after drain!");
            while (!dispatch_fifo_empty && timeout > 0) begin
                pop_and_count();
                timeout--;
            end
        end

        if (timeout == 0) begin
            $display("ERROR: Timeout during pipeline flush!");
            $finish;
        end

        $display("CTA dispatch completed. Total dispatched: %0d", dispatched_count);
        $display("DEBUG: thread_fifo_empty=%b thread_chunk_done=%b",
                 dut.thread_fifo_empty, dut.thread_chunk_done);
        $display("DEBUG: ready_fifo_empty=%b%b%b%b",
                 dut.ready_fifo_empty[3], dut.ready_fifo_empty[2],
                 dut.ready_fifo_empty[1], dut.ready_fifo_empty[0]);
    endtask

    // =========================================================
    // Test 0: Initial state check
    // =========================================================
    task check_initial_state();
        $display("=== Test %0d: Initial State Check ===", ++test_num);

        if (dispatcher_busy)
            $display("ERROR: Dispatcher should not be busy initially");
        else
            $display("PASS: Dispatcher idle initially");

        if (dispatcher_done)
            $display("ERROR: Dispatcher should not be done initially");
        else
            $display("PASS: Dispatcher not done initially");

        if (!dispatch_fifo_empty)
            $display("ERROR: Dispatch FIFOs should be empty initially");
        else
            $display("PASS: All dispatch FIFOs empty initially");
    endtask

    // =========================================================
    // Test 1: Simple dispatch
    // 256 active threads in chunk 0, 4-way unrolling, 1 GPR
    // CTA_SIZE_1 = 256-thread CTA
    // =========================================================
    task test_simple_dispatch();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] simple_mask;
        $display("\n=== Test %0d: Simple Dispatch ===", ++test_num);

        simple_mask       = '0;
        simple_mask[255:0] = '1;  // 256 threads active

        start_cta(simple_mask, REG_NUM'('h1), CTA_SIZE_1, 2'b10);
        wait_for_completion();

        if (dispatched_count == 256)
            $display("PASS: Dispatched exactly 256 threads");
        else
            $display("ERROR: Expected 256 threads, got %0d", dispatched_count);

        dispatched_count = 0;
    endtask

    // =========================================================
    // Test 2: Register conflict → stall → writeback → completion
    // GPR bitmap 'h7 = GPR 0,1,2.  TID mask 'hF = TIDs 0-3.
    // =========================================================
    task test_register_conflicts();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask;
        $display("\n=== Test %0d: Register Conflict Test ===", ++test_num);

        mask      = '0;
        mask[7:0] = 8'hFF;  // 8 threads

        start_cta(mask, REG_NUM'('h7), CTA_SIZE_1, 2'b10);  // GPR 0,1,2

        repeat(20) begin
            pop_and_count();
            @(negedge clk);
        end
        $display("Dispatched before writeback: %0d", dispatched_count);

        // Release GPR 0,1,2 for TIDs 0-3
        writeback_register(REG_NUM'('h7), DICE_NUM_MAX_THREADS_PER_CORE'('hF));

        wait_for_completion();

        if (dispatched_count == 8)
            $display("PASS: All 8 threads eventually dispatched");
        else
            $display("WARNING: Dispatched %0d/8 threads", dispatched_count);

        dispatched_count = 0;
    endtask

    // =========================================================
    // Test 3: Unrolling factors
    // 32 active threads, single GPR, all three unrolling modes
    // =========================================================
    task test_unrolling_factors();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask;
        int count_1way, count_2way, count_4way;
        $display("\n=== Test %0d: Unrolling Factor Test ===", ++test_num);

        mask       = '0;
        mask[31:0] = '1;

        $display("--- 1-way ---");
        reset_system();
        start_cta(mask, REG_NUM'('h1), CTA_SIZE_1, 2'b00);
        wait_for_completion();
        count_1way       = dispatched_count;
        dispatched_count = 0;

        $display("--- 2-way ---");
        reset_system();
        start_cta(mask, REG_NUM'('h1), CTA_SIZE_1, 2'b01);
        wait_for_completion();
        count_2way       = dispatched_count;
        dispatched_count = 0;

        $display("--- 4-way ---");
        reset_system();
        start_cta(mask, REG_NUM'('h1), CTA_SIZE_1, 2'b10);
        wait_for_completion();
        count_4way       = dispatched_count;
        dispatched_count = 0;

        if (count_1way == 32 && count_2way == 32 && count_4way == 32)
            $display("PASS: All unrolling factors dispatch 32 threads");
        else begin
            $display("ERROR: Expected 32, 32, 32 – got %0d, %0d, %0d",
                     count_1way, count_2way, count_4way);
        end
    endtask

    // =========================================================
    // Test 4: Back-to-back CTAs without reset
    // Verifies scoreboard clears between CTAs via start_new_cta.
    // CTA3 uses in_regs_bitmap bits [1:0]=GPR0-1, [17:16]=CR0-1, [24]=PR0
    // (layout: GPR[15:0] | CR[23:16] | PR[31:24] for REG_NUM=32)
    // =========================================================
    task test_back_to_back_cta();
        logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] mask1, mask2, mask3;
        logic [REG_NUM-1:0] regs3;
        int cta1_count, cta2_count, cta3_count;
        $display("\n=== Test %0d: Back-to-Back CTA Dispatch (No Reset) ===", ++test_num);

        // CTA 1: 16 threads, GPR 0+1, 4-way
        mask1        = '0;
        mask1[15:0]  = '1;
        $display("\n--- CTA 1: 16 threads, GPR 0+1, 4-way ---");
        start_cta(mask1, REG_NUM'('h3), CTA_SIZE_1, 2'b10);
        wait_for_completion();
        cta1_count = dispatched_count;
        $display("CTA 1: %0d threads", cta1_count);

        if (!dispatcher_done)
            $display("ERROR: dispatcher_done not asserted after CTA 1");
        else
            $display("PASS: dispatcher_done after CTA 1");

        if (!dispatch_fifo_empty)
            $display("ERROR: FIFOs not empty before CTA 2");
        else
            $display("PASS: FIFOs empty before CTA 2");

        dispatched_count = 0;

        // CTA 2: 32 threads, GPR 0 only, 2-way
        mask2        = '0;
        mask2[31:0]  = '1;
        $display("\n--- CTA 2: 32 threads, GPR 0, 2-way ---");
        start_cta(mask2, REG_NUM'('h1), CTA_SIZE_1, 2'b01);
        wait_for_completion();
        cta2_count = dispatched_count;
        $display("CTA 2: %0d threads", cta2_count);

        if (!dispatcher_done)
            $display("ERROR: dispatcher_done not asserted after CTA 2");
        else
            $display("PASS: dispatcher_done after CTA 2");

        dispatched_count = 0;

        // CTA 3: 8 threads, GPR 0-1 + CR 0-1 + PR 0, 1-way
        // REG_NUM=32 layout: [15:0]=GPR, [23:16]=CR, [31:24]=PR
        mask3       = '0;
        mask3[7:0]  = '1;
        regs3       = '0;
        regs3[1:0]  = 2'b11;   // GPR 0-1
        regs3[17:16]= 2'b11;   // CR 0-1
        regs3[24]   = 1'b1;    // PR 0
        $display("\n--- CTA 3: 8 threads, mixed regs, 1-way ---");
        start_cta(mask3, regs3, CTA_SIZE_1, 2'b00);
        wait_for_completion();
        cta3_count = dispatched_count;
        $display("CTA 3: %0d threads", cta3_count);

        dispatched_count = 0;

        $display("\n--- Back-to-Back Results ---");
        $display("CTA 1: %0d/16", cta1_count);
        $display("CTA 2: %0d/32", cta2_count);
        $display("CTA 3: %0d/8",  cta3_count);

        if (cta1_count == 16 && cta2_count == 32 && cta3_count == 8)
            $display("PASS: All CTAs dispatched correctly");
        else begin
            $display("FAIL: Expected 16, 32, 8");
            $display("      Got %0d, %0d, %0d", cta1_count, cta2_count, cta3_count);
        end
    endtask

    // =========================================================
    // Main sequence
    // =========================================================
    initial begin
        $display("==========================================");
        $display("  Dispatcher Parameterized Testbench");
        $display("  DICE_NUM_MAX_THREADS_PER_CORE = %0d", DICE_NUM_MAX_THREADS_PER_CORE);
        $display("  DICE_TID_WIDTH                = %0d", DICE_TID_WIDTH);
        $display("  REG_NUM                       = %0d", REG_NUM);
        $display("  NUM_LD_DEST_REGS              = %0d", NUM_LD_DEST_REGS);
        $display("  REG_INDEX_W                   = %0d", REG_INDEX_W);
        $display("==========================================");

        test_num = 0;

        reset_system();
        check_initial_state();

        test_simple_dispatch();

        reset_system();
        test_register_conflicts();

        test_unrolling_factors();  // calls reset_system() internally

        reset_system();
        test_back_to_back_cta();

        $display("\n==========================================");
        $display("  Parameterized Tests Completed");
        $display("==========================================");
        $finish;
    end

    // Timeout protection
    initial begin
        #1_000_000;
        $display("ERROR: Testbench timeout!");
        $finish;
    end

    initial begin
        $fsdbDumpfile("refactored_dispatcher_param.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule