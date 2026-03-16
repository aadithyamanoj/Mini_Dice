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

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam int NUM_PORTS       = DICE_NUM_BANKS;
    localparam int DATA_WIDTH      = DICE_REG_DATA_WIDTH;
    localparam int NUM_TID         = DICE_NUM_MAX_THREADS_PER_CORE;
    localparam int TID_WIDTH       = $clog2(NUM_TID);
    localparam int DEPTH           = DICE_REGS_PER_BANK;
    localparam int ADDR_WIDTH      = $clog2(DEPTH);
    localparam int NUM_CONST       = DICE_NUM_CONST;
    localparam int NUM_PRED        = DICE_NUM_PRED;
    localparam int TOTAL_REGS     = DICE_TOTAL_REGS;
    localparam int BUF_DEPTH       = LDST_BUF_DEPTH;

    // Clock period
    localparam int CLK_PERIOD = 20000;

    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    logic clk_i;
    logic reset_i;

    //-------------------------------------------------------------------------
    // Read Interface Signals
    //-------------------------------------------------------------------------
    logic                             rd_tid_valid_i;
    logic                             rd_tid_ready_o;
    logic                             rd_en_i;
    logic [TID_WIDTH-1:0]             rd_tid_i;
    logic [TOTAL_REGS-1:0]            rd_bitmap_i;
    logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0] rd_data_o;
    logic                             rf_rd_valid_o;
    logic [TID_WIDTH-1:0]             tid_o;
    //-------------------------------------------------------------------------
    // Write Interface Signals (CGRA)
    //-------------------------------------------------------------------------
    logic [TID_WIDTH-1:0]                                     cgra_tid_i;
    logic [((NUM_PORTS+NUM_PRED+1)*DATA_WIDTH)-1:0]           cgra_data_i;
    logic [TOTAL_REGS-1:0]                                    wr_bitmap_i;
    logic                                                     cgra_valid_i;

    //-------------------------------------------------------------------------
    // Write Interface Signals (LDST)
    //-------------------------------------------------------------------------
    logic [$bits(cache_wr_cmd)-1:0]   ldst_wr_i;
    logic                             ldst_valid_i;
    logic                             ldst_ready_o;

    // Predicate output — selected TID only, NUM_PRED bits
    logic [NUM_PRED-1:0] pred_o;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
        reset_i = 1;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    //-------------------------------------------------------------------------
    // DUT Instantiation
    //-------------------------------------------------------------------------
    dice_rf_ctrl #(
          .NUM_PORTS       (NUM_PORTS)
        , .DATA_WIDTH      (DATA_WIDTH)
        , .NUM_TID         (NUM_TID)
        , .TID_WIDTH       (TID_WIDTH)
        , .DEPTH           (DEPTH)
        , .ADDR_WIDTH      (ADDR_WIDTH)
        , .NUM_CONST       (NUM_CONST)
        , .NUM_PRED        (NUM_PRED)
        , .TOTAL_REGS      (TOTAL_REGS)
        , .BUF_DEPTH       (BUF_DEPTH)
    ) dut (
          .clk_i              (clk_i)
        , .reset_i            (reset_i)
        // Read interface
        , .rd_tid_valid_i     (rd_tid_valid_i)
        , .rd_tid_ready_o     (rd_tid_ready_o)
        , .rd_en_i            (rd_en_i)
        , .rd_tid_i           (rd_tid_i)
        , .rd_bitmap_i        (rd_bitmap_i)
        , .rd_data_o          (rd_data_o)
        , .rf_rd_valid_o      (rf_rd_valid_o)
        , .tid_o              (tid_o)
        // Predicate output
        , .pred_o             (pred_o)
        // CGRA write interface
        , .cgra_tid_i         (cgra_tid_i)
        , .cgra_data_i        (cgra_data_i)
        , .wr_bitmap_i        (wr_bitmap_i)
        , .cgra_valid_i       (cgra_valid_i)
        // LDST write interface
        , .ldst_wr_i          (ldst_wr_i)
        , .ldst_valid_i       (ldst_valid_i)
        , .ldst_ready_o       (ldst_ready_o)
    );

    //-------------------------------------------------------------------------
    // Tasks
    //-------------------------------------------------------------------------

    // Dump all localparams defined in this module
    task dump_params();
        begin
            $display("=== Module Parameters ===");
            $display("  NUM_PORTS       = %0d", NUM_PORTS);
            $display("  DATA_WIDTH      = %0d", DATA_WIDTH);
            $display("  NUM_TID         = %0d", NUM_TID);
            $display("  TID_WIDTH       = %0d", TID_WIDTH);
            $display("  DEPTH           = %0d", DEPTH);
            $display("  ADDR_WIDTH      = %0d", ADDR_WIDTH);
            $display("  NUM_CONST       = %0d", NUM_CONST);
            $display("  NUM_PRED        = %0d", NUM_PRED);
            $display("  TOTAL_REGS      = %0d", TOTAL_REGS);
            $display("  BUF_DEPTH       = %0d", BUF_DEPTH);
            $display("  CLK_PERIOD      = %0d", CLK_PERIOD);
            $display("=========================");
        end
    endtask

    // Reset DUT task
    task reset_dut(input int num_cycles = 5);
        begin
            // Initialize all inputs to known state
            rd_tid_valid_i     <= 1'b0;
            rd_en_i            <= 1'b0;
            rd_tid_i           <= '0;
            rd_bitmap_i        <= '0;

            cgra_tid_i   <= '0;
            cgra_data_i  <= '0;
            wr_bitmap_i  <= '0;
            cgra_valid_i <= 1'b0;

            ldst_wr_i    <= '0;
            ldst_valid_i <= 1'b0;

            // Assert reset
            reset_i <= 1'b1;
            repeat (num_cycles) @(posedge clk_i);

            // Deassert reset
            reset_i <= 1'b0;
            @(posedge clk_i);

            // Write all registers to zero
            clear_all_registers();

            $display("[%0t] Reset complete", $time);
        end
    endtask

    // Task to write all registers to zero
    task clear_all_registers();
        begin
            $display("[%0t] Clearing all registers...", $time);
            cgra_data_i = '0;
            wr_bitmap_i = '1;  // Enable all regs

            for (int tid = 0; tid < NUM_TID; tid++) begin
                cgra_tid_i = tid[TID_WIDTH-1:0];
                cgra_valid_i = 1'b1;
                @(posedge clk_i);
            end

            // Wait one more cycle to let the last write propagate
            @(posedge clk_i);

            cgra_valid_i = 1'b0;
            wr_bitmap_i  = '0;
            @(posedge clk_i);
            $display("[%0t] All registers cleared", $time);

            // Verify all registers are zero
            verify_all_registers_zero();
        end
    endtask

    // Task to verify all registers are zero
    task verify_all_registers_zero();
        int error_count;
        begin
            $display("[%0t] Verifying all registers are zero...", $time);
            error_count = 0;

            rd_bitmap_i        = '1;  // Read all regs
            rd_en_i            = 1'b1;

            for (int tid = 0; tid < NUM_TID; tid++) begin
                rd_tid_i = tid[TID_WIDTH-1:0];
                rd_tid_valid_i = 1'b1;
                @(posedge clk_i);

                // Wait one cycle for read data to be available
                @(posedge clk_i);

                // Check all GPR banks for this TID
                for (int bank = 0; bank < NUM_PORTS; bank++) begin
                    if (rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH] !== '0) begin
                        $error("[%0t] GPR not zero! TID=%0d, Bank=%0d, Data=0x%0h",
                               $time, tid, bank, rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH]);
                        error_count++;
                    end else begin
                        $display("[%0t] GPR is zero! TID=%0d, Bank=%0d, Data=0x%0h",
                               $time, tid, bank, rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH]);
                    end
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

            rd_tid_valid_i = 1'b0;
            rd_en_i        = 1'b0;
            rd_bitmap_i    = '0;
            @(posedge clk_i);

            if (error_count == 0) begin
                $display("[%0t] PASS: All registers verified as zero (GPR: %0d, Const: %0d, Pred: %0d x %0d TIDs)",
                         $time, NUM_TID * NUM_PORTS, NUM_CONST, NUM_PRED, NUM_TID);
            end else begin
                $error("[%0t] FAIL: %0d registers were not zero", $time, error_count);
            end

            assert (error_count == 0) else $fatal(1, "Register clear verification failed!");
        end
    endtask

    initial begin
        void'($urandom(32'hdead_beef)); // seed once
    end



    //-------------------------------------------------------------------------
    // Functions
    //-------------------------------------------------------------------------

    // Generate a random reg_wr_cmd struct (for LDST writes)
    function automatic reg_wr_cmd gen_rand_reg_wr_cmd();
        reg_wr_cmd cmd;
        cmd.tid       = $urandom;
        cmd.data      = $urandom;
        cmd.mask = 1'b1;
        return cmd;
    endfunction

    // Generate a random reg_wr_cmd with specific tid (for LDST writes)
    function automatic reg_wr_cmd gen_rand_reg_wr_cmd_with_tid(
          input logic [$clog2(NUM_TID)-1:0] tid
    );
        reg_wr_cmd cmd;
        cmd.tid       = tid;
        cmd.data      = $urandom;
        cmd.mask = 1'b1;
        return cmd;
    endfunction

    // Generate a specific reg_wr_cmd (for directed tests)
    function automatic reg_wr_cmd gen_reg_wr_cmd(
          input logic [$clog2(NUM_TID)-1:0]        tid
        , input logic [DICE_REG_DATA_WIDTH-1:0]    data
        , input logic                              mask
    );
        reg_wr_cmd cmd;
        cmd.tid       = tid;
        cmd.data      = data;
        cmd.mask = mask;
        return cmd;
    endfunction

    // Build a cache_wr_cmd for LDST const/pred writes
    function automatic cache_wr_cmd build_ldst_special_cmd(
          input logic [DICE_REG_ADDR_WIDTH-1:0]    dest_reg
        , input logic [TID_WIDTH-1:0]              base_tid
        , input logic [DATA_WIDTH-1:0]             data_val
    );
        cache_wr_cmd cmd;
        cmd = '0;
        cmd.tid = base_tid;
        cmd.wr_bitmap[dest_reg] = 1'b1;
        cmd.data = data_val;
        return cmd;
    endfunction

    // Task: CGRA write to GPR banks with random data
    // cgra_data_i layout in the DUT:
    //   [0 : NUM_PORTS*DW-1]                    = GPR data (one per bank)
    //   [NUM_PORTS*DW : (NUM_PORTS+1)*DW-1]     = const data (shared for all masked const regs)
    //   bit (NUM_PORTS+1+j)*DW                  = pred data for pred j
    task write_cgra_only(input logic [TID_WIDTH-1:0] tid);
        begin
            cgra_valid_i = 1'b1;
            cgra_tid_i   = tid;
            wr_bitmap_i = '0;

            // Write GPR banks only
            for (int i = 0; i < NUM_PORTS; i++) begin
                wr_bitmap_i[i] = 1'b1;
                cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH] = $urandom;
                $display("Writing GPR bank %0d: data=%0h", i, cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH]);
            end
            $display("CGRA write: tid=%0d, mask=%0b", cgra_tid_i, wr_bitmap_i);
            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
        end
    endtask

    // Task: CGRA write to a specific const register
    // const data comes from cgra_data_i[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH]
    task write_cgra_const(
          input logic [TID_WIDTH-1:0] tid
        , input int const_idx
        , input logic [DATA_WIDTH-1:0] data_val
    );
        begin
            cgra_valid_i = 1'b1;
            cgra_tid_i   = tid;
            cgra_data_i  = '0;
            wr_bitmap_i  = '0;
            // Set the const mask bit in bitmap
            wr_bitmap_i[NUM_PORTS + const_idx] = 1'b1;
            // Const data is at the shared const slot
            cgra_data_i[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH] = data_val;
            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
            wr_bitmap_i  = '0;
            @(posedge clk_i);
            $display("[%0t] CGRA const write: const_idx=%0d, data=0x%0h", $time, const_idx, data_val);
        end
    endtask

    // Task: CGRA write to a specific pred register
    // pred data for pred j comes from cgra_data_i bit (NUM_PORTS+1+j)*DATA_WIDTH
    task write_cgra_pred(
          input logic [TID_WIDTH-1:0] tid
        , input int pred_idx
        , input logic pred_val
    );
        begin
            cgra_valid_i = 1'b1;
            cgra_tid_i   = tid;
            cgra_data_i  = '0;
            wr_bitmap_i  = '0;
            // Set the pred mask bit in bitmap
            wr_bitmap_i[NUM_PORTS + NUM_CONST + pred_idx] = 1'b1;
            // Pred data bit location
            cgra_data_i[(NUM_PORTS + 1 + pred_idx)*DATA_WIDTH] = pred_val;
            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
            wr_bitmap_i  = '0;
            @(posedge clk_i);
            $display("[%0t] CGRA pred write: pred_idx=%0d, tid=%0d, val=%0b", $time, pred_idx, tid, pred_val);
        end
    endtask

    task read_cgra_only(input logic [TID_WIDTH-1:0] tid);
        begin
            $display("Reading from cgra only");
            rd_tid_valid_i = 1'b1;
            rd_tid_i = tid;
            rd_bitmap_i = TOTAL_REGS'('1);

            @(posedge clk_i);
            @(posedge clk_i);
            $display("rf_rd_valid_o: %0b", rf_rd_valid_o);
            for (int i = 0; i < NUM_PORTS; i++) begin
                $display("Read GPR bank %0d: %0h", i, rd_data_o[i*DATA_WIDTH +: DATA_WIDTH]);
            end
            for (int i = 0; i < NUM_CONST; i++) begin
                $display("Read const %0d: %0h", i, rd_data_o[(NUM_PORTS+i)*DATA_WIDTH +: DATA_WIDTH]);
            end
            // pred_o is muxed by rd_tid_i, so it shows preds for the selected TID
            for (int p = 0; p < NUM_PRED; p++) begin
                $display("Pred[%0d] for TID %0d: %0b", p, tid, pred_o[p]);
            end
            rd_tid_valid_i = 1'b0;
        end
    endtask

    // LDST write to a const register
    task write_ldst_const(
          input logic [DICE_REG_ADDR_WIDTH-1:0] const_idx  // 0-based const index
        , input logic [DATA_WIDTH-1:0]          data_val
    );
        cache_wr_cmd cmd;
        begin
            cmd = build_ldst_special_cmd(
                DICE_REG_ADDR_WIDTH'(NUM_PORTS + const_idx),
                '0,  // base_tid irrelevant for const
                data_val
            );
            ldst_wr_i = cmd;
            ldst_valid_i = 1'b1;
            @(posedge clk_i);
            ldst_valid_i = 1'b0;
            // Wait for FIFO to drain (CGRA idle)
            @(posedge clk_i);
            @(posedge clk_i);
            $display("[%0t] LDST const write: const_idx=%0d, data=0x%0h", $time, const_idx, data_val);
        end
    endtask

    // LDST write to a pred register
    task write_ldst_pred(
          input logic [DICE_REG_ADDR_WIDTH-1:0] pred_idx   // 0-based pred index
        , input logic [TID_WIDTH-1:0]           tid
        , input logic                           pred_val
    );
        cache_wr_cmd cmd;
        begin
            cmd = build_ldst_special_cmd(
                DICE_REG_ADDR_WIDTH'(NUM_PORTS + NUM_CONST + pred_idx),
                tid,
                DATA_WIDTH'(pred_val)
            );
            ldst_wr_i = cmd;
            ldst_valid_i = 1'b1;
            @(posedge clk_i);
            ldst_valid_i = 1'b0;
            // Wait for FIFO to drain
            @(posedge clk_i);
            @(posedge clk_i);
            $display("[%0t] LDST pred write: pred_idx=%0d, tid=%0d, val=%0b", $time, pred_idx, tid, pred_val);
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("=== dice_rf_ctrl Testbench Start ===");

        dump_params();
        $display("reg_wr_cmd_width: %0d: ", $bits(reg_wr_cmd));

        // Apply reset
        reset_dut(20);

        // ---- Test 1: CGRA GPR write/read ----
        $display("\n=== Test 1: CGRA GPR write/read ===");
        write_cgra_only(0);
        @(posedge clk_i);
        read_cgra_only(0);
        @(posedge clk_i);
        $display("rf_rd_valid_o: %0b", rf_rd_valid_o);

        // ---- Test 2: LDST const write ----
        $display("\n=== Test 2: LDST const register write ===");
        write_ldst_const(0, 8'hAB);
        // Verify const reg 0 updated (const regs are combinational on rd_data_o)
        for (int c = 0; c < NUM_CONST; c++) begin
            $display("[%0t] Const[%0d] = 0x%0h", $time, c,
                     rd_data_o[(NUM_PORTS+c)*DATA_WIDTH +: DATA_WIDTH]);
        end
        assert (rd_data_o[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH] === 8'hAB)
            else $error("LDST const write failed: expected 0xAB, got 0x%0h",
                        rd_data_o[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH]);

        // Write to a different const reg
        write_ldst_const(3, 8'hCD);
        $display("[%0t] Const[3] = 0x%0h", $time,
                 rd_data_o[(NUM_PORTS+3)*DATA_WIDTH +: DATA_WIDTH]);
        assert (rd_data_o[(NUM_PORTS+3)*DATA_WIDTH +: DATA_WIDTH] === 8'hCD)
            else $error("LDST const[3] write failed: expected 0xCD, got 0x%0h",
                        rd_data_o[(NUM_PORTS+3)*DATA_WIDTH +: DATA_WIDTH]);

        // ---- Test 3: CGRA const write ----
        $display("\n=== Test 3: CGRA const register write ===");
        write_cgra_const(0, 1, 8'hEF);
        $display("[%0t] Const[1] = 0x%0h", $time,
                 rd_data_o[(NUM_PORTS+1)*DATA_WIDTH +: DATA_WIDTH]);
        assert (rd_data_o[(NUM_PORTS+1)*DATA_WIDTH +: DATA_WIDTH] === 8'hEF)
            else $error("CGRA const[1] write failed: expected 0xEF, got 0x%0h",
                        rd_data_o[(NUM_PORTS+1)*DATA_WIDTH +: DATA_WIDTH]);
        // Verify const[0] still holds 0xAB from Test 2
        assert (rd_data_o[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH] === 8'hAB)
            else $error("Const[0] corrupted: expected 0xAB, got 0x%0h",
                        rd_data_o[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH]);

        // ---- Test 4: LDST pred write (per-TID) ----
        $display("\n=== Test 4: LDST pred register write (per-TID) ===");
        // Write pred[0] = 1 for TID 0
        write_ldst_pred(0, 0, 1'b1);
        // Select TID 0 to read pred
        rd_tid_i = '0;
        @(posedge clk_i);
        $display("[%0t] pred_o (TID 0) = %0b", $time, pred_o);
        assert (pred_o[0] === 1'b1)
            else $error("LDST pred[0] TID=0 write failed: expected 1, got %0b", pred_o[0]);

        // Write pred[1] = 1 for TID 5
        write_ldst_pred(1, 5, 1'b1);
        // Select TID 5 to read pred
        rd_tid_i = TID_WIDTH'(5);
        @(posedge clk_i);
        $display("[%0t] pred_o (TID 5) = %0b", $time, pred_o);
        assert (pred_o[1] === 1'b1)
            else $error("LDST pred[1] TID=5 write failed: expected 1, got %0b", pred_o[1]);

        // Verify TID 0 pred[0] is still set
        rd_tid_i = '0;
        @(posedge clk_i);
        assert (pred_o[0] === 1'b1)
            else $error("LDST pred[0] TID=0 was corrupted");

        // Verify other TIDs pred[0] are still 0
        for (int t = 1; t < NUM_TID; t++) begin
            rd_tid_i = TID_WIDTH'(t);
            @(posedge clk_i);
            if (t != 5) begin // TID 5 has pred[1] set, but pred[0] should still be 0
                assert (pred_o[0] === 1'b0)
                    else $error("LDST pred[0] TID=%0d should be 0, got %0b", t, pred_o[0]);
            end
        end

        // Write pred[0] = 0 for TID 0 (clear it)
        write_ldst_pred(0, 0, 1'b0);
        rd_tid_i = '0;
        @(posedge clk_i);
        assert (pred_o[0] === 1'b0)
            else $error("LDST pred[0] TID=0 clear failed");

        // ---- Test 5: CGRA pred write ----
        $display("\n=== Test 5: CGRA pred write ===");
        write_cgra_pred(TID_WIDTH'(3), 0, 1'b1);
        // Select TID 3 to verify
        rd_tid_i = TID_WIDTH'(3);
        @(posedge clk_i);
        $display("[%0t] After CGRA pred write: pred_o[0] for TID 3 = %0b", $time, pred_o[0]);
        assert (pred_o[0] === 1'b1)
            else $error("CGRA pred write TID=3 pred[0] failed");

        // Verify other TID not affected
        rd_tid_i = TID_WIDTH'(0);
        @(posedge clk_i);
        assert (pred_o[0] === 1'b0)
            else $error("CGRA pred write leaked to TID 0");

        // ---- Test 6: CGRA write all reg types simultaneously ----
        $display("\n=== Test 6: CGRA simultaneous GPR + const + pred write ===");
        begin
            logic [DATA_WIDTH-1:0] gpr_expected [NUM_PORTS];
            logic [DATA_WIDTH-1:0] const_expected;
            logic pred_expected;

            cgra_valid_i = 1'b1;
            cgra_tid_i   = TID_WIDTH'(7);
            cgra_data_i  = '0;
            wr_bitmap_i  = '0;

            // Write all GPR banks
            for (int i = 0; i < NUM_PORTS; i++) begin
                wr_bitmap_i[i] = 1'b1;
                gpr_expected[i] = $urandom;
                cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH] = gpr_expected[i];
            end
            // Write const[2]
            wr_bitmap_i[NUM_PORTS + 2] = 1'b1;
            const_expected = $urandom;
            cgra_data_i[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH] = const_expected;
            // Write pred[1]
            wr_bitmap_i[NUM_PORTS + NUM_CONST + 1] = 1'b1;
            pred_expected = 1'b1;
            cgra_data_i[(NUM_PORTS + 1 + 1)*DATA_WIDTH] = pred_expected;

            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
            wr_bitmap_i  = '0;

            // Read back GPRs
            rd_tid_valid_i = 1'b1;
            rd_tid_i = TID_WIDTH'(7);
            rd_bitmap_i = TOTAL_REGS'('1);
            rd_en_i = 1'b1;
            @(posedge clk_i);
            @(posedge clk_i);

            for (int i = 0; i < NUM_PORTS; i++) begin
                $display("[%0t] GPR[%0d] TID 7: expected=0x%0h, got=0x%0h",
                         $time, i, gpr_expected[i], rd_data_o[i*DATA_WIDTH +: DATA_WIDTH]);
                assert (rd_data_o[i*DATA_WIDTH +: DATA_WIDTH] === gpr_expected[i])
                    else $error("GPR[%0d] TID 7 mismatch", i);
            end

            // Check const[2]
            $display("[%0t] Const[2]: expected=0x%0h, got=0x%0h",
                     $time, const_expected, rd_data_o[(NUM_PORTS+2)*DATA_WIDTH +: DATA_WIDTH]);
            assert (rd_data_o[(NUM_PORTS+2)*DATA_WIDTH +: DATA_WIDTH] === const_expected)
                else $error("Const[2] mismatch");

            // Check pred[1] for TID 7
            $display("[%0t] Pred[1] TID 7: expected=%0b, got=%0b",
                     $time, pred_expected, pred_o[1]);
            assert (pred_o[1] === pred_expected)
                else $error("Pred[1] TID 7 mismatch");

            rd_tid_valid_i = 1'b0;
            rd_en_i = 1'b0;
            rd_bitmap_i = '0;
        end

        // End simulation
        #100;
        $display("\n=== dice_rf_ctrl Testbench End ===");
        $finish;
    end

endmodule

// verilator lint_on
