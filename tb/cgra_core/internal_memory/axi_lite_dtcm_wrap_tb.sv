`include "axi/typedef.svh"
`include "dice_pkg.sv"

module axi_lite_dtcm_wrap_tb;

    logic clk_i  = 0;
    logic rst_ni = 0;

    always #10 clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // AXI-Lite interfaces — 8 CGRA boundary masters + 1 FPGA master + DTCM slave
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_0_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_1_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_2_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_3_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_4_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_5_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_6_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_7_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) fpga_axi   ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) dtcm_axi   ();

    dice_crossbar i_xbar (
        .clk_i        ( clk_i      ),
        .rst_ni       ( rst_ni     ),
        .cgra_0_axi_i ( cgra_0_axi ),
        .cgra_1_axi_i ( cgra_1_axi ),
        .cgra_2_axi_i ( cgra_2_axi ),
        .cgra_3_axi_i ( cgra_3_axi ),
        .cgra_4_axi_i ( cgra_4_axi ),
        .cgra_5_axi_i ( cgra_5_axi ),
        .cgra_6_axi_i ( cgra_6_axi ),
        .cgra_7_axi_i ( cgra_7_axi ),
        .fpga_axi_i   ( fpga_axi   ),
        .dtcm_axi_o   ( dtcm_axi   )
    );

    axi_lite_dtcm_wrap i_mem (
        .clk_i  ( clk_i    ),
        .rst_ni ( rst_ni   ),
        .axi_i  ( dtcm_axi )
    );

    // -------------------------------------------------------------------------
    // Tasks — FPGA writes, CGRA 0 reads
    // -------------------------------------------------------------------------
    task fpga_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_i);
        fpga_axi.aw_valid = 1'b1;
        fpga_axi.aw_addr  = addr;
        fpga_axi.w_valid  = 1'b1;
        fpga_axi.w_data   = data;
        fpga_axi.w_strb   = 4'b1111;
        wait(fpga_axi.aw_ready && fpga_axi.w_ready);
        @(posedge clk_i);
        fpga_axi.aw_valid = 1'b0;
        fpga_axi.w_valid  = 1'b0;
        fpga_axi.b_ready  = 1'b1;
        wait(fpga_axi.b_valid);
        @(posedge clk_i);
        fpga_axi.b_ready = 1'b0;
        $display("[TIME %0t] FPGA Wrote Data: 0x%h to Address: 0x%h", $time, data, addr);
    endtask

    task cgra_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_i);
        cgra_0_axi.ar_valid = 1'b1;
        cgra_0_axi.ar_addr  = addr;
        wait(cgra_0_axi.ar_ready);
        @(posedge clk_i);
        cgra_0_axi.ar_valid = 1'b0;
        cgra_0_axi.r_ready  = 1'b1;
        wait(cgra_0_axi.r_valid);
        data = cgra_0_axi.r_data;
        @(posedge clk_i);
        cgra_0_axi.r_ready = 1'b0;
        $display("[TIME %0t] CGRA Read Data:  0x%h from Address: 0x%h", $time, data, addr);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic [31:0] read_val;

    initial begin
        // Idle all master interfaces
        cgra_0_axi.aw_valid = 0; cgra_0_axi.w_valid = 0; cgra_0_axi.b_ready = 0;
        cgra_0_axi.ar_valid = 0; cgra_0_axi.r_ready = 0;
        cgra_1_axi.aw_valid = 0; cgra_1_axi.w_valid = 0; cgra_1_axi.b_ready = 0;
        cgra_1_axi.ar_valid = 0; cgra_1_axi.r_ready = 0;
        cgra_2_axi.aw_valid = 0; cgra_2_axi.w_valid = 0; cgra_2_axi.b_ready = 0;
        cgra_2_axi.ar_valid = 0; cgra_2_axi.r_ready = 0;
        cgra_3_axi.aw_valid = 0; cgra_3_axi.w_valid = 0; cgra_3_axi.b_ready = 0;
        cgra_3_axi.ar_valid = 0; cgra_3_axi.r_ready = 0;
        cgra_4_axi.aw_valid = 0; cgra_4_axi.w_valid = 0; cgra_4_axi.b_ready = 0;
        cgra_4_axi.ar_valid = 0; cgra_4_axi.r_ready = 0;
        cgra_5_axi.aw_valid = 0; cgra_5_axi.w_valid = 0; cgra_5_axi.b_ready = 0;
        cgra_5_axi.ar_valid = 0; cgra_5_axi.r_ready = 0;
        cgra_6_axi.aw_valid = 0; cgra_6_axi.w_valid = 0; cgra_6_axi.b_ready = 0;
        cgra_6_axi.ar_valid = 0; cgra_6_axi.r_ready = 0;
        cgra_7_axi.aw_valid = 0; cgra_7_axi.w_valid = 0; cgra_7_axi.b_ready = 0;
        cgra_7_axi.ar_valid = 0; cgra_7_axi.r_ready = 0;
        fpga_axi.aw_valid   = 0; fpga_axi.w_valid   = 0; fpga_axi.b_ready   = 0;
        fpga_axi.ar_valid   = 0; fpga_axi.r_ready   = 0;

        rst_ni = 1'b0;
        #20;
        rst_ni = 1'b1;
        #20;

        fpga_write(32'h0000_00A0, 32'hDEAD_BEEF);
        cgra_read (32'h0000_00A0, read_val);
        fpga_write(32'h0000_0100, 32'hCAFE_F00D);
        cgra_read (32'h0000_0100, read_val);
        fpga_write(32'h0000_0300, 32'hFEED_FACE);
        cgra_read (32'h0000_0300, read_val);
        fpga_write(32'h0000_0000, 32'hAAAA_AAAA);
        cgra_read (32'h0000_0000, read_val);
        fpga_write(32'h0000_0380, 32'hBBBB_BBBB);
        cgra_read (32'h0000_0380, read_val);
        fpga_write(32'h0000_0184, 32'hCCCC_CCCC);
        cgra_read (32'h0000_0184, read_val);
        fpga_write(32'h0000_00A0, 32'h1234_5678);
        cgra_read (32'h0000_00A0, read_val);
        fpga_write(32'h0000_0090, 32'hDDDD_DDDD);
        cgra_read (32'h0000_0090, read_val);
        cgra_read (32'h0000_00A0, read_val);
        fpga_write(32'h0000_0200, 32'hEEEE_EEEE);
        cgra_read (32'h0000_0204, read_val);
        cgra_read (32'h0000_0200, read_val);

        #50; $finish;
    end

endmodule
