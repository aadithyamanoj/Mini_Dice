`include "dice_define.vh"

module tb_scoreboard
    import dice_pkg::*,
           dice_frontend_pkg::*;
();

    // =========================================================================
    // Clock & Reset
    // =========================================================================
    logic clk;
    logic rst_n;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // =========================================================================
    // DUT Parameters & Port Declarations
    // =========================================================================
    localparam int THREADS_PER_SCOREBOARD = 256;
    localparam int SCOREBOARD_TID_WIDTH   = $clog2(THREADS_PER_SCOREBOARD); // 8

    logic [REG_NUM-1:0]                    input_regs_map;
    logic [SCOREBOARD_TID_WIDTH-1:0]       rd_tid;
    logic                                  rd_valid;
    logic [SCOREBOARD_TID_WIDTH-1:0]       rsv_tid;
    logic                                  rsv_valid;
    logic [THREADS_PER_SCOREBOARD-1:0]     wb_tid_bitmap;
    logic [REG_NUM-1:0]                    ld_dest_regs_bitmap;
    logic                                  wb_valid;
    logic                                  clear_scoreboard;
    logic                                  collision;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    scoreboard #(
        .THREADS_PER_SCOREBOARD(THREADS_PER_SCOREBOARD),
        .SCOREBOARD_TID_WIDTH(SCOREBOARD_TID_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .input_regs_map   (input_regs_map),
        .rd_tid           (rd_tid),
        .rd_valid         (rd_valid),
        .rsv_tid          (rsv_tid),
        .rsv_valid        (rsv_valid),
        .wb_tid_bitmap    (wb_tid_bitmap),
        .ld_dest_regs_bitmap(ld_dest_regs_bitmap),
        .wb_valid         (wb_valid),
        .clear_scoreboard (clear_scoreboard),
        .collision        (collision)
    );

    // =========================================================================
    // Test Tracking
    // =========================================================================
    int test_num;
    int pass_count;
    int fail_count;

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    // Drive all inputs to a known idle state
    task automatic idle_inputs();
        input_regs_map    = '0;
        rd_tid            = '0;
        rd_valid          = 1'b0;
        rsv_tid           = '0;
        rsv_valid         = 1'b0;
        wb_tid_bitmap     = '0;
        ld_dest_regs_bitmap = '0;
        wb_valid          = 1'b0;
        clear_scoreboard  = 1'b0;
    endtask

    // Full reset sequence
    task automatic do_reset();
        idle_inputs();
        rst_n = 1'b0;
        repeat(4) @(negedge clk);
        rst_n = 1'b1;
        repeat(2) @(negedge clk);
    endtask

    // Reserve a TID with the given register bitmap (single-cycle pulse)
    task automatic reserve(
        input logic [SCOREBOARD_TID_WIDTH-1:0] tid,
        input logic [REG_NUM-1:0]              reg_map
    );
        @(negedge clk);
        rsv_tid        = tid;
        rsv_valid      = 1'b1;
        input_regs_map = reg_map;
        @(negedge clk);
        rsv_valid = 1'b0;
    endtask

    // Check collision for a TID (result is combinational – sample after 1 cycle settle)
    // Returns the collision value seen
    task automatic check_collision(
        input  logic [SCOREBOARD_TID_WIDTH-1:0] tid,
        input  logic [REG_NUM-1:0]              reg_map,
        output logic                            col_out
    );
        @(negedge clk);
        rd_tid         = tid;
        rd_valid       = 1'b1;
        input_regs_map = reg_map;
        @(negedge clk);      // One cycle for combinational settle
        col_out = collision;
        rd_valid = 1'b0;
    endtask

    // Write-back: release ld_dest registers for every TID set in the bitmap
    task automatic writeback(
        input logic [THREADS_PER_SCOREBOARD-1:0] tid_mask,
        input logic [REG_NUM-1:0]                dest_bitmap
    );
        @(negedge clk);
        wb_tid_bitmap       = tid_mask;
        ld_dest_regs_bitmap = dest_bitmap;
        wb_valid            = 1'b1;
        @(negedge clk);
        wb_valid        = 1'b0;
        wb_tid_bitmap   = '0;
        ld_dest_regs_bitmap = '0;
    endtask

    // Pulse clear_scoreboard for one cycle
    task automatic pulse_clear();
        @(negedge clk);
        clear_scoreboard = 1'b1;
        @(negedge clk);
        clear_scoreboard = 1'b0;
    endtask

    // Pass/Fail checker
    task automatic check(
        input string  test_name,
        input logic   actual,
        input logic   expected
    );
        if (actual === expected) begin
            $display("  PASS [T%0d] %s | got %0b", test_num, test_name, actual);
            pass_count++;
        end else begin
            $display("  FAIL [T%0d] %s | expected %0b, got %0b", test_num, test_name, expected, actual);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Test Cases
    // =========================================================================

    // -----------------------------------------------------------------
    // T1: After reset, no collision on any TID
    // -----------------------------------------------------------------
    task automatic test_reset_clean();
        logic col;
        test_num++;
        $display("\n=== T%0d: Post-Reset Clean State ===", test_num);

        // Check TID 0, 127, 255 with a non-zero reg map
        check_collision(8'd0,   REG_NUM'('hFF), col); check("TID=0   no collision after reset",   col, 1'b0);
        check_collision(8'd127, REG_NUM'('hFF), col); check("TID=127 no collision after reset", col, 1'b0);
        check_collision(8'd255, REG_NUM'('hFF), col); check("TID=255 no collision after reset", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T2: Basic reserve → collision → writeback → no collision
    // -----------------------------------------------------------------
    task automatic test_basic_reserve_wb();
        logic col;
        logic [REG_NUM-1:0] reg_map;
        test_num++;
        $display("\n=== T%0d: Basic Reserve / Writeback ===", test_num);

        reg_map = REG_NUM'('h3);  // GPR 0 & 1

        // Reserve TID 10
        reserve(8'd10, reg_map);

        // Should collide when checking same TID with overlapping reg_map
        check_collision(8'd10, reg_map, col);
        check("collision after reserve", col, 1'b1);

        // Non-overlapping reg_map should NOT collide
        check_collision(8'd10, REG_NUM'('hC), col);  // GPR 2 & 3 – no overlap
        check("no collision non-overlapping regs", col, 1'b0);

        // Different TID should NOT collide
        check_collision(8'd11, reg_map, col);
        check("no collision different TID", col, 1'b0);

        // Write back TID 10, release the registers
        writeback(THREADS_PER_SCOREBOARD'(1 << 10), reg_map);
        repeat(2) @(negedge clk);  // Let FF update propagate

        // Should no longer collide
        check_collision(8'd10, reg_map, col);
        check("no collision after writeback", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T3: Partial writeback – collision persists for unreleased bits
    // -----------------------------------------------------------------
    task automatic test_partial_writeback();
        logic col;
        logic [REG_NUM-1:0] full_map, partial_map, remaining_map;
        test_num++;
        $display("\n=== T%0d: Partial Writeback ===", test_num);

        full_map      = REG_NUM'('h7);  // GPR 0,1,2
        partial_map   = REG_NUM'('h3);  // GPR 0,1 only
        remaining_map = REG_NUM'('h4);  // GPR 2 only

        reserve(8'd20, full_map);

        // Write back only GPR 0,1
        writeback(THREADS_PER_SCOREBOARD'(1 << 20), partial_map);
        repeat(2) @(negedge clk);

        // GPR 2 is still reserved – checking with remaining_map should still collide
        check_collision(8'd20, remaining_map, col);
        check("collision persists for unreleased GPR", col, 1'b1);

        // Checking with already-released GPRs should NOT collide
        check_collision(8'd20, partial_map, col);
        check("no collision for released GPRs", col, 1'b0);

        // Write back GPR 2 as well
        writeback(THREADS_PER_SCOREBOARD'(1 << 20), remaining_map);
        repeat(2) @(negedge clk);

        check_collision(8'd20, full_map, col);
        check("no collision after full writeback", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T4: rd_valid=0 → collision must always be 0
    // -----------------------------------------------------------------
    task automatic test_rd_valid_gate();
        logic col;
        test_num++;
        $display("\n=== T%0d: rd_valid Gate ===", test_num);

        reserve(8'd30, REG_NUM'('hFF));

        @(negedge clk);
        rd_tid         = 8'd30;
        rd_valid       = 1'b0;         // Explicitly NOT valid
        input_regs_map = REG_NUM'('hFF);
        @(negedge clk);
        col = collision;
        rd_valid = 1'b0;

        check("no collision when rd_valid=0", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T5: rd_tid_conflict – TID in both check and wb_tid_bitmap simultaneously
    // -----------------------------------------------------------------
    task automatic test_rd_tid_conflict();
        logic col;
        test_num++;
        $display("\n=== T%0d: rd_tid_conflict (simultaneous rd and wb) ===", test_num);

        reserve(8'd40, REG_NUM'('h1));

        // Drive read and wb simultaneously in same cycle
        @(negedge clk);
        rd_tid              = 8'd40;
        rd_valid            = 1'b1;
        input_regs_map      = REG_NUM'('h1);
        wb_tid_bitmap       = THREADS_PER_SCOREBOARD'(1 << 40);
        ld_dest_regs_bitmap = REG_NUM'('h1);
        wb_valid            = 1'b1;
        @(negedge clk);
        col = collision;
        // rd_tid_conflict should fire → collision expected
        check("rd_tid_conflict causes collision", col, 1'b1);

        rd_valid  = 1'b0;
        wb_valid  = 1'b0;
        wb_tid_bitmap = '0;
        ld_dest_regs_bitmap = '0;
    endtask

    // -----------------------------------------------------------------
    // T6: Fusion – reserve and writeback same TID in same cycle
    // -----------------------------------------------------------------
    task automatic test_fusion();
        logic col;
        logic [REG_NUM-1:0] old_regs, new_regs, dest_regs;
        test_num++;
        $display("\n=== T%0d: Fusion (rsv + wb same TID) ===", test_num);

        old_regs  = REG_NUM'('h3);  // GPR 0,1 currently reserved
        new_regs  = REG_NUM'('hC);  // GPR 2,3 new reservation
        dest_regs = REG_NUM'('h3);  // releasing GPR 0,1

        reserve(8'd50, old_regs);

        // Simultaneous reserve of new regs AND writeback of old regs for same TID
        @(negedge clk);
        rsv_tid             = 8'd50;
        rsv_valid           = 1'b1;
        input_regs_map      = new_regs;
        wb_tid_bitmap       = THREADS_PER_SCOREBOARD'(1 << 50);
        ld_dest_regs_bitmap = dest_regs;
        wb_valid            = 1'b1;
        @(negedge clk);
        rsv_valid = 1'b0;
        wb_valid  = 1'b0;
        wb_tid_bitmap = '0;
        ld_dest_regs_bitmap = '0;

        repeat(2) @(negedge clk);

        // Old regs (GPR 0,1) should be released
        check_collision(8'd50, old_regs, col);
        check("old regs released after fusion", col, 1'b0);

        // New regs (GPR 2,3) should now be reserved
        check_collision(8'd50, new_regs, col);
        check("new regs reserved after fusion", col, 1'b1);
    endtask

    // -----------------------------------------------------------------
    // T7: clear_scoreboard takes highest priority and clears everything
    // -----------------------------------------------------------------
    task automatic test_clear_priority();
        logic col;
        test_num++;
        $display("\n=== T%0d: clear_scoreboard Priority ===", test_num);

        // Reserve several TIDs
        reserve(8'd0,   REG_NUM'('hFF));
        reserve(8'd100, REG_NUM'('hFF));
        reserve(8'd255, REG_NUM'('hFF));

        // Confirm they're reserved
        check_collision(8'd0,   REG_NUM'('hFF), col); check("TID=0   reserved pre-clear",   col, 1'b1);
        check_collision(8'd100, REG_NUM'('hFF), col); check("TID=100 reserved pre-clear", col, 1'b1);
        check_collision(8'd255, REG_NUM'('hFF), col); check("TID=255 reserved pre-clear", col, 1'b1);

        pulse_clear();
        repeat(2) @(negedge clk);

        // All should be clean now
        check_collision(8'd0,   REG_NUM'('hFF), col); check("TID=0   clear after clear_sb",   col, 1'b0);
        check_collision(8'd100, REG_NUM'('hFF), col); check("TID=100 clear after clear_sb", col, 1'b0);
        check_collision(8'd255, REG_NUM'('hFF), col); check("TID=255 clear after clear_sb", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T8: clear_scoreboard overrides simultaneous reserve
    // -----------------------------------------------------------------
    task automatic test_clear_overrides_reserve();
        logic col;
        test_num++;
        $display("\n=== T%0d: clear_scoreboard Overrides Simultaneous Reserve ===", test_num);

        @(negedge clk);
        rsv_tid          = 8'd60;
        rsv_valid        = 1'b1;
        input_regs_map   = REG_NUM'('hF);
        clear_scoreboard = 1'b1;        // Both asserted simultaneously
        @(negedge clk);
        rsv_valid        = 1'b0;
        clear_scoreboard = 1'b0;

        repeat(2) @(negedge clk);

        // Clear should win – TID 60 must NOT be reserved
        check_collision(8'd60, REG_NUM'('hF), col);
        check("clear wins over simultaneous reserve", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T9: Boundary TIDs – TID 0 and TID 255
    // -----------------------------------------------------------------
    task automatic test_boundary_tids();
        logic col;
        test_num++;
        $display("\n=== T%0d: Boundary TIDs (0 and 255) ===", test_num);

        reserve(8'd0,   REG_NUM'('h1));
        reserve(8'd255, REG_NUM'('h2));

        check_collision(8'd0,   REG_NUM'('h1), col); check("TID=0   collision",   col, 1'b1);
        check_collision(8'd255, REG_NUM'('h2), col); check("TID=255 collision", col, 1'b1);

        // Cross-check: TID 0's reg map should NOT collide with TID 255
        check_collision(8'd255, REG_NUM'('h1), col); check("TID=255 no collision on TID-0 regs", col, 1'b0);

        writeback(THREADS_PER_SCOREBOARD'(1 << 0),   REG_NUM'('h1));
        writeback(THREADS_PER_SCOREBOARD'(1 << 255), REG_NUM'('h2));
        repeat(2) @(negedge clk);

        check_collision(8'd0,   REG_NUM'('h1), col); check("TID=0   clear after wb",   col, 1'b0);
        check_collision(8'd255, REG_NUM'('h2), col); check("TID=255 clear after wb", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T10: Bulk writeback – wide bitmap releases many TIDs at once
    // -----------------------------------------------------------------
    task automatic test_bulk_writeback();
        logic col;
        logic [THREADS_PER_SCOREBOARD-1:0] bulk_mask;
        test_num++;
        $display("\n=== T%0d: Bulk Writeback (wide bitmap) ===", test_num);

        // Reserve TIDs 0..7
        for (int t = 0; t < 8; t++)
            reserve(t[SCOREBOARD_TID_WIDTH-1:0], REG_NUM'('h1));

        // Confirm all reserved
        for (int t = 0; t < 8; t++) begin
            check_collision(t[SCOREBOARD_TID_WIDTH-1:0], REG_NUM'('h1), col);
            if (!col) begin
                $display("  FAIL [T%0d] TID=%0d not reserved before bulk wb", test_num, t);
                fail_count++;
            end else pass_count++;
        end

        // Release all 8 in one wb cycle
        bulk_mask = THREADS_PER_SCOREBOARD'('hFF);  // TIDs 0-7
        writeback(bulk_mask, REG_NUM'('h1));
        repeat(2) @(negedge clk);

        for (int t = 0; t < 8; t++) begin
            check_collision(t[SCOREBOARD_TID_WIDTH-1:0], REG_NUM'('h1), col);
            check($sformatf("TID=%0d clear after bulk wb", t), col, 1'b0);
        end
    endtask

    // -----------------------------------------------------------------
    // T11: Multi-bit register map – single bit overlap causes collision
    // -----------------------------------------------------------------
    task automatic test_single_bit_overlap();
        logic col;
        test_num++;
        $display("\n=== T%0d: Single-Bit Overlap Triggers Collision ===", test_num);

        // Reserve TID 70 with GPR 5 only
        reserve(8'd70, REG_NUM'(1 << 5));

        // Check with a map that overlaps ONLY on bit 5
        check_collision(8'd70, REG_NUM'(1 << 5), col);
        check("single overlapping bit causes collision", col, 1'b1);

        // Check with a map that has many bits but NOT bit 5
        check_collision(8'd70, REG_NUM'('hFFFFFFDF), col);  // All bits except bit 5
        check("no collision when bit 5 excluded from check", col, 1'b0);
    endtask

    // -----------------------------------------------------------------
    // T12: Multiple TIDs with different register maps – no cross-talk
    // -----------------------------------------------------------------
    task automatic test_no_cross_tid_pollution();
        logic col;
        test_num++;
        $display("\n=== T%0d: No Cross-TID Pollution ===", test_num);

        reserve(8'd80, REG_NUM'('h1));  // GPR 0
        reserve(8'd81, REG_NUM'('h2));  // GPR 1
        reserve(8'd82, REG_NUM'('h4));  // GPR 2

        // Each TID should only collide on its own register
        check_collision(8'd80, REG_NUM'('h2), col); check("TID=80 no collision on GPR1", col, 1'b0);
        check_collision(8'd81, REG_NUM'('h4), col); check("TID=81 no collision on GPR2", col, 1'b0);
        check_collision(8'd82, REG_NUM'('h1), col); check("TID=82 no collision on GPR0", col, 1'b0);

        check_collision(8'd80, REG_NUM'('h1), col); check("TID=80 collision on GPR0",   col, 1'b1);
        check_collision(8'd81, REG_NUM'('h2), col); check("TID=81 collision on GPR1",   col, 1'b1);
        check_collision(8'd82, REG_NUM'('h4), col); check("TID=82 collision on GPR2",   col, 1'b1);
    endtask

    // =========================================================================
    // Main Sequence
    // =========================================================================
    initial begin
        $display("==========================================");
        $display("  Scoreboard Standalone Testbench");
        $display("  REG_NUM = %0d", REG_NUM);
        $display("  THREADS = %0d", THREADS_PER_SCOREBOARD);
        $display("==========================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        do_reset();

        test_reset_clean();
        do_reset();

        test_basic_reserve_wb();
        do_reset();

        test_partial_writeback();
        do_reset();

        test_rd_valid_gate();
        do_reset();

        test_rd_tid_conflict();
        do_reset();

        test_fusion();
        do_reset();

        test_clear_priority();
        do_reset();

        test_clear_overrides_reserve();
        do_reset();

        test_boundary_tids();
        do_reset();

        test_bulk_writeback();
        do_reset();

        test_single_bit_overlap();
        do_reset();

        test_no_cross_tid_pollution();

        // Final summary
        $display("\n==========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** FAILURES DETECTED ***");

        $finish;
    end

    // Timeout Guard
    initial begin
        #500000;
        $display("ERROR: Testbench global timeout!");
        $finish;
    end

    // Waveform Dump
    initial begin
        $fsdbDumpfile("tb_scoreboard_refactor.fsdb");
        $fsdbDumpvars("+all");
    end

endmodule