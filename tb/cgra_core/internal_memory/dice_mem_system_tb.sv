
`include "axi/typedef.svh"
`include "dice_pkg.sv"

module dice_mem_system_tb;

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
    // AXI-Lite Interface Instances
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) cgra_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) fpga_axi ();

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    dice_mem_system dut (
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

    // Shows every clock cycle when the memory wrapper is active or has r_valid
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
    // -------------------------------------------------------------------------
    task automatic axi_write(
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
        $display("[CYC %0d T=%0t] %s WRITE_START: addr=0x%h data=0x%h strb=%b | aw_ready=%b w_ready=%b",
                 cyc, $time, name, addr, data, strb, v_axi.aw_ready, v_axi.w_ready);

        // Hold valid until the crossbar accepts (aw_ready && w_ready handshake)
        wait(v_axi.aw_ready && v_axi.w_ready);
        $display("[CYC %0d T=%0t] %s WRITE_HANDSHAKE: AW+W accepted by crossbar",
                 cyc, $time, name);
        @(posedge clk_i);
        v_axi.aw_valid <= 1'b0;
        v_axi.w_valid  <= 1'b0;
        $display("[CYC %0d T=%0t] %s WRITE_DEASSERT: aw_valid=0 | b_valid=%b",
                 cyc, $time, name, v_axi.b_valid);

        // Wait for write response from crossbar (b_valid propagates back with latency)
        wait(v_axi.b_valid);
        $display("[CYC %0d T=%0t] %s WRITE_RESP: b_valid seen, b_resp=%b",
                 cyc, $time, name, v_axi.b_resp);
        @(posedge clk_i);
        v_axi.b_ready  <= 1'b0;

        $display("[TIME %0t] %s WROTE: 0x%h to 0x%h (Strobe: %b)", $time, name, data, addr, strb);
    endtask

    task automatic axi_read(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) v_axi,
        input  logic [31:0] addr,
        output logic [7:0]  data,
        input  string       name
    );
        @(posedge clk_i);
        v_axi.ar_addr  <= addr;
        v_axi.ar_valid <= 1'b1;
        v_axi.r_ready  <= 1'b1;
        $display("[CYC %0d T=%0t] %s READ_START: addr=0x%h | ar_ready=%b",
                 cyc, $time, name, addr, v_axi.ar_ready);

        // Hold valid until the crossbar accepts (ar_ready handshake)
        wait(v_axi.ar_ready);
        $display("[CYC %0d T=%0t] %s READ_HANDSHAKE: AR accepted by crossbar",
                 cyc, $time, name);
        @(posedge clk_i);
        v_axi.ar_valid <= 1'b0;
        $display("[CYC %0d T=%0t] %s READ_DEASSERT: ar_valid=0 | r_valid=%b r_data=0x%h",
                 cyc, $time, name, v_axi.r_valid, v_axi.r_data);

        // Wait for read data — sample at clock edge after r_valid to ensure
        // data is stable (required for sim-syn with SDF back-annotation,
        // where r_valid and r_data may arrive at different times in the cycle)
        wait(v_axi.r_valid);
        @(posedge clk_i);
        $display("[CYC %0d T=%0t] %s READ_RVALID: r_valid seen! r_data=0x%h (TB interface)",
                 cyc, $time, name, v_axi.r_data);
        data = v_axi.r_data;
        @(posedge clk_i);
        v_axi.r_ready  <= 1'b0;

        $display("[TIME %0t] %s READ:  0x%h from 0x%h", $time, name, data, addr);
    endtask

    task automatic check_val(input logic [7:0] actual, input logic [7:0] expected, input string msg);
        if (actual !== expected) begin
            $error("[FAIL] %s - Expected: 0x%h, Got: 0x%h", msg, expected, actual);
            $stop;
        end else begin
            $display("[PASS] %s", msg);
        end
    endtask

    task automatic axi_write_burst(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) v_axi,
        input logic [31:0] start_addr,
        input logic [7:0]  data_q[$],
        input string       name
    );
        foreach (data_q[i]) begin
            axi_write(v_axi, start_addr + i, data_q[i], 1'b1, name);
        end
    endtask

    task automatic axi_read_burst(
        virtual AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) v_axi,
        input logic [31:0] start_addr,
        input int          count,
        output logic [7:0] data_q[$],
        input string       name
    );
        logic [7:0] temp;
        data_q.delete();
        repeat (count) begin
            axi_read(v_axi, start_addr + data_q.size(), temp, name);
            data_q.push_back(temp);
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic [7:0] temp_data;
    logic [7:0] burst_data[$];
    logic [7:0] readback[$];

    initial begin
        // Initialize signals
        cgra_axi.aw_valid = 0; cgra_axi.w_valid = 0; cgra_axi.ar_valid = 0; cgra_axi.b_ready = 0; cgra_axi.r_ready = 0;
        fpga_axi.aw_valid = 0; fpga_axi.w_valid = 0; fpga_axi.ar_valid = 0; fpga_axi.b_ready = 0; fpga_axi.r_ready = 0;

        // Reset Sequence
        rst_ni = 0;
        #100; // Adjusted for slower clock
        rst_ni = 1;
        #40;

        // ---------------------------------------------------------------------
        $display("\n--- TEST 1: Basic Sequential Access (FPGA -> CGRA) ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0010, 8'hAA, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_0010, temp_data, "CGRA");
        check_val(temp_data, 8'hAA, "Test 1: Basic Write/Read mismatch");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 2: Reverse Sequential Access (CGRA -> FPGA) ---");
        // ---------------------------------------------------------------------
        axi_write(cgra_axi, 32'h0000_0020, 8'hBB, 1'b1, "CGRA");
        axi_read (fpga_axi, 32'h0000_0020, temp_data, "FPGA");
        check_val(temp_data, 8'hBB, "Test 2: Reverse Write/Read mismatch");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 3: Byte Strobe / Masking Test ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0030, 8'h11, 1'b1, "FPGA"); // Write valid data
        axi_write(fpga_axi, 32'h0000_0030, 8'hFF, 1'b0, "FPGA"); // Write with strb=0 (should ignore)
        axi_read (fpga_axi, 32'h0000_0030, temp_data, "FPGA");
        check_val(temp_data, 8'h11, "Test 3: Strobe=0 overwrote data illegally");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 4: Boundary Conditions (0x00 and 0xFF) ---");
        // ---------------------------------------------------------------------
        // Testing the absolute edges of the 256-word memory space sequentially
        axi_write(fpga_axi, 32'h0000_0000, 8'hC1, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_0000, temp_data, "CGRA");
        check_val(temp_data, 8'hC1, "Test 4: Address 0x00 read failed");
        
        axi_write(fpga_axi, 32'h0000_00FF, 8'hC2, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_00FF, temp_data, "CGRA");
        check_val(temp_data, 8'hC2, "Test 4: Address 0xFF read failed");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 5: Back-to-Back Writes (Same Master) ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0040, 8'h11, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0041, 8'h22, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0042, 8'h33, 1'b1, "FPGA");
        axi_read (fpga_axi, 32'h0000_0040, temp_data, "FPGA");
        check_val(temp_data, 8'h11, "Test 5: Back-to-back write addr 0x40");
        axi_read (fpga_axi, 32'h0000_0041, temp_data, "FPGA");
        check_val(temp_data, 8'h22, "Test 5: Back-to-back write addr 0x41");
        axi_read (fpga_axi, 32'h0000_0042, temp_data, "FPGA");
        check_val(temp_data, 8'h33, "Test 5: Back-to-back write addr 0x42");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 6: Back-to-Back Reads (Same Master) ---");
        // ---------------------------------------------------------------------
        axi_write(cgra_axi, 32'h0000_0050, 8'hAA, 1'b1, "CGRA");
        axi_write(cgra_axi, 32'h0000_0051, 8'hBB, 1'b1, "CGRA");
        axi_write(cgra_axi, 32'h0000_0052, 8'hCC, 1'b1, "CGRA");
        axi_read (cgra_axi, 32'h0000_0050, temp_data, "CGRA");
        check_val(temp_data, 8'hAA, "Test 6: Back-to-back read addr 0x50");
        axi_read (cgra_axi, 32'h0000_0051, temp_data, "CGRA");
        check_val(temp_data, 8'hBB, "Test 6: Back-to-back read addr 0x51");
        axi_read (cgra_axi, 32'h0000_0052, temp_data, "CGRA");
        check_val(temp_data, 8'hCC, "Test 6: Back-to-back read addr 0x52");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 7: Walking Ones Pattern ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0060, 8'h01, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0061, 8'h02, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0062, 8'h04, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0063, 8'h08, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0064, 8'h10, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0065, 8'h20, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0066, 8'h40, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0067, 8'h80, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_0060, temp_data, "CGRA");
        check_val(temp_data, 8'h01, "Test 7: Walking ones bit 0");
        axi_read (cgra_axi, 32'h0000_0064, temp_data, "CGRA");
        check_val(temp_data, 8'h10, "Test 7: Walking ones bit 4");
        axi_read (cgra_axi, 32'h0000_0067, temp_data, "CGRA");
        check_val(temp_data, 8'h80, "Test 7: Walking ones bit 7");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 8: Alternating Master Access (Interleaved) ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0070, 8'hF0, 1'b1, "FPGA");
        axi_write(cgra_axi, 32'h0000_0071, 8'h0F, 1'b1, "CGRA");
        axi_write(fpga_axi, 32'h0000_0072, 8'hA5, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_0070, temp_data, "CGRA");
        check_val(temp_data, 8'hF0, "Test 8: FPGA write, CGRA read");
        axi_read (fpga_axi, 32'h0000_0071, temp_data, "FPGA");
        check_val(temp_data, 8'h0F, "Test 8: CGRA write, FPGA read");
        axi_read (cgra_axi, 32'h0000_0072, temp_data, "CGRA");
        check_val(temp_data, 8'hA5, "Test 8: FPGA write, CGRA read (third)");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 9: Sequential Memory Fills ---");
        // ---------------------------------------------------------------------
        burst_data.delete();
        burst_data.push_back(8'h10);
        burst_data.push_back(8'h20);
        burst_data.push_back(8'h30);
        burst_data.push_back(8'h40);
        burst_data.push_back(8'h50);
        readback.delete();
        axi_write_burst(fpga_axi, 32'h0000_0080, burst_data, "FPGA");
        axi_read_burst(cgra_axi, 32'h0000_0080, 5, readback, "CGRA");
        for (int i = 0; i < 5; i++) begin
            check_val(readback[i], burst_data[i], $sformatf("Test 9: Burst addr 0x%2h", 32'h80 + i));
        end

        // ---------------------------------------------------------------------
        $display("\n--- TEST 10: Double Write with Strobe Pattern ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0090, 8'h5A, 1'b1, "FPGA"); // Write 0x5A with strobe=1
        axi_read (fpga_axi, 32'h0000_0090, temp_data, "FPGA");
        check_val(temp_data, 8'h5A, "Test 10: Initial write");
        axi_write(fpga_axi, 32'h0000_0090, 8'hA5, 1'b0, "FPGA"); // Try to overwrite with strobe=0
        axi_read (fpga_axi, 32'h0000_0090, temp_data, "FPGA");
        check_val(temp_data, 8'h5A, "Test 10: Strobe=0 should preserve data");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 11: Cross-Master Sequential Reads ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_00A0, 8'h11, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_00A1, 8'h22, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_00A0, temp_data, "CGRA");
        check_val(temp_data, 8'h11, "Test 11: Cross-master read addr 0xA0");
        axi_read (cgra_axi, 32'h0000_00A1, temp_data, "CGRA");
        check_val(temp_data, 8'h22, "Test 11: Cross-master read addr 0xA1");
        axi_write(cgra_axi, 32'h0000_00A0, 8'h33, 1'b1, "CGRA");
        axi_read (fpga_axi, 32'h0000_00A0, temp_data, "FPGA");
        check_val(temp_data, 8'h33, "Test 11: CGRA write, FPGA read");

        // ---------------------------------------------------------------------
        $display("\n--- TEST 12: Full Address Range Sampling ---");
        // ---------------------------------------------------------------------
        axi_write(fpga_axi, 32'h0000_0001, 8'h01, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_007F, 8'h7F, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_0080, 8'h80, 1'b1, "FPGA");
        axi_write(fpga_axi, 32'h0000_00FE, 8'hFE, 1'b1, "FPGA");
        axi_read (cgra_axi, 32'h0000_0001, temp_data, "CGRA");
        check_val(temp_data, 8'h01, "Test 12: Low address");
        axi_read (cgra_axi, 32'h0000_007F, temp_data, "CGRA");
        check_val(temp_data, 8'h7F, "Test 12: Mid-low address");
        axi_read (cgra_axi, 32'h0000_0080, temp_data, "CGRA");
        check_val(temp_data, 8'h80, "Test 12: Mid-high address");
        axi_read (cgra_axi, 32'h0000_00FE, temp_data, "CGRA");
        check_val(temp_data, 8'hFE, "Test 12: High address");

        $display("\n========================================");
        $display("   ALL TESTS PASSED!                   ");
        $display("========================================");
        #100;
        $finish;
    end

endmodule