// verilator lint_off 
`include "DE_pkg.sv"
`include "dice_pkg.sv"

module dice_rf_ctrl_tb;

import DE_pkg::*;
import dice_pkg::*;


    initial begin
        $fsdbDumpfile("dice_rf_ctrl_tb.fsdb");
        $fsdbDumpvars(0, "+all");
    end

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    localparam int NUM_PORTS       = DICE_NUM_BANKS;
    localparam int DATA_WIDTH      = DICE_REG_DATA_WIDTH;
    localparam int NUM_TID         = DICE_NUM_MAX_THREADS_PER_CORE;
    localparam int TID_WIDTH       = $clog2(NUM_TID);
    localparam int DEPTH           = NUM_TID;
    localparam int ADDR_WIDTH      = $clog2(DEPTH);
    localparam int NUM_SPECIAL_REG = `DICE_PR_NUM;
    localparam int MAX_CTA_ID      = `DICE_MAX_GRID_SIZE;
    localparam int CTA_ID_WIDTH    = $clog2(MAX_CTA_ID);

    // Clock period
    localparam int CLK_PERIOD = 10;

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
    logic [1:0]                       rd_unroll_factor_i;
    logic                             rd_en_i;
    logic [(4*TID_WIDTH)-1:0]         rd_tid_i;
    logic [NUM_PORTS-1:0]             rd_bitmap_i;
    logic [NUM_PORTS*DATA_WIDTH-1:0]  rd_data_o;
    logic                             rf_rd_valid_o;
    //-------------------------------------------------------------------------
    // Write Interface Signals (CGRA)
    //-------------------------------------------------------------------------
    logic [(4*TID_WIDTH)-1:0]           cgra_tid_i;
    logic [(NUM_PORTS*DATA_WIDTH)-1:0]  cgra_data_i;
    logic [NUM_PORTS-1:0]               wr_bitmap_i;
    logic                               cgra_valid_i;

    //-------------------------------------------------------------------------
    // Write Interface Signals (LDST)
    //-------------------------------------------------------------------------
    reg_wr_cmd [NUM_PORTS-1:0]        ldst_wr_i;
    logic                             ldst_valid_i;
    logic                             ldst_ready_o;

    //-------------------------------------------------------------------------
    // Special Register Interface Signals
    //-------------------------------------------------------------------------

    logic [NUM_SPECIAL_REG-1:0]            clear_i;
    logic [NUM_SPECIAL_REG-1:0]            spec_rd_enable_i;
    logic [NUM_SPECIAL_REG*4-1:0]          spec_reg_sel_i;
    logic [NUM_SPECIAL_REG*DATA_WIDTH-1:0] const_reg_i;

    // TID info
    logic [TID_WIDTH-1:0]   tid_x_i;
    logic [TID_WIDTH-1:0]   tid_y_i;
    logic [TID_WIDTH-1:0]   tid_z_i;
    logic [TID_WIDTH-1:0]   ntid_x_i;
    logic [TID_WIDTH-1:0]   ntid_y_i;
    logic [TID_WIDTH-1:0]   ntid_z_i;
    logic [CTA_ID_WIDTH-1:0] ctaid_x_i;
    logic [CTA_ID_WIDTH-1:0] ctaid_y_i;
    logic [CTA_ID_WIDTH-1:0] ctaid_z_i;
    logic [CTA_ID_WIDTH-1:0] nctaid_x_i;
    logic [CTA_ID_WIDTH-1:0] nctaid_y_i;
    logic [CTA_ID_WIDTH-1:0] nctaid_z_i;

    // Special register output
    logic [NUM_SPECIAL_REG*DATA_WIDTH-1:0] spec_reg_out_o;

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
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
        , .NUM_SPECIAL_REG (NUM_SPECIAL_REG)
        , .MAX_CTA_ID      (MAX_CTA_ID)
        , .CTA_ID_WIDTH    (CTA_ID_WIDTH)
    ) dut (
          .clk_i              (clk_i)           // clock
        , .reset_i            (reset_i)
        , .clear_i            (clear_i)
        // Read interface
        , .rd_tid_valid_i     (rd_tid_valid_i)
        , .rd_tid_ready_o     (rd_tid_ready_o)
        , .rd_unroll_factor_i (rd_unroll_factor_i)
        , .rd_en_i            (rd_en_i)
        , .rd_tid_i           (rd_tid_i)
        , .rd_bitmap_i        (rd_bitmap_i)
        , .rd_data_o          (rd_data_o)
        , .rf_rd_valid_o      (rf_rd_valid_o)
        // CGRA write interface
        , .cgra_tid_i         (cgra_tid_i)
        , .cgra_data_i        (cgra_data_i)
        , .wr_bitmap_i        (wr_bitmap_i)
        , .cgra_valid_i       (cgra_valid_i)

        // LDST write interface
        , .ldst_wr_i          (ldst_wr_i)
        , .ldst_valid_i       (ldst_valid_i)
        , .ldst_ready_o       (ldst_ready_o)

        // Special register interface
        , .spec_rd_enable_i   (spec_rd_enable_i)
        , .spec_reg_sel_i     (spec_reg_sel_i)
        , .const_reg_i        (const_reg_i)
        , .tid_x_i            (tid_x_i)
        , .tid_y_i            (tid_y_i)
        , .tid_z_i            (tid_z_i)
        , .ntid_x_i           (ntid_x_i)
        , .ntid_y_i           (ntid_y_i)
        , .ntid_z_i           (ntid_z_i)
        , .ctaid_x_i          (ctaid_x_i)
        , .ctaid_y_i          (ctaid_y_i)
        , .ctaid_z_i          (ctaid_z_i)
        , .nctaid_x_i         (nctaid_x_i)
        , .nctaid_y_i         (nctaid_y_i)
        , .nctaid_z_i         (nctaid_z_i)
        , .spec_reg_out_o     (spec_reg_out_o)
    );

    //-------------------------------------------------------------------------
    // Tasks
    //-------------------------------------------------------------------------

    // Reset DUT task
    // Asserts reset for a specified number of cycles, then deasserts
    task reset_dut(input int num_cycles = 5);
        begin
            // Initialize all inputs to known state
            rd_tid_valid_i     = 1'b0;
            rd_unroll_factor_i = 2'b0;
            rd_en_i            = 1'b0;
            rd_tid_i           = '0;
            rd_bitmap_i        = '0;

            cgra_tid_i   = '0;
            cgra_data_i  = '0;
            wr_bitmap_i  = '0;
            cgra_valid_i = 1'b0;

            for (int i = 0; i < NUM_PORTS; i++) begin
                ldst_wr_i[i] = '0;
            end
            ldst_valid_i = 1'b0;

            clear_i          = '0;
            spec_rd_enable_i = '0;
            spec_reg_sel_i   = '0;
            const_reg_i      = '0;

            tid_x_i    = '0;
            tid_y_i    = '0;
            tid_z_i    = '0;
            ntid_x_i   = '0;
            ntid_y_i   = '0;
            ntid_z_i   = '0;
            ctaid_x_i  = '0;
            ctaid_y_i  = '0;
            ctaid_z_i  = '0;
            nctaid_x_i = '0;
            nctaid_y_i = '0;
            nctaid_z_i = '0;

            // Assert reset
            reset_i = 1'b1;
            repeat (num_cycles) @(posedge clk_i);

            // Deassert reset
            reset_i = 1'b0;
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
            wr_bitmap_i = '1;  // Enable all banks

            for (int tid = 0; tid < NUM_TID; tid++) begin
                cgra_tid_i = '0;
                cgra_tid_i[0 +: TID_WIDTH] = tid[TID_WIDTH-1:0];
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

            rd_bitmap_i        = '1;  // Read all banks
            rd_unroll_factor_i = 2'b00;
            rd_en_i            = 1'b1;

            for (int tid = 0; tid < NUM_TID; tid++) begin
                rd_tid_i = '0;
                rd_tid_i[0 +: TID_WIDTH] = tid[TID_WIDTH-1:0];
                rd_tid_valid_i = 1'b1;
                @(posedge clk_i);

                // Wait one cycle for read data to be available
                @(posedge clk_i);

                // Check all banks for this TID
                for (int bank = 0; bank < NUM_PORTS; bank++) begin
                    if (rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH] !== '0) begin
                        $error("[%0t] Register not zero! TID=%0d, Bank=%0d, Data=0x%0h",
                               $time, tid, bank, rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH]);
                        error_count++;
                    end else begin
                        $display("[%0t] Register is zero! TID=%0d, Bank=%0d, Data=0x%0h",
                               $time, tid, bank, rd_data_o[bank*DATA_WIDTH +: DATA_WIDTH]);
                    end
                end
            end

            rd_tid_valid_i = 1'b0;
            rd_en_i        = 1'b0;
            rd_bitmap_i    = '0;
            @(posedge clk_i);

            if (error_count == 0) begin
                $display("[%0t] PASS: All %0d registers verified as zero", $time, NUM_TID * NUM_PORTS);
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
    task write_cgra_only(input logic [(4*TID_WIDTH)-1:0] tid);
        begin
            cgra_valid_i = 1'b1;
            cgra_tid_i   = tid;
            wr_bitmap_i = 32'b11111111111111111111111111111111; // 32-bit mask, all banks enabled
            for (int i = 0; i < NUM_PORTS; i++) begin
                cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH] = $urandom;
                $display("Writing to bank %0d: data=%0h", i, cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH]);
            end
            $display("CGRA write: tid=%0d, mask=%0b", cgra_tid_i[0 +: TID_WIDTH], wr_bitmap_i);
            @(posedge clk_i);
            @(posedge clk_i);
            cgra_valid_i = 1'b0;
        end
    endtask


    task read_cgra_only(input logic [(4*TID_WIDTH)-1:0] tid);
        begin
            $display("Reading from cgra only");
            rd_tid_valid_i = 1'b1;
            rd_tid_i = tid;
            rd_bitmap_i = NUM_PORTS'('1);

            @(posedge clk_i);
            @(posedge clk_i);
            $display("rf_rd_valid_o: %0b", rf_rd_valid_o);
            for (int i = 0; i < NUM_PORTS; i++) begin
                $display("Read data from bank %0d: %0h", i, rd_data_o[i*DATA_WIDTH +: DATA_WIDTH]);
            end
            rd_tid_valid_i = 1'b0;
        end
    endtask




    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("=== dice_rf_ctrl Testbench Start ===");

        // Apply reset
        reset_dut(5);

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