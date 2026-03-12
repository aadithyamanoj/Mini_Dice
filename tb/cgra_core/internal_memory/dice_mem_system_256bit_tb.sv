
`include "axi/typedef.svh"
`include "dice_pkg.sv"

module dice_mem_system_256bit_tb;

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
    // AXI-Lite Interface Instances (256-bit)
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) cgra_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) fpga_axi ();

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    dice_mem_system_256bit dut (
        .clk_i      ( clk_i    ),
        .rst_ni     ( rst_ni   ),
        .cgra_axi_i ( cgra_axi ),
        .fpga_axi_i ( fpga_axi )
    );

    // -------------------------------------------------------------------------
    // Cycle counter + memory-wrapper monitor
    // -------------------------------------------------------------------------
    int cyc;
    always @(posedge clk_i) cyc <= cyc + 1;

    always @(posedge clk_i) begin
        if (dut.i_mem_wrap.mem_v)
            $display("[CYC %0d T=%0t] MEM_ACCESS: v=%b w=%b addr=0x%h wdata=0x%h wmask=0x%h",
                     cyc, $time,
                     dut.i_mem_wrap.mem_v, dut.i_mem_wrap.mem_w,
                     dut.i_mem_wrap.mem_addr,
                     dut.i_mem_wrap.axi_i.w_data,
                     dut.i_mem_wrap.mem_w_mask_bit);
        if (dut.i_mem_wrap.axi_i.r_valid)
            $display("[CYC %0d T=%0t] MEM_RVALID: r_valid=%b r_data=0x%h (at wrapper output)",
                     cyc, $time,
                     dut.i_mem_wrap.axi_i.r_valid,
                     dut.i_mem_wrap.axi_i.r_data);
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // Each address is a 32-byte aligned word address (word N -> byte addr N*32)
    // -------------------------------------------------------------------------
    task automatic axi_write(
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
        $display("[CYC %0d T=%0t] %s WRITE_START: addr=0x%h data=0x%h strb=0x%h | aw_ready=%b w_ready=%b",
                 cyc, $time, name, addr, data, strb, v_axi.aw_ready, v_axi.w_ready);

        wait(v_axi.aw_ready && v_axi.w_ready);
        $display("[CYC %0d T=%0t] %s WRITE_HANDSHAKE: AW+W accepted by crossbar",
                 cyc, $time, name);
        @(posedge clk_i);
        v_axi.aw_valid <= 1'b0;
        v_axi.w_valid  <= 1'b0;

        wait(v_axi.b_valid);
        $display("[CYC %0d T=%0t] %s WRITE_RESP: b_valid seen, b_resp=%b",
                 cyc, $time, name, v_axi.b_resp);
        @(posedge clk_i);
        v_axi.b_ready <= 1'b0;

        $display("[TIME %0t] %s WROTE: 0x%h to 0x%h (Strobe: 0x%h)", $time, name, data, addr, strb);
    endtask

    task automatic axi_read(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) v_axi,
        input  logic [31:0]  addr,
        output logic [255:0] data,
        input  string        name
    );
        @(posedge clk_i);
        v_axi.ar_addr  <= addr;
        v_axi.ar_valid <= 1'b1;
        v_axi.r_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s READ_START: addr=0x%h | ar_ready=%b",
                 cyc, $time, name, addr, v_axi.ar_ready);

        wait(v_axi.ar_ready);
        $display("[CYC %0d T=%0t] %s READ_HANDSHAKE: AR accepted by crossbar",
                 cyc, $time, name);
        @(posedge clk_i);
        v_axi.ar_valid <= 1'b0;

        wait(v_axi.r_valid);
        @(posedge clk_i);
        $display("[CYC %0d T=%0t] %s READ_RVALID: r_valid seen! r_data=0x%h",
                 cyc, $time, name, v_axi.r_data);
        data = v_axi.r_data;
        @(posedge clk_i);
        v_axi.r_ready <= 1'b0;

        $display("[TIME %0t] %s READ: 0x%h from 0x%h", $time, name, data, addr);
    endtask

    task automatic check_val(input logic [255:0] actual, input logic [255:0] expected, input string msg);
        if (actual !== expected) begin
            $error("[FAIL] %s - Expected: 0x%h, Got: 0x%h", msg, expected, actual);
            $stop;
        end else begin
            $display("[PASS] %s", msg);
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // Word N is at byte address N*32 (0x20 per word)
    // -------------------------------------------------------------------------
    logic [255:0] temp_data;

    // Full 32-byte strobe (all bytes enabled)
    localparam logic [31:0] STRB_ALL  = 32'hFFFF_FFFF;
    // Zero strobe (no bytes enabled)
    localparam logic [31:0] STRB_NONE = 32'h0000_0000;
    // Lower half only (bytes 0-15)
    localparam logic [31:0] STRB_LO   = 32'h0000_FFFF;
    // Upper half only (bytes 16-31)
    localparam logic [31:0] STRB_HI   = 32'hFFFF_0000;

    initial begin
        // Initialize signals
        cgra_axi.aw_valid = 0; cgra_axi.w_valid = 0; cgra_axi.ar_valid = 0;
        cgra_axi.b_ready  = 0; cgra_axi.r_ready = 0;
        fpga_axi.aw_valid = 0; fpga_axi.w_valid = 0; fpga_axi.ar_valid = 0;
        fpga_axi.b_ready  = 0; fpga_axi.r_ready = 0;

        // Reset Sequence
        rst_ni = 0;
        #100;
        rst_ni = 1;
        #40;

        // -----------------------------------------------------------------
        $display("\n--- TEST 1: Basic Sequential Access (FPGA -> CGRA) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0020, 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0102_0304_0506_0708_090A_0B0C_0D0E_0F10, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_0020, temp_data, "CGRA");
        check_val(temp_data, 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0102_0304_0506_0708_090A_0B0C_0D0E_0F10, "Test 1: Basic Write/Read mismatch");

        // -----------------------------------------------------------------
        $display("\n--- TEST 2: Reverse Sequential Access (CGRA -> FPGA) ---");
        // -----------------------------------------------------------------
        axi_write(cgra_axi, 32'h0000_0040, 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999, STRB_ALL, "CGRA");
        axi_read (fpga_axi, 32'h0000_0040, temp_data, "FPGA");
        check_val(temp_data, 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999, "Test 2: Reverse Write/Read mismatch");

        // -----------------------------------------------------------------
        $display("\n--- TEST 3: Byte Strobe / Masking Test (strb=0 must not overwrite) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0060, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, STRB_ALL,  "FPGA");
        axi_write(fpga_axi, 32'h0000_0060, 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, STRB_NONE, "FPGA");
        axi_read (fpga_axi, 32'h0000_0060, temp_data, "FPGA");
        check_val(temp_data, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, "Test 3: Strobe=0 overwrote data illegally");

        // -----------------------------------------------------------------
        $display("\n--- TEST 4: Partial Strobe - Lower Half Only ---");
        // -----------------------------------------------------------------
        // Write all zeros first, then write lower 16 bytes only
        axi_write(fpga_axi, 32'h0000_0080, 256'h0, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_0080, {128'h0, 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111}, STRB_LO, "FPGA");
        axi_read (cgra_axi, 32'h0000_0080, temp_data, "CGRA");
        // Upper 16 bytes remain 0, lower 16 bytes take the new value
        check_val(temp_data, {128'h0, 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111}, "Test 4: Lower-half strobe");

        // -----------------------------------------------------------------
        $display("\n--- TEST 5: Boundary Conditions (Word 0 and Word 31) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0000, 256'hC1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_0000, temp_data, "CGRA");
        check_val(temp_data, 256'hC1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1_C1C1, "Test 5: Word 0 read failed");

        axi_write(fpga_axi, 32'h0000_03E0, 256'hC2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_03E0, temp_data, "CGRA");
        check_val(temp_data, 256'hC2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2_C2C2, "Test 5: Word 31 (0x3E0) read failed");

        // -----------------------------------------------------------------
        $display("\n--- TEST 6: Back-to-Back Writes (Same Master) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_00A0, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_00C0, 256'h2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_00E0, 256'h3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333, STRB_ALL, "FPGA");
        axi_read (fpga_axi, 32'h0000_00A0, temp_data, "FPGA");
        check_val(temp_data, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, "Test 6: Back-to-back write word 5");
        axi_read (fpga_axi, 32'h0000_00C0, temp_data, "FPGA");
        check_val(temp_data, 256'h2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222, "Test 6: Back-to-back write word 6");
        axi_read (fpga_axi, 32'h0000_00E0, temp_data, "FPGA");
        check_val(temp_data, 256'h3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333, "Test 6: Back-to-back write word 7");

        // -----------------------------------------------------------------
        $display("\n--- TEST 7: Back-to-Back Reads (Same Master) ---");
        // -----------------------------------------------------------------
        axi_write(cgra_axi, 32'h0000_0100, 256'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, STRB_ALL, "CGRA");
        axi_write(cgra_axi, 32'h0000_0120, 256'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, STRB_ALL, "CGRA");
        axi_write(cgra_axi, 32'h0000_0140, 256'hCCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC, STRB_ALL, "CGRA");
        axi_read (cgra_axi, 32'h0000_0100, temp_data, "CGRA");
        check_val(temp_data, 256'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, "Test 7: Back-to-back read word 8");
        axi_read (cgra_axi, 32'h0000_0120, temp_data, "CGRA");
        check_val(temp_data, 256'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, "Test 7: Back-to-back read word 9");
        axi_read (cgra_axi, 32'h0000_0140, temp_data, "CGRA");
        check_val(temp_data, 256'hCCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC, "Test 7: Back-to-back read word 10");

        // -----------------------------------------------------------------
        $display("\n--- TEST 8: Walking Ones Pattern (across words) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0160, 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_0180, 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0002, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_01A0, 256'h8000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_0160, temp_data, "CGRA");
        check_val(temp_data, 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0001, "Test 8: Walking ones bit 0");
        axi_read (cgra_axi, 32'h0000_0180, temp_data, "CGRA");
        check_val(temp_data, 256'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0002, "Test 8: Walking ones bit 1");
        axi_read (cgra_axi, 32'h0000_01A0, temp_data, "CGRA");
        check_val(temp_data, 256'h8000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000, "Test 8: Walking ones MSB");

        // -----------------------------------------------------------------
        $display("\n--- TEST 9: Alternating Master Access (Interleaved) ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_01C0, 256'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0, STRB_ALL, "FPGA");
        axi_write(cgra_axi, 32'h0000_01E0, 256'h0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F, STRB_ALL, "CGRA");
        axi_write(fpga_axi, 32'h0000_0200, 256'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_01C0, temp_data, "CGRA");
        check_val(temp_data, 256'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0, "Test 9: FPGA write, CGRA read");
        axi_read (fpga_axi, 32'h0000_01E0, temp_data, "FPGA");
        check_val(temp_data, 256'h0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F, "Test 9: CGRA write, FPGA read");
        axi_read (cgra_axi, 32'h0000_0200, temp_data, "CGRA");
        check_val(temp_data, 256'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, "Test 9: FPGA write, CGRA read (third)");

        // -----------------------------------------------------------------
        $display("\n--- TEST 10: Double Write with Strobe Pattern ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0220, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, STRB_ALL,  "FPGA");
        axi_read (fpga_axi, 32'h0000_0220, temp_data, "FPGA");
        check_val(temp_data, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, "Test 10: Initial write");
        axi_write(fpga_axi, 32'h0000_0220, 256'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, STRB_NONE, "FPGA");
        axi_read (fpga_axi, 32'h0000_0220, temp_data, "FPGA");
        check_val(temp_data, 256'h5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A_5A5A, "Test 10: Strobe=0 should preserve data");

        // -----------------------------------------------------------------
        $display("\n--- TEST 11: Cross-Master Sequential Reads ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0240, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, STRB_ALL, "FPGA");
        axi_write(fpga_axi, 32'h0000_0260, 256'h2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222, STRB_ALL, "FPGA");
        axi_read (cgra_axi, 32'h0000_0240, temp_data, "CGRA");
        check_val(temp_data, 256'h1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111, "Test 11: Cross-master read word 18");
        axi_read (cgra_axi, 32'h0000_0260, temp_data, "CGRA");
        check_val(temp_data, 256'h2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222_2222, "Test 11: Cross-master read word 19");
        axi_write(cgra_axi, 32'h0000_0240, 256'h3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333, STRB_ALL, "CGRA");
        axi_read (fpga_axi, 32'h0000_0240, temp_data, "FPGA");
        check_val(temp_data, 256'h3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333_3333, "Test 11: CGRA write, FPGA read");

        // -----------------------------------------------------------------
        $display("\n--- TEST 12: Full Address Range Sampling ---");
        // -----------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0020, 256'h0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101, STRB_ALL, "FPGA"); // word 1
        axi_write(fpga_axi, 32'h0000_01E0, 256'h0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F, STRB_ALL, "FPGA"); // word 15
        axi_write(fpga_axi, 32'h0000_0200, 256'h1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010, STRB_ALL, "FPGA"); // word 16
        axi_write(fpga_axi, 32'h0000_03C0, 256'hFEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE, STRB_ALL, "FPGA"); // word 30
        axi_read (cgra_axi, 32'h0000_0020, temp_data, "CGRA");
        check_val(temp_data, 256'h0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101_0101, "Test 12: Word 1");
        axi_read (cgra_axi, 32'h0000_01E0, temp_data, "CGRA");
        check_val(temp_data, 256'h0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F_0F0F, "Test 12: Word 15");
        axi_read (cgra_axi, 32'h0000_0200, temp_data, "CGRA");
        check_val(temp_data, 256'h1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010_1010, "Test 12: Word 16");
        axi_read (cgra_axi, 32'h0000_03C0, temp_data, "CGRA");
        check_val(temp_data, 256'hFEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE_FEFE, "Test 12: Word 30");

        $display("\n========================================");
        $display("   ALL TESTS PASSED!                   ");
        $display("========================================");
        #100;
        $finish;
    end

endmodule
