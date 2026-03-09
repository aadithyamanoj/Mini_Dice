`include "axi/typedef.svh"
`include "dice_pkg.sv"

module axi_lite_dtcm_wrap_tb;

    logic clk_i  = 0;
    logic rst_ni = 0;

    always #10 clk_i = ~clk_i;

    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) cgra_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) fpga_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) dtcm_axi ();

    dice_crossbar i_xbar (
        .clk_i      ( clk_i    ),
        .rst_ni     ( rst_ni   ),
        .cgra_axi_i ( cgra_axi ),
        .fpga_axi_i ( fpga_axi ),
        .dtcm_axi_o ( dtcm_axi )
    );

    axi_lite_dtcm_wrap i_mem (
        .clk_i  ( clk_i    ),
        .rst_ni ( rst_ni   ),
        .axi_i  ( dtcm_axi )
    );

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
        cgra_axi.ar_valid = 1'b1;
        cgra_axi.ar_addr  = addr;
        wait(cgra_axi.ar_ready);
        @(posedge clk_i);
        cgra_axi.ar_valid = 1'b0;
        cgra_axi.r_ready  = 1'b1;
        wait(cgra_axi.r_valid);
        data = cgra_axi.r_data;
        @(posedge clk_i);
        cgra_axi.r_ready = 1'b0;
        $display("[TIME %0t] CGRA Read Data:  0x%h from Address: 0x%h", $time, data, addr);
    endtask

    logic [31:0] read_val;

    initial begin
        cgra_axi.aw_valid = 0; cgra_axi.w_valid = 0; cgra_axi.b_ready = 0;
        cgra_axi.ar_valid = 0; cgra_axi.r_ready = 0;
        fpga_axi.aw_valid = 0; fpga_axi.w_valid = 0; fpga_axi.b_ready = 0;
        fpga_axi.ar_valid = 0; fpga_axi.r_ready = 0;

        rst_ni = 1'b0;
        #20;
        rst_ni = 1'b1;
        #20;

        fpga_write(32'h0000_00A0, 32'hDEAD_BEEF);
        cgra_read(32'h0000_00A0, read_val);

        fpga_write(32'h0000_0100, 32'hCAFE_F00D);
        cgra_read(32'h0000_0100, read_val);

        fpga_write(32'h0000_0300, 32'hFEED_FACE);
        cgra_read(32'h0000_0300, read_val);

        fpga_write(32'h0000_0000, 32'hAAAA_AAAA);
        cgra_read(32'h0000_0000, read_val);

        fpga_write(32'h0000_0380, 32'hBBBB_BBBB);
        cgra_read(32'h0000_0380, read_val);

        fpga_write(32'h0000_0184, 32'hCCCC_CCCC);
        cgra_read(32'h0000_0184, read_val);

        fpga_write(32'h0000_00A0, 32'h1234_5678);
        cgra_read(32'h0000_00A0, read_val);

        fpga_write(32'h0000_0090, 32'hDDDD_DDDD);
        cgra_read(32'h0000_0090, read_val);
        cgra_read(32'h0000_00A0, read_val);

        fpga_write(32'h0000_0200, 32'hEEEE_EEEE);
        cgra_read(32'h0000_0204, read_val);
        cgra_read(32'h0000_0200, read_val);

        #50; $finish;
    end

endmodule
