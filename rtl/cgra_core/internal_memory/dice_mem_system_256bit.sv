`include "axi/typedef.svh"
`include "dice_pkg.sv"

module dice_mem_system_256bit (
    input logic clk_i,
    input logic rst_ni,

    // -------------------------------------------------------------------------
    // 256-BIT PATH (32 words x 256 bits = 1KB)
    // -------------------------------------------------------------------------
    AXI_LITE.Slave cgra_axi_i,
    AXI_LITE.Slave fpga_axi_i
);

    // -------------------------------------------------------------------------
    // Internal AXI-Lite Interconnect (256-bit wide)
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) mem_axi_bus ();

    // -------------------------------------------------------------------------
    // 1. 256-BIT CROSSBAR
    // -------------------------------------------------------------------------
    dice_crossbar_256bit #(
        .ADDR_WIDTH ( 32  ),
        .DATA_WIDTH ( 256 ),
        .NUM_MASTERS( 2   )
    ) i_256bit_xbar (
        .clk_i      ( clk_i       ),
        .rst_ni     ( rst_ni      ),
        .cgra_axi_i ( cgra_axi_i  ),
        .fpga_axi_i ( fpga_axi_i  ),
        .dtcm_axi_o ( mem_axi_bus )
    );

    // -------------------------------------------------------------------------
    // 2. 256-BIT 1RW MEMORY WRAPPER
    //    32 words x 256 bits = 1KB total
    // -------------------------------------------------------------------------
    axi_lite_mem_wrap_256bit #(
        .AXI_ADDR_WIDTH ( 32  ),
        .AXI_DATA_WIDTH ( 256 ),
        .NUM_WORDS      ( 32  )
    ) i_mem_wrap (
        .clk_i  ( clk_i       ),
        .rst_ni ( rst_ni      ),
        .axi_i  ( mem_axi_bus )
    );

endmodule
