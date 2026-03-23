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
    localparam int WRITE_TO_READ_LATENCY = 1;
    localparam int WRITE_HOLD_CYCLES = 1;

    logic clk_i;
    logic reset_i;

    logic                  rd_tid_valid_i;
    logic                  rd_tid_ready_o;
    logic                  rd_en_i;
    logic [TID_WIDTH-1:0]  rd_tid_i;
    logic [TOTAL_REGS-1:0] rd_bitmap_i;
    logic [TOTAL_REGS-1:0] wr_bitmap_i;
    logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0] rd_data_o;
    logic                  rf_rd_valid_o;
    logic [TID_WIDTH-1:0]  tid_o;
    logic [TOTAL_REGS-1:0] wr_bitmap_o;
    logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0] sampled_rd_data_r;
    logic [NUM_PRED-1:0]                        sampled_pred_r;

    logic [TID_WIDTH-1:0]       cgra_tid_i;
    logic [CGRA_DATA_WIDTH-1:0] cgra_data_i;
    logic [TOTAL_REGS-1:0]      cgra_wr_bitmap_i;
    logic                       cgra_valid_i;

    logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i;
    logic                           ldst_valid_i;
    logic                           ldst_ready_o;

    logic [NUM_PRED-1:0] pred_o;

    logic [DATA_WIDTH-1:0] exp_gpr  [NUM_TID-1:0][NUM_PORTS-1:0];
    logic [DATA_WIDTH-1:0] exp_const[NUM_CONST-1:0];
    logic                  exp_pred [NUM_TID-1:0][NUM_PRED-1:0];

    initial begin
        clk_i = 1'b0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            sampled_rd_data_r <= '0;
            sampled_pred_r    <= '0;
        end else if (rf_rd_valid_o) begin
            sampled_rd_data_r <= rd_data_o;
            sampled_pred_r    <= pred_o;
        end
    end

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
        , .rd_en_i        (rd_en_i)
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

    task automatic idle_inputs;
        begin
            rd_tid_valid_i   = 1'b0;
            rd_en_i          = 1'b0;
            rd_tid_i         = '0;
            rd_bitmap_i      = '0;
            wr_bitmap_i      = '0;
            cgra_tid_i       = '0;
            cgra_data_i      = '0;
            cgra_wr_bitmap_i = '0;
            cgra_valid_i     = 1'b0;
            ldst_wr_i        = '0;
            ldst_valid_i     = 1'b0;
        end
    endtask

    task automatic init_scoreboard;
        begin
            for (int tid = 0; tid < NUM_TID; tid++) begin
                for (int bank = 0; bank < NUM_PORTS; bank++) begin
                    exp_gpr[tid][bank] = '0;
                end
                for (int pred = 0; pred < NUM_PRED; pred++) begin
                    exp_pred[tid][pred] = 1'b0;
                end
            end

            for (int c = 0; c < NUM_CONST; c++) begin
                exp_const[c] = '0;
            end
        end
    endtask

    function automatic cache_wr_cmd make_ldst_cmd(
          input logic [TID_WIDTH-1:0]  tid
        , input logic [DATA_WIDTH-1:0] data
        , input logic [TOTAL_REGS-1:0] bitmap
    );
        cache_wr_cmd cmd;
        cmd          = '0;
        cmd.tid      = tid;
        cmd.data     = data;
        cmd.wr_bitmap = bitmap;
        return cmd;
    endfunction

    task automatic scoreboard_apply_cgra(
          input logic [TID_WIDTH-1:0]       tid
        , input logic [TOTAL_REGS-1:0]      bitmap
        , input logic [CGRA_DATA_WIDTH-1:0] data
    );
        begin
            for (int bank = 0; bank < NUM_PORTS; bank++) begin
                if (bitmap[bank]) begin
                    exp_gpr[tid][bank] = data[bank*DATA_WIDTH +: DATA_WIDTH];
                end
            end

            for (int c = 0; c < NUM_CONST; c++) begin
                if (bitmap[NUM_PORTS + c]) begin
                    exp_const[c] = data[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH];
                end
            end

            for (int p = 0; p < NUM_PRED; p++) begin
                if (bitmap[NUM_PORTS + NUM_CONST + p]) begin
                    exp_pred[tid][p] = data[(NUM_PORTS + 1 + p) * DATA_WIDTH];
                end
            end
        end
    endtask

    task automatic scoreboard_apply_ldst(input cache_wr_cmd cmd);
        begin
            for (int bank = 0; bank < NUM_PORTS; bank++) begin
                if (cmd.wr_bitmap[bank]) begin
                    exp_gpr[cmd.tid][bank] = cmd.data;
                end
            end

            for (int c = 0; c < NUM_CONST; c++) begin
                if (cmd.wr_bitmap[NUM_PORTS + c]) begin
                    exp_const[c] = cmd.data;
                end
            end

            for (int p = 0; p < NUM_PRED; p++) begin
                if (cmd.wr_bitmap[NUM_PORTS + NUM_CONST + p]) begin
                    exp_pred[cmd.tid][p] = cmd.data[0];
                end
            end
        end
    endtask

    task automatic do_cgra_write(
          input logic [TID_WIDTH-1:0]       tid
        , input logic [TOTAL_REGS-1:0]      bitmap
        , input logic [CGRA_DATA_WIDTH-1:0] data
    );
        begin
            cgra_tid_i       = tid;
            cgra_data_i      = data;
            cgra_wr_bitmap_i = bitmap;
            cgra_valid_i     = 1'b1;
            scoreboard_apply_cgra(tid, bitmap, data);

            repeat (WRITE_HOLD_CYCLES) @(posedge clk_i);

            cgra_valid_i     = 1'b0;
            cgra_wr_bitmap_i = '0;
            cgra_data_i      = '0;
        end
    endtask

    task automatic do_ldst_write(
          input cache_wr_cmd cmd
        , input bit wait_for_ready
    );
        begin
            if (wait_for_ready) begin
                while (ldst_ready_o !== 1'b1) @(posedge clk_i);
            end

            ldst_wr_i    = cmd;
            ldst_valid_i = 1'b1;
            scoreboard_apply_ldst(cmd);

            repeat (WRITE_HOLD_CYCLES) @(posedge clk_i);

            ldst_valid_i = 1'b0;
            ldst_wr_i    = '0;
        end
    endtask

    task automatic check_tid_state(
          input logic [TID_WIDTH-1:0]  tid
        , input logic [TOTAL_REGS-1:0] passthrough_bitmap
    );
        begin
            rd_tid_i       = tid;
            rd_bitmap_i    = '1;
            wr_bitmap_i    = passthrough_bitmap;
            rd_en_i        = 1'b1;
            rd_tid_valid_i = 1'b1;

            @(posedge clk_i);
            @(posedge clk_i);

            if (rf_rd_valid_o !== 1'b1) begin
                $fatal(1, "[%0t] rf_rd_valid_o did not assert for tid %0d", $time, tid);
            end
            if (tid_o !== tid) begin
                $fatal(1, "[%0t] tid_o mismatch. expected=%0d got=%0d", $time, tid, tid_o);
            end
            if (wr_bitmap_o !== passthrough_bitmap) begin
                $fatal(1, "[%0t] wr_bitmap_o mismatch. expected=0x%0h got=0x%0h",
                       $time, passthrough_bitmap, wr_bitmap_o);
            end

            rd_tid_valid_i = 1'b0;
            rd_en_i        = 1'b0;
            rd_bitmap_i    = '0;
            wr_bitmap_i    = '0;

            for (int bank = 0; bank < NUM_PORTS; bank++) begin
                if (sampled_rd_data_r[bank*DATA_WIDTH +: DATA_WIDTH] !== exp_gpr[tid][bank]) begin
                    $fatal(1, "[%0t] GPR mismatch. tid=%0d bank=%0d expected=0x%0h got=0x%0h",
                           $time, tid, bank, exp_gpr[tid][bank],
                           sampled_rd_data_r[bank*DATA_WIDTH +: DATA_WIDTH]);
                end
            end

            for (int c = 0; c < NUM_CONST; c++) begin
                if (sampled_rd_data_r[(NUM_PORTS + c)*DATA_WIDTH +: DATA_WIDTH] !== exp_const[c]) begin
                    $fatal(1, "[%0t] CONST mismatch. const=%0d expected=0x%0h got=0x%0h",
                           $time, c, exp_const[c],
                           sampled_rd_data_r[(NUM_PORTS + c)*DATA_WIDTH +: DATA_WIDTH]);
                end
            end

            for (int p = 0; p < NUM_PRED; p++) begin
                if (sampled_pred_r[p] !== exp_pred[tid][p]) begin
                    $fatal(1, "[%0t] PRED mismatch. tid=%0d pred=%0d expected=%0b got=%0b",
                           $time, tid, p, exp_pred[tid][p], sampled_pred_r[p]);
                end
            end
        end
    endtask

    task automatic check_all_tids_zero;
        begin
            for (int tid = 0; tid < NUM_TID; tid++) begin
                check_tid_state(TID_WIDTH'(tid), TOTAL_REGS'(1 << (tid % TOTAL_REGS)));
            end
        end
    endtask

    task automatic clear_all_registers;
        logic [CGRA_DATA_WIDTH-1:0] clear_data;
        begin
            clear_data = '0;

            for (int tid = 0; tid < NUM_TID; tid++) begin
                do_cgra_write(TID_WIDTH'(tid), '1, clear_data);
            end

            repeat (2 + WRITE_TO_READ_LATENCY) @(posedge clk_i);
        end
    endtask

    task automatic reset_dut;
        begin
            idle_inputs();
            init_scoreboard();
            reset_i = 1'b1;
            repeat (5) @(posedge clk_i);
            reset_i = 1'b0;
            @(posedge clk_i);

            clear_all_registers();
            check_all_tids_zero();
        end
    endtask

    initial begin
        logic [CGRA_DATA_WIDTH-1:0] cgra_case_data;
        logic [TOTAL_REGS-1:0] case_bitmap;
        logic [TOTAL_REGS-1:0] passthrough_bitmap;
        int queued_writes;
        cache_wr_cmd ldst_cmd;

        $display("=== dice_rf_ctrl directed test start ===");

        reset_i = 1'b0;
        reset_dut();

        $display("=== Case 1: Writing from CGRA ===");
        cgra_case_data = '0;
        for (int bank = 0; bank < NUM_PORTS; bank++) begin
            cgra_case_data[bank*DATA_WIDTH +: DATA_WIDTH] = DATA_WIDTH'(8'h10 + bank);
        end
        case_bitmap = '0;
        for (int bank = 0; bank < NUM_PORTS; bank++) begin
            case_bitmap[bank] = 1'b1;
        end

        do_cgra_write(
            TID_WIDTH'(3),
            case_bitmap,
            cgra_case_data
        );
        repeat (WRITE_TO_READ_LATENCY) @(posedge clk_i);
        passthrough_bitmap = '0;
        passthrough_bitmap[0] = 1'b1;
        passthrough_bitmap[2] = 1'b1;
        passthrough_bitmap[4] = 1'b1;
        passthrough_bitmap[6] = 1'b1;
        check_tid_state(TID_WIDTH'(3), passthrough_bitmap);

        passthrough_bitmap = '0;
        passthrough_bitmap[1] = 1'b1;
        passthrough_bitmap[3] = 1'b1;
        passthrough_bitmap[5] = 1'b1;
        passthrough_bitmap[7] = 1'b1;
        check_tid_state(TID_WIDTH'(2), passthrough_bitmap);

        $display("=== Case 2: Writing from LDST unit ===");
        case_bitmap = '0;
        case_bitmap[1] = 1'b1;
        case_bitmap[6] = 1'b1;
        ldst_cmd = make_ldst_cmd(
            TID_WIDTH'(5),
            DATA_WIDTH'(8'h5A),
            case_bitmap
        );
        do_ldst_write(ldst_cmd, 1'b1);

        case_bitmap = '0;
        case_bitmap[3] = 1'b1;
        case_bitmap[7] = 1'b1;
        ldst_cmd = make_ldst_cmd(
            TID_WIDTH'(5),
            DATA_WIDTH'(8'hA7),
            case_bitmap
        );
        do_ldst_write(ldst_cmd, 1'b1);

        repeat (WRITE_TO_READ_LATENCY) @(posedge clk_i);
        passthrough_bitmap = '0;
        passthrough_bitmap[0] = 1'b1;
        passthrough_bitmap[1] = 1'b1;
        passthrough_bitmap[4] = 1'b1;
        passthrough_bitmap[5] = 1'b1;
        check_tid_state(TID_WIDTH'(5), passthrough_bitmap);

        passthrough_bitmap = '0;
        passthrough_bitmap[4] = 1'b1;
        passthrough_bitmap[5] = 1'b1;
        passthrough_bitmap[6] = 1'b1;
        passthrough_bitmap[7] = 1'b1;
        check_tid_state(TID_WIDTH'(3), passthrough_bitmap);

        $display("=== Case 3: Filling the LDST buffer ===");
        cgra_tid_i       = '0;
        cgra_data_i      = '0;
        cgra_wr_bitmap_i = '0;
        cgra_valid_i     = 1'b1;
        queued_writes    = 0;

        if (ldst_ready_o !== 1'b1) begin
            $fatal(1, "[%0t] LDST was not ready at the start of the buffer fill case", $time);
        end

        for (int tid = 0; tid < NUM_TID; tid++) begin
            if (ldst_ready_o !== 1'b1) begin
                break;
            end

            ldst_cmd = make_ldst_cmd(
                TID_WIDTH'(tid),
                DATA_WIDTH'(8'h80 + tid),
                TOTAL_REGS'(1)
            );
            do_ldst_write(ldst_cmd, 1'b0);
            queued_writes++;
        end

        if (ldst_ready_o !== 1'b0) begin
            $fatal(1, "[%0t] LDST buffer did not report full after %0d accepted writes",
                   $time, queued_writes);
        end

        cgra_valid_i = 1'b0;
        repeat (queued_writes + 3) @(posedge clk_i);

        if (ldst_ready_o !== 1'b1) begin
            $fatal(1, "[%0t] LDST ready did not recover after draining the buffer", $time);
        end

        $display("=== dice_rf_ctrl directed test PASS ===");
        #100;
        $finish;
    end

endmodule

// verilator lint_on
