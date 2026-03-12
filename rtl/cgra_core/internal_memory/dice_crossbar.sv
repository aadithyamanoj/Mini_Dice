`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "dice_pkg.sv"

// 9-master AXI-Lite crossbar to single DTCM slave.
// Masters [7:0] = 8 CGRA boundary ports (top row [3:0], bottom row [7:4])
// Master  [8]   = FPGA
// Slave         = DTCM (via axi_lite_dtcm_wrap in dice_core)
module dice_crossbar
import dice_pkg::*;
#(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int NUM_MASTERS = 9
)(
    input  logic clk_i,
    input  logic rst_ni,

    // CGRA boundary masters — top row [3:0], bottom row [7:4]
    AXI_LITE.Slave  cgra_0_axi_i,
    AXI_LITE.Slave  cgra_1_axi_i,
    AXI_LITE.Slave  cgra_2_axi_i,
    AXI_LITE.Slave  cgra_3_axi_i,
    AXI_LITE.Slave  cgra_4_axi_i,
    AXI_LITE.Slave  cgra_5_axi_i,
    AXI_LITE.Slave  cgra_6_axi_i,
    AXI_LITE.Slave  cgra_7_axi_i,

    // FPGA master
    AXI_LITE.Slave  fpga_axi_i,

    // Single DTCM slave
    AXI_LITE.Master dtcm_axi_o
);

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

    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH)) master_ifs [NUM_MASTERS-1:0] ();

    `AXI_LITE_ASSIGN(master_ifs[0], cgra_0_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[1], cgra_1_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[2], cgra_2_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[3], cgra_3_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[4], cgra_4_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[5], cgra_5_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[6], cgra_6_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[7], cgra_7_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[8], fpga_axi_i)

    axi_pkg::xbar_rule_32_t [0:0] routing_rules;
    always_comb begin
        routing_rules[0].idx        = 0;
        routing_rules[0].start_addr = 32'h0000_0000;
        routing_rules[0].end_addr   = 32'h0000_03FF;  // 1 KB DTCM
    end

    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH)) dtcm_if_array [0:0] ();

    axi_lite_xbar_intf #(
        .Cfg    ( XBAR_CFG ),
        .rule_t ( axi_pkg::xbar_rule_32_t )
    ) i_main_xbar (
        .clk_i                 ( clk_i          ),
        .rst_ni                ( rst_ni          ),
        .test_i                ( 1'b0            ),
        .slv_ports             ( master_ifs      ),
        .mst_ports             ( dtcm_if_array   ),
        .addr_map_i            ( routing_rules   ),
        .en_default_mst_port_i ( '0              ),
        .default_mst_port_i    ( '0              )
    );

    `AXI_LITE_ASSIGN(dtcm_axi_o, dtcm_if_array[0])

endmodule
