`include "axi/typedef.svh"
`include "axi/assign.svh"

// CGRA memory system: 4 AXI-Lite masters, 2 AXI-Lite slaves.
//
// Masters (slave ports on the crossbar):
//   [0] FPGA          — off-chip, configuration/debug master
//   [1] Bitstream_fetch — on-chip DMA for bitstream loading
//   [2] Metadata_fetch  — on-chip DMA for metadata loading
//   [3] Data_fetch      — on-chip DMA for data loading
//
// Slaves (master ports on the crossbar):
//   [0] CSRs       — on-chip, 0x0000_0000 – 0x0000_00FF  (16 x 16-bit regs)
//   [1] FPGA Memory — off-chip, 0x0001_0000 – 0x0001_FFFF (16-bit SRAM)
//
// The crossbar (axi_lite_xbar) uses round-robin arbitration at each slave
// port (via rr_arb_tree in axi_lite_mux), giving fair access for all 4 masters.
//
// Both FPGA and FPGA Memory ports are annotated off-chip; the CSR slave and
// the three fetch masters are on-chip.

module cgra_mem_system_16bit #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 16,
    parameter int NUM_MASTERS = 4,
    parameter int NUM_SLAVES  = 2,
    parameter int CSR_NUM_REGS  = 8,
    parameter int MEM_NUM_WORDS = 1024
)(
    input  logic clk_i,
    input  logic rst_i,

    // ---- Masters (off-chip / on-chip as noted) ----
    AXI_LITE.Slave  fpga_axi_i,            // off-chip FPGA master
    AXI_LITE.Slave  bitstream_fetch_axi_i, // on-chip
    AXI_LITE.Slave  metadata_fetch_axi_i,  // on-chip
    AXI_LITE.Slave  data_fetch_axi_i       // on-chip
    // Slave wrappers (CSR bank + FPGA SRAM) are instantiated internally.
    // Use hierarchical references (dut.i_csr_wrap / dut.i_mem_wrap) to observe
    // slave-side signals in simulation.
);

    // -------------------------------------------------------------------------
    // Crossbar configuration
    // -------------------------------------------------------------------------
    localparam axi_pkg::xbar_cfg_t XBAR_CFG = '{
        NoSlvPorts:         NUM_MASTERS,
        NoMstPorts:         NUM_SLAVES,
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
        NoAddrRules:        32'd2
    };

    // -------------------------------------------------------------------------
    // Internal interface arrays
    // -------------------------------------------------------------------------
    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH))
        master_ifs [NUM_MASTERS-1:0] ();

    `AXI_LITE_ASSIGN(master_ifs[0], fpga_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[1], bitstream_fetch_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[2], metadata_fetch_axi_i)
    `AXI_LITE_ASSIGN(master_ifs[3], data_fetch_axi_i)

    AXI_LITE #(.AXI_ADDR_WIDTH(ADDR_WIDTH), .AXI_DATA_WIDTH(DATA_WIDTH))
        slave_ifs [NUM_SLAVES-1:0] ();

    // -------------------------------------------------------------------------
    // Address routing rules
    //   Slave 0: CSRs       0x0000_0000 – 0x0000_0100
    //   Slave 1: FPGA mem   0x0001_0000 – 0x0002_0000
    // -------------------------------------------------------------------------
    axi_pkg::xbar_rule_32_t [1:0] routing_rules;
    always_comb begin
        routing_rules[0].idx        = 32'd0;
        routing_rules[0].start_addr = 32'h0000_0000;
        routing_rules[0].end_addr   = 32'h0000_0100;  // 256 bytes = 128 x 16-bit regs

        routing_rules[1].idx        = 32'd1;
        routing_rules[1].start_addr = 32'h0001_0000;
        routing_rules[1].end_addr   = 32'h0002_0000;  // 64 KB FPGA SRAM window
    end

    // -------------------------------------------------------------------------
    // Crossbar
    // -------------------------------------------------------------------------
    axi_lite_xbar_intf #(
        .Cfg    ( XBAR_CFG                ),
        .rule_t ( axi_pkg::xbar_rule_32_t )
    ) i_xbar (
        .clk_i                 ( clk_i        ),
        .rst_ni                ( ~rst_i       ),
        .test_i                ( 1'b0         ),
        .slv_ports             ( master_ifs   ),
        .mst_ports             ( slave_ifs    ),
        .addr_map_i            ( routing_rules),
        .en_default_mst_port_i ( '0           ),
        .default_mst_port_i    ( '0           )
    );

    // -------------------------------------------------------------------------
    // Slave 0: on-chip CSR bank — wired directly to slave_ifs[0]
    // -------------------------------------------------------------------------
    axi_lite_csr_wrap_16bit #(
        .ADDR_WIDTH ( ADDR_WIDTH   ),
        .DATA_WIDTH ( DATA_WIDTH   ),
        .NUM_REGS   ( CSR_NUM_REGS )
    ) i_csr_wrap (
        .clk_i  ( clk_i          ),
        .rst_i  ( rst_i          ),
        .axi_i  ( slave_ifs[0]   )
    );

    // -------------------------------------------------------------------------
    // Slave 1: off-chip FPGA SRAM (simulated) — wired directly to slave_ifs[1]
    // -------------------------------------------------------------------------
    axi_lite_fpgamem_wrap_16bit #(
        .ADDR_WIDTH ( ADDR_WIDTH    ),
        .DATA_WIDTH ( DATA_WIDTH    ),
        .NUM_WORDS  ( MEM_NUM_WORDS )
    ) i_mem_wrap (
        .clk_i  ( clk_i          ),
        .rst_i  ( rst_i          ),
        .axi_i  ( slave_ifs[1]   )
    );

endmodule
