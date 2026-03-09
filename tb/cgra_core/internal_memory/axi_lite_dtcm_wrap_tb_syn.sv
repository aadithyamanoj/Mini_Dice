`include "axi/typedef.svh"
`include "dice_pkg.sv"

module axi_lite_dtcm_wrap_tb_syn;

    logic clk_i  = 0;
    logic rst_ni = 0;
    always #10000 clk_i = ~clk_i;  // 20ns period = 50 MHz (1ps timescale)

    // -------------------------------------------------------------------------
    // Flat signals - cgra (master)
    // -------------------------------------------------------------------------
    logic        cgra_aw_valid = 0, cgra_aw_ready;
    logic [31:0] cgra_aw_addr  = 0;
    logic [2:0]  cgra_aw_prot  = 0;
    logic        cgra_w_valid  = 0, cgra_w_ready;
    logic [31:0] cgra_w_data   = 0;
    logic [3:0]  cgra_w_strb   = 0;
    logic        cgra_b_ready  = 0, cgra_b_valid;
    logic [1:0]  cgra_b_resp;
    logic        cgra_ar_valid = 0, cgra_ar_ready;
    logic [31:0] cgra_ar_addr  = 0;
    logic [2:0]  cgra_ar_prot  = 0;
    logic        cgra_r_ready  = 0, cgra_r_valid;
    logic [31:0] cgra_r_data;
    logic [1:0]  cgra_r_resp;

    // -------------------------------------------------------------------------
    // Flat signals - fpga (master)
    // -------------------------------------------------------------------------
    logic        fpga_aw_valid = 0, fpga_aw_ready;
    logic [31:0] fpga_aw_addr  = 0;
    logic [2:0]  fpga_aw_prot  = 0;
    logic        fpga_w_valid  = 0, fpga_w_ready;
    logic [31:0] fpga_w_data   = 0;
    logic [3:0]  fpga_w_strb   = 0;
    logic        fpga_b_ready  = 0, fpga_b_valid;
    logic [1:0]  fpga_b_resp;
    logic        fpga_ar_valid = 0, fpga_ar_ready;
    logic [31:0] fpga_ar_addr  = 0;
    logic [2:0]  fpga_ar_prot  = 0;
    logic        fpga_r_ready  = 0, fpga_r_valid;
    logic [31:0] fpga_r_data;
    logic [1:0]  fpga_r_resp;

    // -------------------------------------------------------------------------
    // Flat signals - dtcm (slave, between crossbar and dtcm_wrap)
    // -------------------------------------------------------------------------
    logic        dtcm_aw_valid, dtcm_aw_ready;
    logic [31:0] dtcm_aw_addr;
    logic [2:0]  dtcm_aw_prot;
    logic        dtcm_w_valid,  dtcm_w_ready;
    logic [31:0] dtcm_w_data;
    logic [3:0]  dtcm_w_strb;
    logic        dtcm_b_ready,  dtcm_b_valid;
    logic [1:0]  dtcm_b_resp;
    logic        dtcm_ar_valid, dtcm_ar_ready;
    logic [31:0] dtcm_ar_addr;
    logic [2:0]  dtcm_ar_prot;
    logic        dtcm_r_ready,  dtcm_r_valid;
    logic [31:0] dtcm_r_data;
    logic [1:0]  dtcm_r_resp;

    // -------------------------------------------------------------------------
    // AXI_LITE interface - only needed for axi_lite_dtcm_wrap (still RTL)
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) dtcm_axi ();

    // dtcm flat wires <-> dtcm_axi interface
    assign dtcm_axi.aw_addr  = dtcm_aw_addr;
    assign dtcm_axi.aw_prot  = dtcm_aw_prot;
    assign dtcm_axi.aw_valid = dtcm_aw_valid;
    assign dtcm_aw_ready     = dtcm_axi.aw_ready;
    assign dtcm_axi.w_data   = dtcm_w_data;
    assign dtcm_axi.w_strb   = dtcm_w_strb;
    assign dtcm_axi.w_valid  = dtcm_w_valid;
    assign dtcm_w_ready      = dtcm_axi.w_ready;
    assign dtcm_b_resp       = dtcm_axi.b_resp;
    assign dtcm_b_valid      = dtcm_axi.b_valid;
    assign dtcm_axi.b_ready  = dtcm_b_ready;
    assign dtcm_axi.ar_addr  = dtcm_ar_addr;
    assign dtcm_axi.ar_prot  = dtcm_ar_prot;
    assign dtcm_axi.ar_valid = dtcm_ar_valid;
    assign dtcm_ar_ready     = dtcm_axi.ar_ready;
    assign dtcm_r_data       = dtcm_axi.r_data;
    assign dtcm_r_resp       = dtcm_axi.r_resp;
    assign dtcm_r_valid      = dtcm_axi.r_valid;
    assign dtcm_axi.r_ready  = dtcm_r_ready;

    // -------------------------------------------------------------------------
    // dice_crossbar - synthesized netlist, fully flat ports
    // -------------------------------------------------------------------------
    dice_crossbar i_xbar (
        .clk_i                  ( clk_i         ),
        .rst_ni                 ( rst_ni         ),

        // cgra master inputs (driven by TB)
        .cgra_axi_i_aw_addr     ( cgra_aw_addr   ),
        .cgra_axi_i_aw_prot     ( cgra_aw_prot   ),
        .cgra_axi_i_aw_valid    ( cgra_aw_valid  ),
        .cgra_axi_i_w_data      ( cgra_w_data    ),
        .cgra_axi_i_w_strb      ( cgra_w_strb    ),
        .cgra_axi_i_w_valid     ( cgra_w_valid   ),
        .cgra_axi_i_b_ready     ( cgra_b_ready   ),
        .cgra_axi_i_ar_addr     ( cgra_ar_addr   ),
        .cgra_axi_i_ar_prot     ( cgra_ar_prot   ),
        .cgra_axi_i_ar_valid    ( cgra_ar_valid  ),
        .cgra_axi_i_r_ready     ( cgra_r_ready   ),

        // cgra master outputs (back to TB)
        .cgra_axi_i_aw_ready    ( cgra_aw_ready  ),
        .cgra_axi_i_w_ready     ( cgra_w_ready   ),
        .cgra_axi_i_b_resp      ( cgra_b_resp    ),
        .cgra_axi_i_b_valid     ( cgra_b_valid   ),
        .cgra_axi_i_ar_ready    ( cgra_ar_ready  ),
        .cgra_axi_i_r_data      ( cgra_r_data    ),
        .cgra_axi_i_r_resp      ( cgra_r_resp    ),
        .cgra_axi_i_r_valid     ( cgra_r_valid   ),

        // fpga master inputs (driven by TB)
        .fpga_axi_i_aw_addr     ( fpga_aw_addr   ),
        .fpga_axi_i_aw_prot     ( fpga_aw_prot   ),
        .fpga_axi_i_aw_valid    ( fpga_aw_valid  ),
        .fpga_axi_i_w_data      ( fpga_w_data    ),
        .fpga_axi_i_w_strb      ( fpga_w_strb    ),
        .fpga_axi_i_w_valid     ( fpga_w_valid   ),
        .fpga_axi_i_b_ready     ( fpga_b_ready   ),
        .fpga_axi_i_ar_addr     ( fpga_ar_addr   ),
        .fpga_axi_i_ar_prot     ( fpga_ar_prot   ),
        .fpga_axi_i_ar_valid    ( fpga_ar_valid  ),
        .fpga_axi_i_r_ready     ( fpga_r_ready   ),

        // fpga master outputs (back to TB)
        .fpga_axi_i_aw_ready    ( fpga_aw_ready  ),
        .fpga_axi_i_w_ready     ( fpga_w_ready   ),
        .fpga_axi_i_b_resp      ( fpga_b_resp    ),
        .fpga_axi_i_b_valid     ( fpga_b_valid   ),
        .fpga_axi_i_ar_ready    ( fpga_ar_ready  ),
        .fpga_axi_i_r_data      ( fpga_r_data    ),
        .fpga_axi_i_r_resp      ( fpga_r_resp    ),
        .fpga_axi_i_r_valid     ( fpga_r_valid   ),

        // dtcm slave outputs (crossbar -> memory)
        .dtcm_axi_o_aw_addr     ( dtcm_aw_addr   ),
        .dtcm_axi_o_aw_prot     ( dtcm_aw_prot   ),
        .dtcm_axi_o_aw_valid    ( dtcm_aw_valid  ),
        .dtcm_axi_o_w_data      ( dtcm_w_data    ),
        .dtcm_axi_o_w_strb      ( dtcm_w_strb    ),
        .dtcm_axi_o_w_valid     ( dtcm_w_valid   ),
        .dtcm_axi_o_b_ready     ( dtcm_b_ready   ),
        .dtcm_axi_o_ar_addr     ( dtcm_ar_addr   ),
        .dtcm_axi_o_ar_prot     ( dtcm_ar_prot   ),
        .dtcm_axi_o_ar_valid    ( dtcm_ar_valid  ),
        .dtcm_axi_o_r_ready     ( dtcm_r_ready   ),

        // dtcm slave inputs (memory -> crossbar)
        .dtcm_axi_o_aw_ready    ( dtcm_aw_ready  ),
        .dtcm_axi_o_w_ready     ( dtcm_w_ready   ),
        .dtcm_axi_o_b_resp      ( dtcm_b_resp    ),
        .dtcm_axi_o_b_valid     ( dtcm_b_valid   ),
        .dtcm_axi_o_ar_ready    ( dtcm_ar_ready  ),
        .dtcm_axi_o_r_data      ( dtcm_r_data    ),
        .dtcm_axi_o_r_resp      ( dtcm_r_resp    ),
        .dtcm_axi_o_r_valid     ( dtcm_r_valid   )
    );

    // -------------------------------------------------------------------------
    // axi_lite_dtcm_wrap - connected directly via dtcm_axi interface
    // -------------------------------------------------------------------------
    axi_lite_dtcm_wrap i_mem (
        .clk_i  ( clk_i    ),
        .rst_ni ( rst_ni   ),
        .axi_i  ( dtcm_axi )
    );

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task fpga_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_i);
        fpga_aw_valid = 1'b1;
        fpga_aw_addr  = addr;
        fpga_w_valid  = 1'b1;
        fpga_w_data   = data;
        fpga_w_strb   = 4'b1111;
        fork
            wait(fpga_aw_ready && fpga_w_ready);
            begin repeat(500) @(posedge clk_i); $display("TIMEOUT: fpga_write aw/w ready"); $finish; end
        join_any
        disable fork;
        @(posedge clk_i);
        fpga_aw_valid = 1'b0;
        fpga_w_valid  = 1'b0;
        fpga_b_ready  = 1'b1;
        fork
            wait(fpga_b_valid);
            begin repeat(500) @(posedge clk_i); $display("TIMEOUT: fpga_write b_valid"); $finish; end
        join_any
        disable fork;
        @(posedge clk_i);
        fpga_b_ready = 1'b0;
        $display("[TIME %0t] FPGA Wrote Data: 0x%h to Address: 0x%h", $time, data, addr);
    endtask

    task cgra_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_i);
        cgra_ar_valid = 1'b1;
        cgra_ar_addr  = addr;
        fork
            wait(cgra_ar_ready);
            begin repeat(500) @(posedge clk_i); $display("TIMEOUT: cgra_read ar_ready"); $finish; end
        join_any
        disable fork;
        @(posedge clk_i);
        cgra_ar_valid = 1'b0;
        cgra_r_ready  = 1'b1;
        fork
            wait(cgra_r_valid);
            begin repeat(500) @(posedge clk_i); $display("TIMEOUT: cgra_read r_valid"); $finish; end
        join_any
        disable fork;
        data = cgra_r_data;
        @(posedge clk_i);
        cgra_r_ready = 1'b0;
        $display("[TIME %0t] CGRA Read Data:  0x%h from Address: 0x%h", $time, data, addr);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    logic [31:0] read_val;
    initial begin
        rst_ni = 1'b0;
        repeat(10) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat(5) @(posedge clk_i);
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