`include "axi/typedef.svh"
`include "dice_pkg.sv"

module axi_lite_dtcm_wrap_tb_syn;

    logic clk_i  = 0;
    logic rst_ni = 0;
    always #10000 clk_i = ~clk_i; 

    localparam int NM   = 9;
    localparam int FPGA = 8;
    localparam int CGRA0 = 0;

    // Flat signal arrays for synthesized crossbar ports
    logic [NM-1:0]        m_aw_valid = '0, m_aw_ready;
    logic [NM-1:0][31:0]  m_aw_addr  = '0;
    logic [NM-1:0][2:0]   m_aw_prot  = '0;
    logic [NM-1:0]        m_w_valid  = '0, m_w_ready;
    logic [NM-1:0][31:0]  m_w_data   = '0;
    logic [NM-1:0][3:0]   m_w_strb   = '0;
    logic [NM-1:0]        m_b_valid,       m_b_ready = '0;
    logic [NM-1:0][1:0]   m_b_resp;
    logic [NM-1:0]        m_ar_valid = '0, m_ar_ready;
    logic [NM-1:0][31:0]  m_ar_addr  = '0;
    logic [NM-1:0][2:0]   m_ar_prot  = '0;
    logic [NM-1:0]        m_r_valid,       m_r_ready = '0;
    logic [NM-1:0][31:0]  m_r_data;
    logic [NM-1:0][1:0]   m_r_resp;

    // Bridge signals for DTCM wrapper
    logic [31:0] dtcm_aw_addr;
    logic [2:0]  dtcm_aw_prot;
    logic        dtcm_aw_valid, dtcm_aw_ready;
    logic [31:0] dtcm_w_data;
    logic [3:0]  dtcm_w_strb;
    logic        dtcm_w_valid, dtcm_w_ready;
    logic [1:0]  dtcm_b_resp;
    logic        dtcm_b_valid, dtcm_b_ready;
    logic [31:0] dtcm_ar_addr;
    logic [2:0]  dtcm_ar_prot;
    logic        dtcm_ar_valid, dtcm_ar_ready;
    logic [31:0] dtcm_r_data;
    logic [1:0]  dtcm_r_resp;
    logic        dtcm_r_valid, dtcm_r_ready;

    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32)) dtcm_axi ();

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

    dice_crossbar i_xbar (
        .clk_i  ( clk_i  ),
        .rst_ni ( rst_ni ),
        // test_i removed per user instruction

        .cgra_0_axi_i_aw_addr  ( m_aw_addr [0] ), .cgra_0_axi_i_aw_prot  ( m_aw_prot [0] ),
        .cgra_0_axi_i_aw_valid ( m_aw_valid[0] ), .cgra_0_axi_i_aw_ready ( m_aw_ready[0] ),
        .cgra_0_axi_i_w_data   ( m_w_data  [0] ), .cgra_0_axi_i_w_strb   ( m_w_strb  [0] ),
        .cgra_0_axi_i_w_valid  ( m_w_valid [0] ), .cgra_0_axi_i_w_ready  ( m_w_ready [0] ),
        .cgra_0_axi_i_b_resp   ( m_b_resp  [0] ), .cgra_0_axi_i_b_valid  ( m_b_valid [0] ),
        .cgra_0_axi_i_b_ready  ( m_b_ready [0] ),
        .cgra_0_axi_i_ar_addr  ( m_ar_addr [0] ), .cgra_0_axi_i_ar_prot  ( m_ar_prot [0] ),
        .cgra_0_axi_i_ar_valid ( m_ar_valid[0] ), .cgra_0_axi_i_ar_ready ( m_ar_ready[0] ),
        .cgra_0_axi_i_r_data   ( m_r_data  [0] ), .cgra_0_axi_i_r_resp   ( m_r_resp  [0] ),
        .cgra_0_axi_i_r_valid  ( m_r_valid [0] ), .cgra_0_axi_i_r_ready  ( m_r_ready [0] ),

        .cgra_1_axi_i_aw_addr  ( m_aw_addr [1] ), .cgra_1_axi_i_aw_prot  ( m_aw_prot [1] ),
        .cgra_1_axi_i_aw_valid ( m_aw_valid[1] ), .cgra_1_axi_i_aw_ready ( m_aw_ready[1] ),
        .cgra_1_axi_i_w_data   ( m_w_data  [1] ), .cgra_1_axi_i_w_strb   ( m_w_strb  [1] ),
        .cgra_1_axi_i_w_valid  ( m_w_valid [1] ), .cgra_1_axi_i_w_ready  ( m_w_ready [1] ),
        .cgra_1_axi_i_b_resp   ( m_b_resp  [1] ), .cgra_1_axi_i_b_valid  ( m_b_valid [1] ),
        .cgra_1_axi_i_b_ready  ( m_b_ready [1] ),
        .cgra_1_axi_i_ar_addr  ( m_ar_addr [1] ), .cgra_1_axi_i_ar_prot  ( m_ar_prot [1] ),
        .cgra_1_axi_i_ar_valid ( m_ar_valid[1] ), .cgra_1_axi_i_ar_ready ( m_ar_ready[1] ),
        .cgra_1_axi_i_r_data   ( m_r_data  [1] ), .cgra_1_axi_i_r_resp   ( m_r_resp  [1] ),
        .cgra_1_axi_i_r_valid  ( m_r_valid [1] ), .cgra_1_axi_i_r_ready  ( m_r_ready [1] ),

        .cgra_2_axi_i_aw_addr  ( m_aw_addr [2] ), .cgra_2_axi_i_aw_prot  ( m_aw_prot [2] ),
        .cgra_2_axi_i_aw_valid ( m_aw_valid[2] ), .cgra_2_axi_i_aw_ready ( m_aw_ready[2] ),
        .cgra_2_axi_i_w_data   ( m_w_data  [2] ), .cgra_2_axi_i_w_strb   ( m_w_strb  [2] ),
        .cgra_2_axi_i_w_valid  ( m_w_valid [2] ), .cgra_2_axi_i_w_ready  ( m_w_ready [2] ),
        .cgra_2_axi_i_b_resp   ( m_b_resp  [2] ), .cgra_2_axi_i_b_valid  ( m_b_valid [2] ),
        .cgra_2_axi_i_b_ready  ( m_b_ready [2] ),
        .cgra_2_axi_i_ar_addr  ( m_ar_addr [2] ), .cgra_2_axi_i_ar_prot  ( m_ar_prot [2] ),
        .cgra_2_axi_i_ar_valid ( m_ar_valid[2] ), .cgra_2_axi_i_ar_ready ( m_ar_ready[2] ),
        .cgra_2_axi_i_r_data   ( m_r_data  [2] ), .cgra_2_axi_i_r_resp   ( m_r_resp  [2] ),
        .cgra_2_axi_i_r_valid  ( m_r_valid [2] ), .cgra_2_axi_i_r_ready  ( m_r_ready [2] ),

        .cgra_3_axi_i_aw_addr  ( m_aw_addr [3] ), .cgra_3_axi_i_aw_prot  ( m_aw_prot [3] ),
        .cgra_3_axi_i_aw_valid ( m_aw_valid[3] ), .cgra_3_axi_i_aw_ready ( m_aw_ready[3] ),
        .cgra_3_axi_i_w_data   ( m_w_data  [3] ), .cgra_3_axi_i_w_strb   ( m_w_strb  [3] ),
        .cgra_3_axi_i_w_valid  ( m_w_valid [3] ), .cgra_3_axi_i_w_ready  ( m_w_ready [3] ),
        .cgra_3_axi_i_b_resp   ( m_b_resp  [3] ), .cgra_3_axi_i_b_valid  ( m_b_valid [3] ),
        .cgra_3_axi_i_b_ready  ( m_b_ready [3] ),
        .cgra_3_axi_i_ar_addr  ( m_ar_addr [3] ), .cgra_3_axi_i_ar_prot  ( m_ar_prot [3] ),
        .cgra_3_axi_i_ar_valid ( m_ar_valid[3] ), .cgra_3_axi_i_ar_ready ( m_ar_ready[3] ),
        .cgra_3_axi_i_r_data   ( m_r_data  [3] ), .cgra_3_axi_i_r_resp   ( m_r_resp  [3] ),
        .cgra_3_axi_i_r_valid  ( m_r_valid [3] ), .cgra_3_axi_i_r_ready  ( m_r_ready [3] ),

        .cgra_4_axi_i_aw_addr  ( m_aw_addr [4] ), .cgra_4_axi_i_aw_prot  ( m_aw_prot [4] ),
        .cgra_4_axi_i_aw_valid ( m_aw_valid[4] ), .cgra_4_axi_i_aw_ready ( m_aw_ready[4] ),
        .cgra_4_axi_i_w_data   ( m_w_data  [4] ), .cgra_4_axi_i_w_strb   ( m_w_strb  [4] ),
        .cgra_4_axi_i_w_valid  ( m_w_valid [4] ), .cgra_4_axi_i_w_ready  ( m_w_ready [4] ),
        .cgra_4_axi_i_b_resp   ( m_b_resp  [4] ), .cgra_4_axi_i_b_valid  ( m_b_valid [4] ),
        .cgra_4_axi_i_b_ready  ( m_b_ready [4] ),
        .cgra_4_axi_i_ar_addr  ( m_ar_addr [4] ), .cgra_4_axi_i_ar_prot  ( m_ar_prot [4] ),
        .cgra_4_axi_i_ar_valid ( m_ar_valid[4] ), .cgra_4_axi_i_ar_ready ( m_ar_ready[4] ),
        .cgra_4_axi_i_r_data   ( m_r_data  [4] ), .cgra_4_axi_i_r_resp   ( m_r_resp  [4] ),
        .cgra_4_axi_i_r_valid  ( m_r_valid [4] ), .cgra_4_axi_i_r_ready  ( m_r_ready [4] ),

        .cgra_5_axi_i_aw_addr  ( m_aw_addr [5] ), .cgra_5_axi_i_aw_prot  ( m_aw_prot [5] ),
        .cgra_5_axi_i_aw_valid ( m_aw_valid[5] ), .cgra_5_axi_i_aw_ready ( m_aw_ready[5] ),
        .cgra_5_axi_i_w_data   ( m_w_data  [5] ), .cgra_5_axi_i_w_strb   ( m_w_strb  [5] ),
        .cgra_5_axi_i_w_valid  ( m_w_valid [5] ), .cgra_5_axi_i_w_ready  ( m_w_ready [5] ),
        .cgra_5_axi_i_b_resp   ( m_b_resp  [5] ), .cgra_5_axi_i_b_valid  ( m_b_valid [5] ),
        .cgra_5_axi_i_b_ready  ( m_b_ready [5] ),
        .cgra_5_axi_i_ar_addr  ( m_ar_addr [5] ), .cgra_5_axi_i_ar_prot  ( m_ar_prot [5] ),
        .cgra_5_axi_i_ar_valid ( m_ar_valid[5] ), .cgra_5_axi_i_ar_ready ( m_ar_ready[5] ),
        .cgra_5_axi_i_r_data   ( m_r_data  [5] ), .cgra_5_axi_i_r_resp   ( m_r_resp  [5] ),
        .cgra_5_axi_i_r_valid  ( m_r_valid [5] ), .cgra_5_axi_i_r_ready  ( m_r_ready [5] ),

        .cgra_6_axi_i_aw_addr  ( m_aw_addr [6] ), .cgra_6_axi_i_aw_prot  ( m_aw_prot [6] ),
        .cgra_6_axi_i_aw_valid ( m_aw_valid[6] ), .cgra_6_axi_i_aw_ready ( m_aw_ready[6] ),
        .cgra_6_axi_i_w_data   ( m_w_data  [6] ), .cgra_6_axi_i_w_strb   ( m_w_strb  [6] ),
        .cgra_6_axi_i_w_valid  ( m_w_valid [6] ), .cgra_6_axi_i_w_ready  ( m_w_ready [6] ),
        .cgra_6_axi_i_b_resp   ( m_b_resp  [6] ), .cgra_6_axi_i_b_valid  ( m_b_valid [6] ),
        .cgra_6_axi_i_b_ready  ( m_b_ready [6] ),
        .cgra_6_axi_i_ar_addr  ( m_ar_addr [6] ), .cgra_6_axi_i_ar_prot  ( m_ar_prot [6] ),
        .cgra_6_axi_i_ar_valid ( m_ar_valid[6] ), .cgra_6_axi_i_ar_ready ( m_ar_ready[6] ),
        .cgra_6_axi_i_r_data   ( m_r_data  [6] ), .cgra_6_axi_i_r_resp   ( m_r_resp  [6] ),
        .cgra_6_axi_i_r_valid  ( m_r_valid [6] ), .cgra_6_axi_i_r_ready  ( m_r_ready [6] ),

        .cgra_7_axi_i_aw_addr  ( m_aw_addr [7] ), .cgra_7_axi_i_aw_prot  ( m_ar_prot [7] ),
        .cgra_7_axi_i_aw_valid ( m_aw_valid[7] ), .cgra_7_axi_i_aw_ready ( m_aw_ready[7] ),
        .cgra_7_axi_i_w_data   ( m_w_data  [7] ), .cgra_7_axi_i_w_strb   ( m_w_strb  [7] ),
        .cgra_7_axi_i_w_valid  ( m_w_valid [7] ), .cgra_7_axi_i_w_ready  ( m_w_ready [7] ),
        .cgra_7_axi_i_b_resp   ( m_b_resp  [7] ), .cgra_7_axi_i_b_valid  ( m_b_valid [7] ),
        .cgra_7_axi_i_b_ready  ( m_b_ready [7] ),
        .cgra_7_axi_i_ar_addr  ( m_ar_addr [7] ), .cgra_7_axi_i_ar_prot  ( m_ar_prot [7] ),
        .cgra_7_axi_i_ar_valid ( m_ar_valid[7] ), .cgra_7_axi_i_ar_ready ( m_ar_ready[7] ),
        .cgra_7_axi_i_r_data   ( m_r_data  [7] ), .cgra_7_axi_i_r_resp   ( m_r_resp  [7] ),
        .cgra_7_axi_i_r_valid  ( m_r_valid [7] ), .cgra_7_axi_i_r_ready  ( m_r_ready [7] ),

        .fpga_axi_i_aw_addr  ( m_aw_addr [FPGA] ), .fpga_axi_i_aw_prot  ( m_aw_prot [FPGA] ),
        .fpga_axi_i_aw_valid ( m_aw_valid[FPGA] ), .fpga_axi_i_aw_ready ( m_aw_ready[FPGA] ),
        .fpga_axi_i_w_data   ( m_w_data  [FPGA] ), .fpga_axi_i_w_strb   ( m_w_strb  [FPGA] ),
        .fpga_axi_i_w_valid  ( m_w_valid [FPGA] ), .fpga_axi_i_w_ready  ( m_w_ready [FPGA] ),
        .fpga_axi_i_b_resp   ( m_b_resp  [FPGA] ), .fpga_axi_i_b_valid  ( m_b_valid [FPGA] ),
        .fpga_axi_i_b_ready  ( m_b_ready [FPGA] ),
        .fpga_axi_i_ar_addr  ( m_ar_addr [FPGA] ), .fpga_axi_i_ar_prot  ( m_ar_prot [FPGA] ),
        .fpga_axi_i_ar_valid ( m_ar_valid[FPGA] ), .fpga_axi_i_ar_ready ( m_ar_ready[FPGA] ),
        .fpga_axi_i_r_data   ( m_r_data  [FPGA] ), .fpga_axi_i_r_resp   ( m_r_resp  [FPGA] ),
        .fpga_axi_i_r_valid  ( m_r_valid [FPGA] ), .fpga_axi_i_r_ready  ( m_r_ready [FPGA] ),

        .dtcm_axi_o_aw_addr  ( dtcm_aw_addr  ), .dtcm_axi_o_aw_prot  ( dtcm_aw_prot  ),
        .dtcm_axi_o_aw_valid ( dtcm_aw_valid ), .dtcm_axi_o_aw_ready ( dtcm_aw_ready ),
        .dtcm_axi_o_w_data   ( dtcm_w_data   ), .dtcm_axi_o_w_strb   ( dtcm_w_strb   ),
        .dtcm_axi_o_w_valid  ( dtcm_w_valid  ), .dtcm_axi_o_w_ready  ( dtcm_w_ready  ),
        .dtcm_axi_o_b_resp   ( dtcm_b_resp   ), .dtcm_axi_o_b_valid  ( dtcm_b_valid  ),
        .dtcm_axi_o_b_ready  ( dtcm_b_ready  ),
        .dtcm_axi_o_ar_addr  ( dtcm_ar_addr  ), .dtcm_axi_o_ar_prot  ( dtcm_ar_prot  ),
        .dtcm_axi_o_ar_valid ( dtcm_ar_valid ), .dtcm_axi_o_ar_ready ( dtcm_ar_ready ),
        .dtcm_axi_o_r_data   ( dtcm_r_data   ), .dtcm_axi_o_r_resp   ( dtcm_r_resp   ),
        .dtcm_axi_o_r_valid  ( dtcm_r_valid  ), .dtcm_axi_o_r_ready  ( dtcm_r_ready  )
    );

    axi_lite_dtcm_wrap i_mem (
        .clk_i  ( clk_i    ),
        .rst_ni ( rst_ni   ),
        .axi_i  ( dtcm_axi )
    );

    // Synchronous tasks with restored verification displays
    task fpga_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_i);
        m_aw_valid[FPGA] <= 1'b1;
        m_aw_addr [FPGA] <= addr;
        m_w_valid [FPGA] <= 1'b1;
        m_w_data  [FPGA] <= data;
        m_w_strb  [FPGA] <= 4'b1111;

        do begin
            @(posedge clk_i);
        end while (!(m_aw_ready[FPGA] && m_w_ready[FPGA]));
        
        m_aw_valid[FPGA] <= 1'b0;
        m_w_valid [FPGA] <= 1'b0;
        m_b_ready [FPGA] <= 1'b1;

        do begin
            @(posedge clk_i);
        end while (!m_b_valid[FPGA]);

        m_b_ready[FPGA] <= 1'b0;
        $display("[TIME %0t] FPGA Wrote Data: 0x%h to Address: 0x%h", $time, data, addr); 
    endtask

    task cgra_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_i);
        m_ar_valid[CGRA0] <= 1'b1;
        m_ar_addr [CGRA0] <= addr;
        
        do begin
            @(posedge clk_i);
        end while (!m_ar_ready[CGRA0]);
        
        m_ar_valid[CGRA0] <= 1'b0;
        m_r_ready [CGRA0] <= 1'b1;

        do begin
            @(posedge clk_i);
        end while (!m_r_valid[CGRA0]);
        
        data = m_r_data[CGRA0];
        m_r_ready[CGRA0] <= 1'b0;
        $display("[TIME %0t] CGRA Read Data:  0x%h from Address: 0x%h", $time, data, addr); 
    endtask

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