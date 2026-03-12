`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "dice_pkg.sv"

module dice_crossbar_8bit
import dice_pkg::*;
#(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 8,   // Fixed at 8-bit for this test
    parameter int NUM_MASTERS = 2    // 0: CGRA, 1: FPGA
)(
    input  logic clk_i,
    input  logic rst_ni,

    // Master 0: CGRA
    AXI_LITE.Slave  cgra_axi_i,

    // Master 1: FPGA
    AXI_LITE.Slave  fpga_axi_i,

    // Slave 0: DTCM (8-bit bank)
    AXI_LITE.Master dtcm_axi_o
);
    // Configuration for the internal AXI-Lite Crossbar IP [cite: 134-136]
    localparam axi_pkg::xbar_cfg_t XBAR_CFG = '{
        NoSlvPorts:         NUM_MASTERS,
        NoMstPorts:         32'd1,
        MaxMstTrans:        32'd4,
        MaxSlvTrans:        32'd4,
        FallThrough:        1'b0,
        LatencyMode:        10'h3FF,
        PipelineStages:     32'd0,
        AxiIdWidthSlvPorts: 32'd1,
        AxiIdUsedSlvPorts:  32'd1,
        UniqueIds:          1'b0,
        AxiAddrWidth:       ADDR_WIDTH,
        AxiDataWidth:       DATA_WIDTH,
        NoAddrRules:        32'd1
    };

    // Internal interface array for the crossbar ports [cite: 136]
    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH)) master_ifs [NUM_MASTERS-1:0] ();

    // Map the external AXI bundles to the internal interface array [cite: 136]
    `AXI_LITE_ASSIGN(master_ifs[0], cgra_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[1], fpga_axi_i)

    // Define the address range for the 256-byte DTCM [cite: 137-138]
    axi_pkg::xbar_rule_32_t [0:0] routing_rules;
    always_comb begin
        routing_rules[0].idx        = 0;
        routing_rules[0].start_addr = 32'h0000_0000;
        routing_rules[0].end_addr   = 32'h0000_0100; // 256 bytes
    end

    // Slave interface array (only 1 slave for now) [cite: 138]
    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH)) dtcm_if_array [0:0] ();

    // Instantiate the synthesizable AXI-Lite Crossbar IP [cite: 139-141]
    axi_lite_xbar_intf #(
        .Cfg    ( XBAR_CFG ),
        .rule_t ( axi_pkg::xbar_rule_32_t )
    ) i_8bit_xbar (
        .clk_i                 ( clk_i          ),
        .rst_ni                ( rst_ni         ),
        .test_i                ( 1'b0           ), // test_i removed/tied low
        .slv_ports             ( master_ifs     ),
        .mst_ports             ( dtcm_if_array  ),
        .addr_map_i            ( routing_rules  ),
        .en_default_mst_port_i ( '0             ),
        .default_mst_port_i    ( '0             )
    );

    // Final assignment to the external DTCM slave port [cite: 142]
    `AXI_LITE_ASSIGN(dtcm_axi_o, dtcm_if_array[0])

endmodule