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
    //-------------------------------------------------------------------------
    // Write Interface Signals (CGRA)
    //-------------------------------------------------------------------------
    logic [TID_WIDTH-1:0]               cgra_tid_i;
    logic [(TOTAL_REGS*DATA_WIDTH)-1:0] cgra_data_i;
    logic [TOTAL_REGS-1:0]              wr_bitmap_i;
    logic                               cgra_valid_i;

    //-------------------------------------------------------------------------
    // Write Interface Signals (LDST)
    //-------------------------------------------------------------------------
    logic [$bits(cache_wr_cmd)-1:0]   ldst_wr_i;
    logic                             ldst_valid_i;
    logic                             ldst_ready_o;

    

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
    // Asserts reset for a specified number of cycles, then deasserts
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
    // Iterates through all TIDs and writes zeros to all banks
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

            // Wait one more cycle to let the last write (tid=511) propagate
            // through the single-entry buffer before deasserting valid
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

            // Check pred registers (shared, 1-bit each)
            if (pred_o !== '0) begin
                $error("[%0t] Pred regs not zero! pred_o=%0b", $time, pred_o);
                error_count++;
            end else begin
                $display("[%0t] Pred regs are zero! pred_o=%0b", $time, pred_o);
            end

            rd_tid_valid_i = 1'b0;
            rd_en_i        = 1'b0;
            rd_bitmap_i    = '0;
            @(posedge clk_i);

            if (error_count == 0) begin
                $display("[%0t] PASS: All registers verified as zero (GPR: %0d, Const: %0d, Pred: %0d)",
                         $time, NUM_TID * NUM_PORTS, NUM_CONST, NUM_PRED);
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

    // Task write cgra only
    task write_cgra_only(input logic [TID_WIDTH-1:0] tid);
        begin
            cgra_valid_i = 1'b1;
            cgra_tid_i   = tid;
            wr_bitmap_i = '1; // all regs enabled
            for (int i = 0; i < TOTAL_REGS; i++) begin
                cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH] = $urandom;
                $display("Writing to reg %0d: data=%0h", i, cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH]);
            end
            $display("CGRA write: tid=%0d, mask=%0b", cgra_tid_i, wr_bitmap_i);
            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
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
            $display("Pred output: %0b", pred_o);
            rd_tid_valid_i = 1'b0;
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

        write_cgra_only(0);
        @(posedge clk_i);
        read_cgra_only(0);
        @(posedge clk_i);
        $display("rf_rd_valid_o: %0b", rf_rd_valid_o);
        // End simulation
        #100;
        $display("=== dice_rf_ctrl Testbench End ===");
        $finish;
    end

endmodule

// verilator lint_on