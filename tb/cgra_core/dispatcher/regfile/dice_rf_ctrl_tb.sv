// verilator lint_off
`include "DE_pkg.sv"
`include "dice_pkg.sv"

module dice_rf_ctrl_tb;

import DE_pkg::*;
import dice_pkg::*;

    initial begin
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    // ---------------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------------
    localparam int NUM_PORTS  = DICE_NUM_BANKS;
    localparam int DATA_WIDTH = DICE_REG_DATA_WIDTH;
    localparam int NUM_TID    = DICE_NUM_MAX_THREADS_PER_CORE;
    localparam int TID_WIDTH  = $clog2(NUM_TID);
    localparam int DEPTH      = DICE_REGS_PER_BANK;
    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int NUM_CONST  = DICE_NUM_CONST;
    localparam int NUM_PRED   = DICE_NUM_PRED;
    localparam int TOTAL_REGS = DICE_TOTAL_REGS;
    localparam int BUF_DEPTH  = LDST_BUF_DEPTH;
    localparam int CLK_PERIOD = 20000;
    localparam int CGRA_DATA_WIDTH = (NUM_PORTS + NUM_PRED + 1) * DATA_WIDTH;

    // ---------------------------------------------------------------
    // DUT signals
    // ---------------------------------------------------------------
    logic clk_i;
    logic reset_i;

    logic                  rd_tid_valid_i;
    logic                  rd_tid_ready_o;
    logic [TID_WIDTH-1:0]  rd_tid_i;
    logic [TOTAL_REGS-1:0] rd_bitmap_i;
    logic [TOTAL_REGS-1:0] wr_bitmap_i;
    logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0] rd_data_o;
    logic                  rf_rd_valid_o;
    logic [TID_WIDTH-1:0]  tid_o;
    logic [TOTAL_REGS-1:0] wr_bitmap_o;

    logic [TID_WIDTH-1:0]       cgra_tid_i;
    logic [CGRA_DATA_WIDTH-1:0] cgra_data_i;
    logic [TOTAL_REGS-1:0]      cgra_wr_bitmap_i;
    logic                       cgra_valid_i;

    logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i;
    logic                           ldst_valid_i;
    logic                           ldst_ready_o;

    logic [NUM_PRED-1:0] pred_o;

    // ---------------------------------------------------------------
    // Scoreboard: expected register state
    // ---------------------------------------------------------------
    logic [DATA_WIDTH-1:0] exp_gpr  [NUM_TID-1:0][NUM_PORTS-1:0];
    logic [DATA_WIDTH-1:0] exp_const[NUM_CONST-1:0];
    logic                  exp_pred [NUM_TID-1:0][NUM_PRED-1:0];

    int test_num;
    int err_count;

    // ---------------------------------------------------------------
    // Clock
    // ---------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
        reset_i = 1;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    dice_rf_ctrl #(
          .NUM_PORTS  (NUM_PORTS)
        , .DATA_WIDTH (DATA_WIDTH)
        , .NUM_TID    (NUM_TID)
        , .TID_WIDTH  (TID_WIDTH)
        , .DEPTH      (DEPTH)
        , .ADDR_WIDTH (ADDR_WIDTH)
        , .NUM_CONST  (NUM_CONST)
        , .NUM_PRED   (NUM_PRED)
        , .TOTAL_REGS (TOTAL_REGS)
        , .BUF_DEPTH  (BUF_DEPTH)
    ) dut (
          .clk_i          (clk_i)
        , .reset_i        (reset_i)
        , .rd_tid_valid_i (rd_tid_valid_i)
        , .rd_tid_ready_o (rd_tid_ready_o)
        , .rd_tid_i       (rd_tid_i)
        , .rd_bitmap_i    (rd_bitmap_i)
        , .wr_bitmap_i    (wr_bitmap_i)
        , .rd_data_o      (rd_data_o)
        , .rf_rd_valid_o  (rf_rd_valid_o)
        , .tid_o          (tid_o)
        , .wr_bitmap_o    (wr_bitmap_o)
        , .pred_o         (pred_o)
        , .cgra_tid_i     (cgra_tid_i)
        , .cgra_data_i    (cgra_data_i)
        , .cgra_wr_bitmap_i(cgra_wr_bitmap_i)
        , .cgra_valid_i   (cgra_valid_i)
        , .ldst_wr_i      (ldst_wr_i)
        , .ldst_valid_i   (ldst_valid_i)
        , .ldst_ready_o   (ldst_ready_o)
    );

    // ---------------------------------------------------------------
    // Helper: idle all inputs (call at negedge or between edges)
    // ---------------------------------------------------------------
    task automatic idle_inputs;
        rd_tid_valid_i   = 1'b0;
        rd_tid_i         = '0;
        rd_bitmap_i      = '0;
        wr_bitmap_i      = '0;
        cgra_tid_i       = '0;
        cgra_data_i      = '0;
        cgra_wr_bitmap_i = '0;
        cgra_valid_i     = 1'b0;
        ldst_wr_i        = '0;
        ldst_valid_i     = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // Helper: zero the scoreboard
    // ---------------------------------------------------------------
    task automatic init_scoreboard;
        for (int t = 0; t < NUM_TID; t++) begin
            for (int b = 0; b < NUM_PORTS; b++)
                exp_gpr[t][b] = '0;
            for (int p = 0; p < NUM_PRED; p++)
                exp_pred[t][p] = 1'b0;
        end
        for (int c = 0; c < NUM_CONST; c++)
            exp_const[c] = '0;
    endtask

    // ---------------------------------------------------------------
    // CGRA write: drive on negedge, DUT samples on posedge, deassert
    //   on next negedge. Takes 1 clock cycle.
    // ---------------------------------------------------------------
    task automatic do_cgra_write(
          input logic [TID_WIDTH-1:0]       tid
        , input logic [TOTAL_REGS-1:0]      bitmap
        , input logic [CGRA_DATA_WIDTH-1:0] data
    );
        @(negedge clk_i);
        cgra_tid_i       = tid;
        cgra_data_i      = data;
        cgra_wr_bitmap_i = bitmap;
        cgra_valid_i     = 1'b1;

        // Update scoreboard
        for (int b = 0; b < NUM_PORTS; b++)
            if (bitmap[b])
                exp_gpr[tid][b] = data[b*DATA_WIDTH +: DATA_WIDTH];

        for (int c = 0; c < NUM_CONST; c++)
            if (bitmap[NUM_PORTS + c])
                exp_const[c] = data[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH];

        for (int p = 0; p < NUM_PRED; p++)
            if (bitmap[NUM_PORTS + NUM_CONST + p])
                exp_pred[tid][p] = data[(NUM_PORTS + 1 + p) * DATA_WIDTH];

        @(negedge clk_i);
        cgra_valid_i     = 1'b0;
        cgra_wr_bitmap_i = '0;
        cgra_data_i      = '0;
    endtask

    // ---------------------------------------------------------------
    // LDST write helpers
    // ---------------------------------------------------------------
    function automatic cache_wr_cmd make_ldst_cmd(
          input logic [TID_WIDTH-1:0]  tid
        , input logic [DATA_WIDTH-1:0] data
        , input logic [TOTAL_REGS-1:0] bitmap
    );
        cache_wr_cmd cmd;
        cmd           = '0;
        cmd.tid       = tid;
        cmd.data      = data;
        cmd.wr_bitmap = bitmap;
        return cmd;
    endfunction

    // Drive LDST for 1 cycle (negedge → posedge → negedge)
    task automatic do_ldst_write(input cache_wr_cmd cmd);
        @(negedge clk_i);
        ldst_wr_i    = cmd;
        ldst_valid_i = 1'b1;

        // Update scoreboard
        for (int b = 0; b < NUM_PORTS; b++)
            if (cmd.wr_bitmap[b])
                exp_gpr[cmd.tid][b] = cmd.data;

        for (int c = 0; c < NUM_CONST; c++)
            if (cmd.wr_bitmap[NUM_PORTS + c])
                exp_const[c] = cmd.data;

        for (int p = 0; p < NUM_PRED; p++)
            if (cmd.wr_bitmap[NUM_PORTS + NUM_CONST + p])
                exp_pred[cmd.tid][p] = cmd.data[0];

        @(negedge clk_i);
        ldst_valid_i = 1'b0;
        ldst_wr_i    = '0;
    endtask

    // ---------------------------------------------------------------
    // Read-back and check.
    //   Drive rd_tid_valid_i on negedge, DUT samples on posedge,
    //   deassert on next negedge, then sample outputs on posedge
    //   (1-cycle read latency from synchronous RAM).
    // ---------------------------------------------------------------
    task automatic read_and_check(
          input logic [TID_WIDTH-1:0]  tid
        , input string                 tag
    );
        // Drive read request on negedge
        @(negedge clk_i);
        rd_tid_i       = tid;
        rd_bitmap_i    = '1;
        wr_bitmap_i    = '0;
        rd_tid_valid_i = 1'b1;

        // Deassert on next negedge (posedge between: request sampled)
        @(negedge clk_i);
        rd_tid_valid_i = 1'b0;
        rd_bitmap_i    = '0;

        // Sample outputs on next posedge (1-cycle latency)
        @(posedge clk_i);

        if (rf_rd_valid_o !== 1'b1) begin
            $error("[%s] tid=%0d: rf_rd_valid_o not asserted", tag, tid);
            err_count++;
        end

        // Check GPR banks
        for (int b = 0; b < NUM_PORTS; b++) begin
            logic [DATA_WIDTH-1:0] got;
            got = rd_data_o[b*DATA_WIDTH +: DATA_WIDTH];
            if (got !== exp_gpr[tid][b]) begin
                $error("[%s] GPR mismatch tid=%0d bank=%0d exp=0x%0h got=0x%0h",
                       tag, tid, b, exp_gpr[tid][b], got);
                err_count++;
            end
        end

        // Check const regs
        for (int c = 0; c < NUM_CONST; c++) begin
            logic [DATA_WIDTH-1:0] got;
            got = rd_data_o[(NUM_PORTS + c)*DATA_WIDTH +: DATA_WIDTH];
            if (got !== exp_const[c]) begin
                $error("[%s] CONST mismatch const=%0d exp=0x%0h got=0x%0h",
                       tag, c, exp_const[c], got);
                err_count++;
            end
        end

        // Check pred regs (registered on rd_tid_r, aligned with rf_rd_valid_o)
        for (int p = 0; p < NUM_PRED; p++) begin
            if (pred_o[p] !== exp_pred[tid][p]) begin
                $error("[%s] PRED mismatch tid=%0d pred=%0d exp=%0b got=%0b",
                       tag, tid, p, exp_pred[tid][p], pred_o[p]);
                err_count++;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Read-back all TIDs and check (pipelined: 1 result per cycle)
    // ---------------------------------------------------------------
    task automatic read_and_check_all(input string tag);
        // Drive first read request
        @(negedge clk_i);
        rd_tid_valid_i = 1'b1;
        rd_bitmap_i    = '1;
        wr_bitmap_i    = '0;
        rd_tid_i       = TID_WIDTH'(0);

        for (int t = 0; t < NUM_TID; t++) begin
            // Advance to next negedge — set up next TID or deassert
            @(negedge clk_i);
            if (t < NUM_TID - 1)
                rd_tid_i = TID_WIDTH'(t + 1);
            else
                rd_tid_valid_i = 1'b0;

            // Sample result for TID t on posedge (1-cycle latency)
            @(posedge clk_i);

            if (rf_rd_valid_o !== 1'b1) begin
                $error("[%s] tid=%0d: rf_rd_valid_o not asserted", tag, t);
                err_count++;
            end

            for (int b = 0; b < NUM_PORTS; b++) begin
                logic [DATA_WIDTH-1:0] got;
                got = rd_data_o[b*DATA_WIDTH +: DATA_WIDTH];
                if (got !== exp_gpr[t][b]) begin
                    $error("[%s] GPR mismatch tid=%0d bank=%0d exp=0x%0h got=0x%0h",
                           tag, t, b, exp_gpr[t][b], got);
                    err_count++;
                end

                // Check pred registers for this TID (pred_o is muxed by rd_tid_i)
                for (int p = 0; p < NUM_PRED; p++) begin
                    if (pred_o[p] !== 1'b0) begin
                        $error("[%0t] Pred reg not zero! TID=%0d, Pred=%0d, Val=%0b",
                               $time, tid, p, pred_o[p]);
                        error_count++;
                    end
                end
            end

            // Check const registers (shared, only need to check once)
            for (int c = 0; c < NUM_CONST; c++) begin
                if (rd_data_o[(NUM_PORTS+c)*DATA_WIDTH +: DATA_WIDTH] !== '0) begin
                    $error("[%0t] Const reg not zero! Const=%0d, Data=0x%0h",
                           $time, c, rd_data_o[(NUM_PORTS+c)*DATA_WIDTH +: DATA_WIDTH]);
                    error_count++;
                end else begin
                    $display("[%0t] Const reg is zero! Const=%0d, Data=0x%0h",
                           $time, c, rd_data_o[(NUM_PORTS+c)*DATA_WIDTH +: DATA_WIDTH]);
                end
            end

            for (int c = 0; c < NUM_CONST; c++) begin
                logic [DATA_WIDTH-1:0] got;
                got = rd_data_o[(NUM_PORTS + c)*DATA_WIDTH +: DATA_WIDTH];
                if (got !== exp_const[c]) begin
                    $error("[%s] CONST mismatch const=%0d exp=0x%0h got=0x%0h",
                           tag, c, exp_const[c], got);
                    err_count++;
                end
            end

            for (int p = 0; p < NUM_PRED; p++) begin
                if (pred_o[p] !== exp_pred[t][p]) begin
                    $error("[%s] PRED mismatch tid=%0d pred=%0d exp=%0b got=%0b",
                           tag, t, p, exp_pred[t][p], pred_o[p]);
                    err_count++;
                end
            end
        end

        rd_bitmap_i = '0;
    endtask

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        logic [CGRA_DATA_WIDTH-1:0] wr_data;
        logic [TOTAL_REGS-1:0]      bitmap;
        cache_wr_cmd                 ldst_cmd;

        $display("=== dice_rf_ctrl directed test start ===");
        err_count = 0;
        test_num  = 0;

        // ===========================================================
        // TEST 1: Reset
        //   Assert reset, then clear all registers via CGRA writes,
        //   then read back every TID and verify all zeros.
        // ===========================================================
        test_num++;
        $display("--- Test %0d: Reset and clear ---", test_num);

        idle_inputs();
        init_scoreboard();
        @(negedge clk_i);
        reset_i = 1'b1;
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        reset_i = 1'b0;

        // Write all GPR banks to zero for every TID via CGRA
        for (int t = 0; t < NUM_TID; t++)
            do_cgra_write(TID_WIDTH'(t), '1, '0);

        // Read back all TIDs — everything should be zero
        read_and_check_all("reset_clear");

        // ===========================================================
        // TEST 2: CGRA writes to specific banks / TIDs
        //   Write distinct data to a few TIDs targeting specific
        //   GPR banks, const, and pred regs. Read back and verify.
        // ===========================================================
        test_num++;
        $display("--- Test %0d: CGRA targeted writes ---", test_num);

        // Write TID 3: GPR banks 0-7 with unique values
        wr_data = '0;
        for (int b = 0; b < NUM_PORTS; b++)
            wr_data[b*DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(8'hA0 + b);
        bitmap = '0;
        bitmap[NUM_PORTS-1:0] = '1;
        do_cgra_write(TID_WIDTH'(3), bitmap, wr_data);
        read_and_check(TID_WIDTH'(3), "cgra_gpr_tid3");

        // Write TID 7: only banks 1 and 5
        wr_data = '0;
        wr_data[1*DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(8'hB1);
        wr_data[5*DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(8'hB5);
        bitmap = '0;
        bitmap[1] = 1'b1;
        bitmap[5] = 1'b1;
        do_cgra_write(TID_WIDTH'(7), bitmap, wr_data);
        read_and_check(TID_WIDTH'(7), "cgra_gpr_tid7");
        // Verify TID 3 is unchanged
        read_and_check(TID_WIDTH'(3), "cgra_gpr_tid3_recheck");

        // Write const registers (shared across TIDs)
        wr_data = '0;
        wr_data[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(8'hCC);
        bitmap = '0;
        bitmap[NUM_PORTS]     = 1'b1;  // const 0
        bitmap[NUM_PORTS + 3] = 1'b1;  // const 3
        do_cgra_write(TID_WIDTH'(0), bitmap, wr_data);
        read_and_check(TID_WIDTH'(0), "cgra_const");
        // Const is shared — verify from a different TID too
        read_and_check(TID_WIDTH'(5), "cgra_const_othertid");

        // Write pred registers for TID 10
        wr_data = '0;
        wr_data[(NUM_PORTS + 1)*DATA_WIDTH] = 1'b1;  // pred 0 = 1
        bitmap = '0;
        bitmap[NUM_PORTS + NUM_CONST] = 1'b1;  // pred 0
        do_cgra_write(TID_WIDTH'(10), bitmap, wr_data);
        read_and_check(TID_WIDTH'(10), "cgra_pred_tid10");
        // Other TIDs pred should be unaffected
        read_and_check(TID_WIDTH'(0), "cgra_pred_tid0_unaffected");

        // ===========================================================
        // TEST 3: Uncontested LDST writes (CGRA not writing)
        //   CGRA is idle. Issue LDST writes and verify.
        //   LDST data enqueues in FIFO on cycle N, drains and writes
        //   RF on cycle N+1 (since CGRA is idle).
        // ===========================================================
        test_num++;
        $display("--- Test %0d: Uncontested LDST writes ---", test_num);

        // LDST write to TID 5, banks 2 and 4
        bitmap = '0;
        bitmap[2] = 1'b1;
        bitmap[4] = 1'b1;
        ldst_cmd = make_ldst_cmd(TID_WIDTH'(5), DATA_WIDTH'(8'hDD), bitmap);
        do_ldst_write(ldst_cmd);
        // FIFO drains on next posedge (between this negedge and read_and_check's negedge)
        read_and_check(TID_WIDTH'(5), "ldst_gpr_tid5");

        // LDST write to TID 1, bank 0 and const 2
        bitmap = '0;
        bitmap[0]             = 1'b1;
        bitmap[NUM_PORTS + 2] = 1'b1;
        ldst_cmd = make_ldst_cmd(TID_WIDTH'(1), DATA_WIDTH'(8'hEE), bitmap);
        do_ldst_write(ldst_cmd);
        read_and_check(TID_WIDTH'(1), "ldst_gpr_const_tid1");

        // LDST write to TID 12, pred 1
        bitmap = '0;
        bitmap[NUM_PORTS + NUM_CONST + 1] = 1'b1;
        ldst_cmd = make_ldst_cmd(TID_WIDTH'(12), DATA_WIDTH'(8'h01), bitmap);
        do_ldst_write(ldst_cmd);
        read_and_check(TID_WIDTH'(12), "ldst_pred_tid12");

        // ===========================================================
        // TEST 4: LDST blocked by CGRA — buffer fill and drain
        //   Hold cgra_valid_i high (zero bitmap → no real writes) to
        //   block LDST drain. Fill LDST buffers until ldst_ready_o
        //   drops. Release CGRA, let buffers drain, verify.
        // ===========================================================
        test_num++;
        $display("--- Test %0d: LDST buffer fill/drain under CGRA contention ---", test_num);

        // Hold CGRA valid (no-op) on negedge to block LDST drain
        @(negedge clk_i);
        cgra_tid_i       = '0;
        cgra_data_i      = '0;
        cgra_wr_bitmap_i = '0;
        cgra_valid_i     = 1'b1;

        // Fill LDST buffers — write to bank 0 for distinct TIDs
        begin
            int writes_accepted;
            writes_accepted = 0;

            for (int t = 0; t < NUM_TID; t++) begin
                // At negedge: ldst_ready_o is stable from last posedge
                @(negedge clk_i);
                if (ldst_ready_o !== 1'b1) break;

                bitmap = '0;
                bitmap[0] = 1'b1;
                ldst_cmd = make_ldst_cmd(
                    TID_WIDTH'(t),
                    DATA_WIDTH'(8'hF0 + t),
                    bitmap
                );
                ldst_wr_i    = ldst_cmd;
                ldst_valid_i = 1'b1;

                // Scoreboard (these will land after drain)
                exp_gpr[t][0] = DATA_WIDTH'(8'hF0 + t);
                writes_accepted++;

                // Posedge between this negedge and next: FIFO enqueues
            end

            // Deassert LDST
            @(negedge clk_i);
            ldst_valid_i = 1'b0;
            ldst_wr_i    = '0;

            $display("  Accepted %0d LDST writes before buffer full", writes_accepted);

            if (writes_accepted != BUF_DEPTH)
                $error("[buf_fill] Expected %0d writes accepted, got %0d", BUF_DEPTH, writes_accepted);
        end

        // Release CGRA — let LDST buffers drain
        @(negedge clk_i);
        cgra_valid_i = 1'b0;

        // Wait for all buffered writes to drain into RF
        repeat (BUF_DEPTH + 2) @(posedge clk_i);

        // Verify LDST ready recovered
        @(negedge clk_i);
        if (ldst_ready_o !== 1'b1) begin
            $error("[buf_drain] ldst_ready_o did not recover after drain");
            err_count++;
        end

        // Verify final state for the TIDs we wrote
        for (int t = 0; t < BUF_DEPTH; t++)
            read_and_check(TID_WIDTH'(t), "ldst_drain");

        // ===========================================================
        // Done
        // ===========================================================
        if (err_count == 0)
            $display("=== ALL %0d TESTS PASSED ===", test_num);
        else
            $display("=== FAILED: %0d errors across %0d tests ===", err_count, test_num);

        #100;
        $finish;
    end

endmodule

// verilator lint_on
