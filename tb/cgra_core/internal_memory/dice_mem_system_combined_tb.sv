
`include "axi/typedef.svh"
`include "dice_pkg.sv"

/**
 * Testbench for dice_mem_system_combined
 * Tests both 8-bit (256B) and 256-bit (1KB) memory subsystems
 */
module dice_mem_system_combined_tb;

    // -------------------------------------------------------------------------
    // Clock and Reset Generation
    // -------------------------------------------------------------------------
    bit clk_i;
    logic rst_ni = 0;
    parameter CLK_PERIOD = 20000;

    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // -------------------------------------------------------------------------
    // AXI-Lite Interface Instances (8-bit)
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) cgra_axi_8bit ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) fpga_axi_8bit ();

    // -------------------------------------------------------------------------
    // AXI-Lite Interface Instances (256-bit)
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) cgra_axi_256bit ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) fpga_axi_256bit ();

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    dice_mem_system_combined dut (
        .clk_i               ( clk_i              ),
        .rst_ni              ( rst_ni             ),
        .cgra_axi_8bit_i     ( cgra_axi_8bit     ),
        .cgra_axi_256bit_i   ( cgra_axi_256bit   ),
        .fpga_axi_8bit_i     ( fpga_axi_8bit     ),
        .fpga_axi_256bit_i   ( fpga_axi_256bit   )
    );

    // -------------------------------------------------------------------------
    // Cycle counter
    // -------------------------------------------------------------------------
    int cyc;
    always @(posedge clk_i) cyc <= cyc + 1;

    // =========================================================================
    // 8-BIT HELPER TASKS
    // =========================================================================
    task automatic axi_write_8bit(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) v_axi,
        input logic [31:0] addr,
        input logic [7:0]  data,
        input logic        strb,
        input string       name
    );
        @(posedge clk_i);
        v_axi.aw_addr  <= addr;
        v_axi.aw_valid <= 1'b1;
        v_axi.w_data   <= data;
        v_axi.w_strb   <= strb;
        v_axi.w_valid  <= 1'b1;
        v_axi.b_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s (8BIT) WRITE_START: addr=0x%h data=0x%h strb=%b",
                 cyc, $time, name, addr, data, strb);

        wait(v_axi.aw_ready && v_axi.w_ready);
        @(posedge clk_i);
        v_axi.aw_valid <= 1'b0;
        v_axi.w_valid  <= 1'b0;

        wait(v_axi.b_valid);
        @(posedge clk_i);
        v_axi.b_ready  <= 1'b0;
        $display("[TIME %0t] %s (8BIT) WROTE: 0x%h to 0x%h", $time, name, data, addr);
    endtask

    task automatic axi_read_8bit(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) v_axi,
        input  logic [31:0] addr,
        output logic [7:0]  data,
        input  string       name
    );
        @(posedge clk_i);
        v_axi.ar_addr  <= addr;
        v_axi.ar_valid <= 1'b1;
        v_axi.r_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s (8BIT) READ_START: addr=0x%h", cyc, $time, name, addr);

        wait(v_axi.ar_ready);
        @(posedge clk_i);
        v_axi.ar_valid <= 1'b0;

        wait(v_axi.r_valid);
        @(posedge clk_i);
        data = v_axi.r_data;
        @(posedge clk_i);
        v_axi.r_ready  <= 1'b0;
        $display("[TIME %0t] %s (8BIT) READ: 0x%h from 0x%h", $time, name, data, addr);
    endtask

    task automatic check_val_8bit(input logic [7:0] actual, input logic [7:0] expected, input string msg);
        if (actual !== expected) begin
            $error("[FAIL] %s - Expected: 0x%h, Got: 0x%h", msg, expected, actual);
            $stop;
        end else begin
            $display("[PASS] %s", msg);
        end
    endtask

    // =========================================================================
    // 256-BIT HELPER TASKS
    // =========================================================================
    task automatic axi_write_256bit(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) v_axi,
        input logic [31:0]  addr,
        input logic [255:0] data,
        input logic [31:0]  strb,
        input string        name
    );
        @(posedge clk_i);
        v_axi.aw_addr  <= addr;
        v_axi.aw_valid <= 1'b1;
        v_axi.w_data   <= data;
        v_axi.w_strb   <= strb;
        v_axi.w_valid  <= 1'b1;
        v_axi.b_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s (256BIT) WRITE_START: addr=0x%h data=0x%h strb=0x%h",
                 cyc, $time, name, addr, data, strb);

        wait(v_axi.aw_ready && v_axi.w_ready);
        @(posedge clk_i);
        v_axi.aw_valid <= 1'b0;
        v_axi.w_valid  <= 1'b0;

        wait(v_axi.b_valid);
        @(posedge clk_i);
        v_axi.b_ready <= 1'b0;
        $display("[TIME %0t] %s (256BIT) WROTE: 0x%h to 0x%h", $time, name, data, addr);
    endtask

    task automatic axi_read_256bit(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) v_axi,
        input  logic [31:0]  addr,
        output logic [255:0] data,
        input  string        name
    );
        @(posedge clk_i);
        v_axi.ar_addr  <= addr;
        v_axi.ar_valid <= 1'b1;
        v_axi.r_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s (256BIT) READ_START: addr=0x%h", cyc, $time, name, addr);

        wait(v_axi.ar_ready);
        @(posedge clk_i);
        v_axi.ar_valid <= 1'b0;

        wait(v_axi.r_valid);
        @(posedge clk_i);
        data = v_axi.r_data;
        @(posedge clk_i);
        v_axi.r_ready <= 1'b0;
        $display("[TIME %0t] %s (256BIT) READ: 0x%h from 0x%h", $time, name, data, addr);
    endtask

    task automatic check_val_256bit(input logic [255:0] actual, input logic [255:0] expected, input string msg);
        if (actual !== expected) begin
            $error("[FAIL] %s - Expected: 0x%h, Got: 0x%h", msg, expected, actual);
            $stop;
        end else begin
            $display("[PASS] %s", msg);
        end
    endtask

    // =========================================================================
    // STIMULUS
    // =========================================================================
    logic [7:0]   temp_data_8bit;
    logic [255:0] temp_data_256bit;

    localparam logic [31:0] STRB_ALL_256  = 32'hFFFF_FFFF;
    localparam logic [31:0] STRB_NONE_256 = 32'h0000_0000;

    initial begin
        // Initialize all signals
        cgra_axi_8bit.aw_valid = 0;   cgra_axi_8bit.w_valid = 0;   cgra_axi_8bit.ar_valid = 0;
        cgra_axi_8bit.b_ready = 0;    cgra_axi_8bit.r_ready = 0;
        fpga_axi_8bit.aw_valid = 0;   fpga_axi_8bit.w_valid = 0;   fpga_axi_8bit.ar_valid = 0;
        fpga_axi_8bit.b_ready = 0;    fpga_axi_8bit.r_ready = 0;

        cgra_axi_256bit.aw_valid = 0; cgra_axi_256bit.w_valid = 0; cgra_axi_256bit.ar_valid = 0;
        cgra_axi_256bit.b_ready = 0;  cgra_axi_256bit.r_ready = 0;
        fpga_axi_256bit.aw_valid = 0; fpga_axi_256bit.w_valid = 0; fpga_axi_256bit.ar_valid = 0;
        fpga_axi_256bit.b_ready = 0;  fpga_axi_256bit.r_ready = 0;

        // Reset Sequence
        rst_ni = 0;
        #100;
        rst_ni = 1;
        #40;

        // =====================================================================
        $display("\n========== 8-BIT MEMORY TESTS ==========\n");
        // =====================================================================

        $display("\n--- TEST 1.1: Basic 8-bit Write/Read (FPGA->CGRA) ---");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0010, 8'hAA, 1'b1, "FPGA");
        axi_read_8bit (cgra_axi_8bit, 32'h0000_0010, temp_data_8bit, "CGRA");
        check_val_8bit(temp_data_8bit, 8'hAA, "Test 1.1: Basic Write/Read");

        $display("\n--- TEST 1.2: Basic 8-bit Write/Read (CGRA->FPGA) ---");
        axi_write_8bit(cgra_axi_8bit, 32'h0000_0020, 8'hBB, 1'b1, "CGRA");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0020, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'hBB, "Test 1.2: CGRA write, FPGA read");

        $display("\n--- TEST 1.3: Boundary Conditions (8-bit) ---");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0000, 8'hC1, 1'b1, "FPGA");
        axi_read_8bit (cgra_axi_8bit, 32'h0000_0000, temp_data_8bit, "CGRA");
        check_val_8bit(temp_data_8bit, 8'hC1, "Test 1.3a: Address 0x00");

        axi_write_8bit(fpga_axi_8bit, 32'h0000_00FF, 8'hC2, 1'b1, "FPGA");
        axi_read_8bit (cgra_axi_8bit, 32'h0000_00FF, temp_data_8bit, "CGRA");
        check_val_8bit(temp_data_8bit, 8'hC2, "Test 1.3b: Address 0xFF");

        $display("\n--- TEST 1.4: Back-to-Back 8-bit Writes ---");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0030, 8'h11, 1'b1, "FPGA");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0031, 8'h22, 1'b1, "FPGA");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0032, 8'h33, 1'b1, "FPGA");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0030, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'h11, "Test 1.4a: Back-to-back addr 0x30");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0031, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'h22, "Test 1.4b: Back-to-back addr 0x31");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0032, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'h33, "Test 1.4c: Back-to-back addr 0x32");

        $display("\n--- TEST 1.5: Strobe Masking (8-bit) ---");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0040, 8'h5A, 1'b1, "FPGA");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0040, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'h5A, "Test 1.5a: Initial write");
        axi_write_8bit(fpga_axi_8bit, 32'h0000_0040, 8'hA5, 1'b0, "FPGA");
        axi_read_8bit (fpga_axi_8bit, 32'h0000_0040, temp_data_8bit, "FPGA");
        check_val_8bit(temp_data_8bit, 8'h5A, "Test 1.5b: Strobe=0 preserves data");

        // =====================================================================
        $display("\n========== 256-BIT MEMORY TESTS ==========\n");
        // =====================================================================

        $display("\n--- TEST 2.1: Basic 256-bit Write/Read (FPGA->CGRA) ---");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_0020, 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0102_0304_0506_0708_090A_0B0C_0D0E_0F10, STRB_ALL_256, "FPGA");
        axi_read_256bit (cgra_axi_256bit, 32'h0000_0020, temp_data_256bit, "CGRA");
        check_val_256bit(temp_data_256bit, 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0102_0304_0506_0708_090A_0B0C_0D0E_0F10, "Test 2.1: Basic Write/Read");

        $display("\n--- TEST 2.2: Basic 256-bit Write/Read (CGRA->FPGA) ---");
        axi_write_256bit(cgra_axi_256bit, 32'h0000_0040, 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999, STRB_ALL_256, "CGRA");
        axi_read_256bit (fpga_axi_256bit, 32'h0000_0040, temp_data_256bit, "FPGA");
        check_val_256bit(temp_data_256bit, 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999, "Test 2.2: CGRA write, FPGA read");

        $display("\n--- TEST 2.3: Boundary Conditions (256-bit) ---");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_0000, 256'hC1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1, STRB_ALL_256, "FPGA");
        axi_read_256bit (cgra_axi_256bit, 32'h0000_0000, temp_data_256bit, "CGRA");
        check_val_256bit(temp_data_256bit, 256'hC1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1, "Test 2.3a: Word 0");

        axi_write_256bit(fpga_axi_256bit, 32'h0000_03E0, 256'hC2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2, STRB_ALL_256, "FPGA");
        axi_read_256bit (cgra_axi_256bit, 32'h0000_03E0, temp_data_256bit, "CGRA");
        check_val_256bit(temp_data_256bit, 256'hC2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2, "Test 2.3b: Word 31");

        $display("\n--- TEST 2.4: Back-to-Back 256-bit Writes ---");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_0060, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, STRB_ALL_256, "FPGA");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_0080, 256'h2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222, STRB_ALL_256, "FPGA");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_00A0, 256'h3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333, STRB_ALL_256, "FPGA");
        axi_read_256bit (fpga_axi_256bit, 32'h0000_0060, temp_data_256bit, "FPGA");
        check_val_256bit(temp_data_256bit, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, "Test 2.4a: Back-to-back write");

        $display("\n--- TEST 2.5: Strobe Masking (256-bit) ---");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_00C0, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, STRB_ALL_256, "FPGA");
        axi_read_256bit (fpga_axi_256bit, 32'h0000_00C0, temp_data_256bit, "FPGA");
        check_val_256bit(temp_data_256bit, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, "Test 2.5a: Initial write");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_00C0, 256'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, STRB_NONE_256, "FPGA");
        axi_read_256bit (fpga_axi_256bit, 32'h0000_00C0, temp_data_256bit, "FPGA");
        check_val_256bit(temp_data_256bit, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, "Test 2.5b: Strobe=0 preserves");

        // =====================================================================
        $display("\n========== CONCURRENT ACCESS TESTS (8-BIT + 256-BIT) ==========\n");
        // =====================================================================

        $display("\n--- TEST 3.1: Concurrent 8-bit and 256-bit Writes ---");
        fork
            axi_write_8bit(fpga_axi_8bit, 32'h0000_0050, 8'hEE, 1'b1, "FPGA_8BIT");
            axi_write_256bit(fpga_axi_256bit, 32'h0000_00E0, 256'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0, STRB_ALL_256, "FPGA_256BIT");
        join

        $display("\n--- TEST 3.2: Concurrent Reads from Different Paths ---");
        fork
            axi_read_8bit(cgra_axi_8bit, 32'h0000_0050, temp_data_8bit, "CGRA_8BIT");
            axi_read_256bit(cgra_axi_256bit, 32'h0000_00E0, temp_data_256bit, "CGRA_256BIT");
        join
        check_val_8bit(temp_data_8bit, 8'hEE, "Test 3.2a: 8-bit concurrent read");
        check_val_256bit(temp_data_256bit, 256'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0, "Test 3.2b: 256-bit concurrent read");

        $display("\n--- TEST 3.3: Interleaved Access (CGRA 8-bit, FPGA 256-bit) ---");
        axi_write_8bit(cgra_axi_8bit, 32'h0000_0060, 8'hFF, 1'b1, "CGRA_8BIT");
        axi_write_256bit(fpga_axi_256bit, 32'h0000_0100, 256'h1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010, STRB_ALL_256, "FPGA_256BIT");
        axi_read_8bit(fpga_axi_8bit, 32'h0000_0060, temp_data_8bit, "FPGA_8BIT");
        check_val_8bit(temp_data_8bit, 8'hFF, "Test 3.3a: CGRA write, FPGA 8-bit read");
        axi_read_256bit(cgra_axi_256bit, 32'h0000_0100, temp_data_256bit, "CGRA_256BIT");
        check_val_256bit(temp_data_256bit, 256'h1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010, "Test 3.3b: FPGA write, CGRA 256-bit read");

        // =====================================================================
        $display("\n========================================");
        $display("   ALL TESTS PASSED!                   ");
        $display("========================================");
        #100;
        $finish;
    end

endmodule
