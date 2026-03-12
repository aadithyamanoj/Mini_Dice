`include "axi/typedef.svh"
`include "dice_pkg.sv"

module dice_mem_system (
    input logic clk_i,
    input logic rst_ni,

    // -------------------------------------------------------------------------
    // 8-BIT TEST PATH (DTCM / Metadata - 256 Bytes)
    // -------------------------------------------------------------------------
    // Master Interfaces (Slave Modports)
    AXI_LITE.Slave cgra_axi_i, 
    AXI_LITE.Slave fpga_axi_i
);

    // -------------------------------------------------------------------------
    // Internal AXI-Lite Interconnect
    // -------------------------------------------------------------------------
    // Slave Interface (Connects Crossbar to Memory Wrapper)
    AXI_LITE #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(8)) mem_axi_bus ();

    // -------------------------------------------------------------------------
    // 1. 8-BIT CROSSBAR
    // -------------------------------------------------------------------------
    dice_crossbar_8bit #(
        .ADDR_WIDTH ( 32 ),
        .DATA_WIDTH ( 8  ),
        .NUM_MASTERS( 2  )
    ) i_8bit_xbar (
        .clk_i      ( clk_i        ),
        .rst_ni     ( rst_ni       ),
        .cgra_axi_i ( cgra_axi_i   ),
        .fpga_axi_i ( fpga_axi_i   ),
        .dtcm_axi_o ( mem_axi_bus  ) 
    );

    // -------------------------------------------------------------------------
    // 2. 8-BIT 1R1W MEMORY WRAPPER
    // -------------------------------------------------------------------------
    // Uses the bsg_mem_1r1w_sync_mask_write_byte internally
    axi_lite_mem_wrap_8bit #(
        .AXI_ADDR_WIDTH ( 32  ),
        .AXI_DATA_WIDTH ( 8   ),
        .NUM_WORDS      ( 256 ) // 256 Bytes total (1 byte per word)
    ) i_mem_wrap (
        .clk_i          ( clk_i       ),
        .rst_ni         ( rst_ni      ),
        .axi_i          ( mem_axi_bus )
    );

endmodule