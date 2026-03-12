`include "axi/typedef.svh"
`include "dice_pkg.sv"

/**
 * Combined Memory System: Dual-Width Architecture
 *
 * Integrates both 8-bit (256B) and 256-bit (1KB) memory systems into a single
 * top-level module, allowing CGRA/FPGA to independently read/write from both.
 *
 * Memory Map:
 * - 8-bit path:   0x00000000 - 0x000000FF  (256 bytes, 8-bit wide)
 * - 256-bit path: 0x00000100 - 0x00000FFF  (1KB, 256-bit wide)
 */
module dice_mem_system_combined (
    input logic clk_i,
    input logic rst_ni,

    // -------------------------------------------------------------------------
    // CGRA 8-BIT PATH (256 Bytes)
    // -------------------------------------------------------------------------
    AXI_LITE.Slave cgra_axi_8bit_i,

    // -------------------------------------------------------------------------
    // CGRA 256-BIT PATH (1 KB)
    // -------------------------------------------------------------------------
    AXI_LITE.Slave cgra_axi_256bit_i,

    // -------------------------------------------------------------------------
    // FPGA 8-BIT PATH (256 Bytes)
    // -------------------------------------------------------------------------
    AXI_LITE.Slave fpga_axi_8bit_i,

    // -------------------------------------------------------------------------
    // FPGA 256-BIT PATH (1 KB)
    // -------------------------------------------------------------------------
    AXI_LITE.Slave fpga_axi_256bit_i
);

    // =========================================================================
    // 8-BIT SUBSYSTEM
    // =========================================================================

    // Internal AXI-Lite bus for 8-bit path
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) mem_axi_bus_8bit ();

    // 8-bit Crossbar: Arbitrates between CGRA and FPGA 8-bit interfaces
    dice_crossbar_8bit #(
        .ADDR_WIDTH ( 32 ),
        .DATA_WIDTH ( 8  ),
        .NUM_MASTERS( 2  )
    ) i_8bit_xbar (
        .clk_i      ( clk_i              ),
        .rst_ni     ( rst_ni             ),
        .cgra_axi_i ( cgra_axi_8bit_i    ),
        .fpga_axi_i ( fpga_axi_8bit_i    ),
        .dtcm_axi_o ( mem_axi_bus_8bit   )
    );

    // 8-bit Memory Wrapper: 256 bytes (1 byte per word)
    axi_lite_mem_wrap_8bit #(
        .AXI_ADDR_WIDTH ( 32  ),
        .AXI_DATA_WIDTH ( 8   ),
        .NUM_WORDS      ( 256 )
    ) i_mem_wrap_8bit (
        .clk_i          ( clk_i            ),
        .rst_ni         ( rst_ni           ),
        .axi_i          ( mem_axi_bus_8bit )
    );

    // =========================================================================
    // 256-BIT SUBSYSTEM
    // =========================================================================

    // Internal AXI-Lite bus for 256-bit path
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(256)) mem_axi_bus_256bit ();

    // 256-bit Crossbar: Arbitrates between CGRA and FPGA 256-bit interfaces
    dice_crossbar_256bit #(
        .ADDR_WIDTH ( 32  ),
        .DATA_WIDTH ( 256 ),
        .NUM_MASTERS( 2   )
    ) i_256bit_xbar (
        .clk_i      ( clk_i                ),
        .rst_ni     ( rst_ni               ),
        .cgra_axi_i ( cgra_axi_256bit_i    ),
        .fpga_axi_i ( fpga_axi_256bit_i    ),
        .dtcm_axi_o ( mem_axi_bus_256bit   )
    );

    // 256-bit Memory Wrapper: 32 words x 256 bits = 1KB total
    axi_lite_mem_wrap_256bit #(
        .AXI_ADDR_WIDTH ( 32  ),
        .AXI_DATA_WIDTH ( 256 ),
        .NUM_WORDS      ( 32  )
    ) i_mem_wrap_256bit (
        .clk_i  ( clk_i              ),
        .rst_ni ( rst_ni             ),
        .axi_i  ( mem_axi_bus_256bit )
    );

endmodule
