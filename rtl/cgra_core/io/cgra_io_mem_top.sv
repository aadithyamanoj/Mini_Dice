// =============================================================================
// cgra_io_mem_top.sv
//
// Top-level integration module connecting:
//
//   1. io_rx_tx_adapter      — link ↔ 16-bit flit converter (CGRA master path)
//   2. flit_axil_bridge      — LEN-framed flit ↔ AXI-Lite bridge
//   3. cgra_mem_system_16bit — 4-to-2 AXI-Lite crossbar + CSR bank + FPGA SRAM
//
// Data flow:
//
//   CGRA master (link words) ──► io_rx_tx_adapter (link side)
//                                     │  phy_rx_v / phy_rx_data / phy_rx_ready
//                                     ▼
//                               flit_axil_bridge ──► data_fetch_axi ──►┐
//                                     │  phy_tx_v / phy_tx_data / phy_tx_ready
//                                     ◄─────────────────────────────────┘
//                               cgra_mem_system_16bit
//                                     ▲
//   FPGA master (AXI-Lite) ──────────►  fpga_axi_i  (CSR writes / SRAM debug)
//
// Single-adapter constraint:
//   Only one physical 16-bit link exists (pin-budget limited to 16-bit in +
//   16-bit out).  All chip-side traffic (bitstream, metadata, data fetch)
//   serialises through this one link.  The crossbar's bitstream_fetch and
//   metadata_fetch master ports are tied idle here; they remain in
//   cgra_mem_system_16bit for future use or when the pin budget grows.
//
// Exposed ports
// ─────────────────────────────────────────────────────────────────────────────
//   CGRA link  : link_rx_v_i / link_rx_data_i / link_rx_ready_o
//                link_tx_v_o / link_tx_data_o / link_tx_ready_i
//   FPGA AXI   : flat AXI-Lite pins
// =============================================================================

`include "axi/typedef.svh"
`include "axi/assign.svh"

module cgra_io_mem_top #(
    parameter int ADDR_WIDTH    = 16,
    parameter int DATA_WIDTH    = 16,
    parameter int FLIT_WIDTH    = 16,
    parameter int LINK_WIDTH    = 16,
    parameter int RX_FIFO_ELS   = 16,
    parameter int TX_FIFO_ELS   = 16,
    parameter int CSR_NUM_REGS  = 8,
    parameter int MEM_NUM_WORDS = 1024
)(
    input  logic clk_i,
    input  logic rst_i,

    // ---- CGRA master link interface ----------------------------------------
    // The CGRA master drives link_rx_* and receives link_tx_*.
    // Internally this feeds io_rx_tx_adapter link side.
    input  logic                  link_rx_v_i,
    input  logic [LINK_WIDTH-1:0] link_rx_data_i,
    output logic                  link_rx_ready_o,

    output logic                  link_tx_v_o,
    output logic [LINK_WIDTH-1:0] link_tx_data_o,
    input  logic                  link_tx_ready_i,

    // ---- FPGA AXI-Lite master (CSR writes, SRAM reads/writes) --------------
    input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_aw_addr,
    input  logic [2:0]                fpga_axi_i_aw_prot,
    input  logic                      fpga_axi_i_aw_valid,
    output logic                      fpga_axi_i_aw_ready,
    input  logic [DATA_WIDTH-1:0]     fpga_axi_i_w_data,
    input  logic [(DATA_WIDTH/8)-1:0] fpga_axi_i_w_strb,
    input  logic                      fpga_axi_i_w_valid,
    output logic                      fpga_axi_i_w_ready,
    output logic [1:0]                fpga_axi_i_b_resp,
    output logic                      fpga_axi_i_b_valid,
    input  logic                      fpga_axi_i_b_ready,
    input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_ar_addr,
    input  logic [2:0]                fpga_axi_i_ar_prot,
    input  logic                      fpga_axi_i_ar_valid,
    output logic                      fpga_axi_i_ar_ready,
    output logic [DATA_WIDTH-1:0]     fpga_axi_i_r_data,
    output logic [1:0]                fpga_axi_i_r_resp,
    output logic                      fpga_axi_i_r_valid,
    input  logic                      fpga_axi_i_r_ready
);

    // Internal PHY wires (between io_rx_tx_adapter and flit_axil_bridge)
    // -------------------------------------------------------------------------
    logic                  phy_rx_v;
    logic [FLIT_WIDTH-1:0] phy_rx_data;
    logic                  phy_rx_ready;

    logic                  phy_tx_v;
    logic [FLIT_WIDTH-1:0] phy_tx_data;
    logic                  phy_tx_ready;

    AXI_LITE #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH)
    ) fpga_axi_i ();

    assign fpga_axi_i.aw_addr  = fpga_axi_i_aw_addr;
    assign fpga_axi_i.aw_prot  = fpga_axi_i_aw_prot;
    assign fpga_axi_i.aw_valid = fpga_axi_i_aw_valid;
    assign fpga_axi_i_aw_ready = fpga_axi_i.aw_ready;

    assign fpga_axi_i.w_data   = fpga_axi_i_w_data;
    assign fpga_axi_i.w_strb   = fpga_axi_i_w_strb;
    assign fpga_axi_i.w_valid  = fpga_axi_i_w_valid;
    assign fpga_axi_i_w_ready  = fpga_axi_i.w_ready;

    assign fpga_axi_i_b_resp   = fpga_axi_i.b_resp;
    assign fpga_axi_i_b_valid  = fpga_axi_i.b_valid;
    assign fpga_axi_i.b_ready  = fpga_axi_i_b_ready;

    assign fpga_axi_i.ar_addr  = fpga_axi_i_ar_addr;
    assign fpga_axi_i.ar_prot  = fpga_axi_i_ar_prot;
    assign fpga_axi_i.ar_valid = fpga_axi_i_ar_valid;
    assign fpga_axi_i_ar_ready = fpga_axi_i.ar_ready;

    assign fpga_axi_i_r_data   = fpga_axi_i.r_data;
    assign fpga_axi_i_r_resp   = fpga_axi_i.r_resp;
    assign fpga_axi_i_r_valid  = fpga_axi_i.r_valid;
    assign fpga_axi_i.r_ready  = fpga_axi_i_r_ready;

    // -------------------------------------------------------------------------
    // AXI-Lite interface: flit_axil_bridge → data_fetch port on the crossbar
    // -------------------------------------------------------------------------
    AXI_LITE #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH)
    ) cgra_data_axi ();
    
    // Flat wires driven by flit_axil_bridge (master outputs)
    logic [ADDR_WIDTH-1:0]         fab_awaddr;
    logic [2:0]                    fab_awprot;
    logic                          fab_awvalid;
    logic [DATA_WIDTH-1:0]         fab_wdata;
    logic [(DATA_WIDTH/8)-1:0]     fab_wstrb;
    logic                          fab_wvalid;
    logic                          fab_bready;
    logic [ADDR_WIDTH-1:0]         fab_araddr;
    logic [2:0]                    fab_arprot;
    logic                          fab_arvalid;
    logic                          fab_rready;

    // Drive AXI_LITE master-direction signals from flit_axil_bridge outputs
    assign cgra_data_axi.aw_addr  = fab_awaddr;
    assign cgra_data_axi.aw_prot  = fab_awprot;
    assign cgra_data_axi.aw_valid = fab_awvalid;
    assign cgra_data_axi.w_data   = fab_wdata;
    assign cgra_data_axi.w_strb   = fab_wstrb;
    assign cgra_data_axi.w_valid  = fab_wvalid;
    assign cgra_data_axi.b_ready  = fab_bready;
    assign cgra_data_axi.ar_addr  = fab_araddr;
    assign cgra_data_axi.ar_prot  = fab_arprot;
    assign cgra_data_axi.ar_valid = fab_arvalid;
    assign cgra_data_axi.r_ready  = fab_rready;

    // -------------------------------------------------------------------------
    // Idle stubs for the two crossbar master ports that have no physical link.
    // bitstream_fetch and metadata_fetch are reserved for future expansion
    // (or a larger pin budget).  Tie all valid/addr/data signals low; accept
    // all responses immediately so the crossbar never deadlocks.
    // -------------------------------------------------------------------------
    AXI_LITE #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH)
    ) bs_idle_axi ();

    AXI_LITE #(
        .AXI_ADDR_WIDTH (ADDR_WIDTH),
        .AXI_DATA_WIDTH (DATA_WIDTH)
    ) md_idle_axi ();

    assign bs_idle_axi.aw_valid = 1'b0;
    assign bs_idle_axi.aw_addr  = '0;
    assign bs_idle_axi.aw_prot  = '0;
    assign bs_idle_axi.w_valid  = 1'b0;
    assign bs_idle_axi.w_data   = '0;
    assign bs_idle_axi.w_strb   = '0;
    assign bs_idle_axi.b_ready  = 1'b1;
    assign bs_idle_axi.ar_valid = 1'b0;
    assign bs_idle_axi.ar_addr  = '0;
    assign bs_idle_axi.ar_prot  = '0;
    assign bs_idle_axi.r_ready  = 1'b1;

    assign md_idle_axi.aw_valid = 1'b0;
    assign md_idle_axi.aw_addr  = '0;
    assign md_idle_axi.aw_prot  = '0;
    assign md_idle_axi.w_valid  = 1'b0;
    assign md_idle_axi.w_data   = '0;
    assign md_idle_axi.w_strb   = '0;
    assign md_idle_axi.b_ready  = 1'b1;
    assign md_idle_axi.ar_valid = 1'b0;
    assign md_idle_axi.ar_addr  = '0;
    assign md_idle_axi.ar_prot  = '0;
    assign md_idle_axi.r_ready  = 1'b1;

    // -------------------------------------------------------------------------
    // io_rx_tx_adapter
    // Converts link-side valid/data words ↔ internal 16-bit flits.
    // -------------------------------------------------------------------------
    io_rx_tx_adapter #(
        .flit_width_p      (FLIT_WIDTH),
        .link_word_width_p (LINK_WIDTH),
        .rx_fifo_els_p     (RX_FIFO_ELS),
        .tx_fifo_els_p     (TX_FIFO_ELS)
    ) u_io_adapter (
        .clk_i           (clk_i),
        .reset_i         (rst_i),
        .link_rx_v_i     (link_rx_v_i),
        .link_rx_data_i  (link_rx_data_i),
        .link_rx_ready_o (link_rx_ready_o),
        .link_tx_v_o     (link_tx_v_o),
        .link_tx_data_o  (link_tx_data_o),
        .link_tx_ready_i (link_tx_ready_i),
        .phy_rx_v_o      (phy_rx_v),
        .phy_rx_data_o   (phy_rx_data),
        .phy_rx_ready_i  (phy_rx_ready),
        .phy_tx_v_i      (phy_tx_v),
        .phy_tx_data_i   (phy_tx_data),
        .phy_tx_ready_o  (phy_tx_ready)
    );

    // -------------------------------------------------------------------------
    // flit_axil_bridge
    // Converts LEN-framed 16-bit flit packets (from CGRA link) into AXI-Lite
    // master transactions, and packetizes AXI-Lite responses back into flits.
    // Drives the data_fetch master port of the cgra_mem_system_16bit crossbar.
    // -------------------------------------------------------------------------
    flit_axil_bridge #(
        .flit_width_p      (FLIT_WIDTH),
        .axil_addr_width_p (ADDR_WIDTH),
        .axil_data_width_p (DATA_WIDTH)
    ) u_bridge (
        .clk_i             (clk_i),
        .rst_i             (rst_i),

        // Flit RX from adapter
        .phy_rx_v_i        (phy_rx_v),
        .phy_rx_data_i     (phy_rx_data),
        .phy_rx_ready_o    (phy_rx_ready),

        // Flit TX to adapter
        .phy_tx_v_o        (phy_tx_v),
        .phy_tx_data_o     (phy_tx_data),
        .phy_tx_ready_i    (phy_tx_ready),

        // AXI-Lite master outputs (wired to cgra_data_axi via fab_* signals)
        .m_axil_awaddr_o   (fab_awaddr),
        .m_axil_awprot_o   (fab_awprot),
        .m_axil_awvalid_o  (fab_awvalid),
        .m_axil_awready_i  (cgra_data_axi.aw_ready),

        .m_axil_wdata_o    (fab_wdata),
        .m_axil_wstrb_o    (fab_wstrb),
        .m_axil_wvalid_o   (fab_wvalid),
        .m_axil_wready_i   (cgra_data_axi.w_ready),

        .m_axil_bresp_i    (cgra_data_axi.b_resp),
        .m_axil_bvalid_i   (cgra_data_axi.b_valid),
        .m_axil_bready_o   (fab_bready),

        .m_axil_araddr_o   (fab_araddr),
        .m_axil_arprot_o   (fab_arprot),
        .m_axil_arvalid_o  (fab_arvalid),
        .m_axil_arready_i  (cgra_data_axi.ar_ready),

        .m_axil_rdata_i    (cgra_data_axi.r_data),
        .m_axil_rresp_i    (cgra_data_axi.r_resp),
        .m_axil_rvalid_i   (cgra_data_axi.r_valid),
        .m_axil_rready_o   (fab_rready)
    );

    // -------------------------------------------------------------------------
    // cgra_mem_system_16bit
    // 4-master, 2-slave AXI-Lite crossbar.
    //   Master [0] = fpga_axi_i    → CSR writes / SRAM debug (active, off-chip)
    //   Master [1] = bs_idle_axi   → tied idle (single-link constraint)
    //   Master [2] = md_idle_axi   → tied idle (single-link constraint)
    //   Master [3] = cgra_data_axi → all chip-side flit traffic via bridge
    //
    //   Slave  [0] = CSR bank      → on-chip, 0x0000–0x00FF
    //   Slave  [1] = FPGA SRAM     → off-chip, 0x0800–0x0FFF
    // -------------------------------------------------------------------------
    cgra_mem_system_16bit #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .CSR_NUM_REGS  (CSR_NUM_REGS),
        .MEM_NUM_WORDS (MEM_NUM_WORDS)
    ) u_mem_sys (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),
        .fpga_axi_i            (fpga_axi_i),
        .bitstream_fetch_axi_i (bs_idle_axi),   // tied idle — single-link constraint
        .metadata_fetch_axi_i  (md_idle_axi),   // tied idle — single-link constraint
        .data_fetch_axi_i      (cgra_data_axi)
    );

endmodule
