// =============================================================================
// mini_dice_top.sv
//
// Top-level integration of dice_core + cgra_io_axi4_top + cgra_io_csr.
//
// Connections:
//   FPGA AXI4 → crossbar → fpga_mem → external bsg_link DDR → FPGA SRAM
//   FPGA AXI4 → crossbar → cgra_csr → cgra_io_csr
//   cgra_io_csr regs 0-7  → cta_if (start/start_pc) + boundary (cgra_reset, bsload_en)
//   cgra_io_csr regs 8-15 → dice_core csrX0-7 (kernel arguments)
//   dice_core mfetch/bsfetch (slv_req_t) → crossbar
//   dice_core axi_* (dfetch) → crossbar
//
// grid_size is tied to a single-CTA default for now. Thread count is
// host-programmable through the CSR bank so smaller CTAs can be launched.
// =============================================================================

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module mini_dice_top
  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;
#(
    parameter int ADDR_WIDTH             = 16,
    parameter int DATA_WIDTH             = 32,
    parameter int FLIT_WIDTH             = 32,
    parameter int CHANNEL_WIDTH          = 8,
    parameter int LG_FIFO_DEPTH          = 6,
    parameter int LG_CREDIT_TO_TOKEN_DEC = 3,
    parameter int BYPASS_TWOFER_FIFO     = 0,
    parameter int BYPASS_GEARBOX         = 1,
    parameter int USE_HARDENED_FIFO      = 0
) (
    input logic clk_i,
    input logic rst_i,

    // FPGA AXI4 full master (flat pins from host) — fpga_mst crossbar port
    // input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_aw_addr,
    // input  logic [2:0]                fpga_axi_i_aw_prot,
    // input  logic                      fpga_axi_i_aw_valid,
    // output logic                      fpga_axi_i_aw_ready,

    // input  logic [DATA_WIDTH-1:0]     fpga_axi_i_w_data,
    // input  logic [(DATA_WIDTH/8)-1:0] fpga_axi_i_w_strb,
    // input  logic                      fpga_axi_i_w_valid,
    // output logic                      fpga_axi_i_w_ready,

    // output logic [1:0]                fpga_axi_i_b_resp,
    // output logic                      fpga_axi_i_b_valid,
    // input  logic                      fpga_axi_i_b_ready,

    // input  logic [ADDR_WIDTH-1:0]     fpga_axi_i_ar_addr,
    // input  logic [2:0]                fpga_axi_i_ar_prot,
    // input  logic                      fpga_axi_i_ar_valid,
    // output logic                      fpga_axi_i_ar_ready,

    // output logic [DATA_WIDTH-1:0]     fpga_axi_i_r_data,
    // output logic [1:0]                fpga_axi_i_r_resp,
    // output logic                      fpga_axi_i_r_valid,
    // input  logic                      fpga_axi_i_r_ready,

    // Core-side stream from the external bsg_link wrapper.
    input  logic [FLIT_WIDTH-1:0] link_rx_data_i,
    input  logic                  link_rx_valid_i,
    output logic                  link_rx_yumi_o,

    // Core-side stream to the external bsg_link wrapper.
    output logic [FLIT_WIDTH-1:0] link_tx_data_o,
    output logic                  link_tx_valid_o,
    input  logic                  link_tx_ready_i,

    // CGRA scan chain / bitstream outputs
    output logic cgra_prog_dout_o,
    output logic cgra_prog_we_o,

    // CSR control outputs not yet wired to dice_core internals
    output logic csr_cgra_reset_o,
    output logic csr_bsload_en_o
);

  // --------------------------------------------------------------------------
  // Internal wires
  // --------------------------------------------------------------------------
  slv_req_t mfetch_req, bsfetch_req;
  slv_resp_t mfetch_resp, bsfetch_resp;

  mst_req_t  csr_req;
  mst_resp_t csr_resp;

  // dfetch flat AXI4 (dice_core LDST FIFO → cgra_io_axi4_top)
  logic [NUM_MEM_PORTS-1:0][DICE_REG_DATA_WIDTH-1:0] dfetch_awaddr, dfetch_araddr;
  logic [NUM_MEM_PORTS-1:0][AxiUserWidth-1:0] dfetch_aruser;
  logic [NUM_MEM_PORTS-1:0][DICE_REG_DATA_WIDTH-1:0] dfetch_wdata;
  logic [DATA_WIDTH-1:0] dfetch_rdata;
  logic [NUM_MEM_PORTS-1:0][1:0] dfetch_wstrb, dfetch_bresp;
  logic [1:0] dfetch_rresp;
  logic [NUM_MEM_PORTS-1:0] dfetch_awvalid, dfetch_awready;
  logic [NUM_MEM_PORTS-1:0] dfetch_wvalid, dfetch_wready;
  logic [NUM_MEM_PORTS-1:0] dfetch_bvalid, dfetch_bready;
  logic [NUM_MEM_PORTS-1:0] dfetch_arvalid, dfetch_arready;
  logic dfetch_rvalid, dfetch_rready;

  logic [NUM_MEM_PORTS-1:0][DATA_WIDTH-1:0] dfetch_awaddr_axi, dfetch_araddr_axi;
  logic [NUM_MEM_PORTS-1:0][DATA_WIDTH-1:0] dfetch_wdata_axi;
  logic [DATA_WIDTH-1:0] dfetch_rdata_axi;

  for (genvar dfetch_i = 0; dfetch_i < NUM_MEM_PORTS; dfetch_i++) begin : gen_dfetch_widen
    assign dfetch_awaddr_axi[dfetch_i] = DATA_WIDTH'(dfetch_awaddr[dfetch_i]);
    assign dfetch_araddr_axi[dfetch_i] = DATA_WIDTH'(dfetch_araddr[dfetch_i]);
    assign dfetch_wdata_axi[dfetch_i]  = DATA_WIDTH'(dfetch_wdata[dfetch_i]);
  end
  assign dfetch_rdata = dfetch_rdata_axi;

  // CSR outputs
  logic                           csr_start;
  logic [                   15:0] csr_start_pc;
  logic [                   15:0] csr_thread_count;

  // csrX kernel arguments: cgra_io_csr regs 8-15 → dice_core
  logic [DICE_REG_DATA_WIDTH-1:0] csrX              [8];
  logic                           cta_complete_fire;

  // Legacy flat FPGA AXI4 host interface is no longer consumed by
  // cgra_io_axi4_top; FPGA-originated traffic now enters through bsg_link RX.
  // assign fpga_axi_i_aw_ready = 1'b0;
  // assign fpga_axi_i_w_ready  = 1'b0;
  // assign fpga_axi_i_b_resp   = RESP_OKAY;
  // assign fpga_axi_i_b_valid  = 1'b0;
  // assign fpga_axi_i_ar_ready = 1'b0;
  // assign fpga_axi_i_r_data   = '0;
  // assign fpga_axi_i_r_resp   = RESP_OKAY;
  // assign fpga_axi_i_r_valid  = 1'b0;

  // --------------------------------------------------------------------------
  // cta_if — internal; driven from cgra_io_csr launch outputs.
  // grid_size and cta_id remain single-CTA defaults for now.
  // --------------------------------------------------------------------------
  cta_if u_cta_if ();

  always_comb begin
    u_cta_if.dispatch_valid                         = csr_start;
    u_cta_if.dispatch_data                          = '0;
    u_cta_if.dispatch_data.kernel_desc.start_pc     = DICE_ADDR_WIDTH'(csr_start_pc);
    u_cta_if.dispatch_data.kernel_desc.grid_size.x  = 1;
    u_cta_if.dispatch_data.kernel_desc.grid_size.y  = 1;
    u_cta_if.dispatch_data.kernel_desc.grid_size.z  = 1;
    u_cta_if.dispatch_data.kernel_desc.thread_count = csr_thread_count[DICE_TID_WIDTH:0];
    u_cta_if.complete_ready                         = 1'b1;
  end

  assign cta_complete_fire = u_cta_if.complete_valid && u_cta_if.complete_ready;

  // --------------------------------------------------------------------------
  // dice_core
  // --------------------------------------------------------------------------
  dice_core u_dice_core (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .cta_if_inst(u_cta_if),

      .mfetch_req_o  (mfetch_req),
      .mfetch_resp_i (mfetch_resp),
      .bsfetch_req_o (bsfetch_req),
      .bsfetch_resp_i(bsfetch_resp),

      .csrX0_i(csrX[0]),
      .csrX1_i(csrX[1]),
      .csrX2_i(csrX[2]),
      .csrX3_i(csrX[3]),
      .csrX4_i(csrX[4]),
      .csrX5_i(csrX[5]),
      .csrX6_i(csrX[6]),
      .csrX7_i(csrX[7]),

      .cgra_prog_dout_o(cgra_prog_dout_o),
      .cgra_prog_we_o  (cgra_prog_we_o),

      .axi_awaddr_o (dfetch_awaddr),
      .axi_awvalid_o(dfetch_awvalid),
      .axi_awready_i(dfetch_awready),
      .axi_wdata_o  (dfetch_wdata),
      .axi_wstrb_o  (dfetch_wstrb),
      .axi_wvalid_o (dfetch_wvalid),
      .axi_wready_i (dfetch_wready),
      .axi_bresp_i  (dfetch_bresp),
      .axi_bvalid_i (dfetch_bvalid),
      .axi_bready_o (dfetch_bready),
      .axi_araddr_o (dfetch_araddr),
      .axi_aruser_o (dfetch_aruser),
      .axi_arvalid_o(dfetch_arvalid),
      .axi_arready_i(dfetch_arready),
      .axi_rdata_i  (dfetch_rdata),
      .axi_rresp_i  (dfetch_rresp),
      .axi_rvalid_i (dfetch_rvalid),
      .axi_rready_o (dfetch_rready)
  );

  // --------------------------------------------------------------------------
  // cgra_io_axi4_top — crossbar + bsg_link IO
  // --------------------------------------------------------------------------
  cgra_io_axi4_top #(
      .ADDR_WIDTH            (ADDR_WIDTH),
      .DATA_WIDTH            (DATA_WIDTH),
      .FLIT_WIDTH            (FLIT_WIDTH),
      .CHANNEL_WIDTH         (CHANNEL_WIDTH),
      .LG_FIFO_DEPTH         (LG_FIFO_DEPTH),
      .LG_CREDIT_TO_TOKEN_DEC(LG_CREDIT_TO_TOKEN_DEC),
      .BYPASS_TWOFER_FIFO    (BYPASS_TWOFER_FIFO),
      .BYPASS_GEARBOX        (BYPASS_GEARBOX),
      .USE_HARDENED_FIFO     (USE_HARDENED_FIFO)
  ) u_io_top (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // Legacy flat FPGA AXI4 master ports on cgra_io_axi4_top are disabled.
      // .fpga_axi_i_aw_addr           ( fpga_axi_i_aw_addr           ),
      // .fpga_axi_i_aw_prot           ( fpga_axi_i_aw_prot           ),
      // .fpga_axi_i_aw_valid          ( fpga_axi_i_aw_valid          ),
      // .fpga_axi_i_aw_ready          ( fpga_axi_i_aw_ready          ),
      // .fpga_axi_i_w_data            ( fpga_axi_i_w_data            ),
      // .fpga_axi_i_w_strb            ( fpga_axi_i_w_strb            ),
      // .fpga_axi_i_w_valid           ( fpga_axi_i_w_valid           ),
      // .fpga_axi_i_w_ready           ( fpga_axi_i_w_ready           ),
      // .fpga_axi_i_b_resp            ( fpga_axi_i_b_resp            ),
      // .fpga_axi_i_b_valid           ( fpga_axi_i_b_valid           ),
      // .fpga_axi_i_b_ready           ( fpga_axi_i_b_ready           ),
      // .fpga_axi_i_ar_addr           ( fpga_axi_i_ar_addr           ),
      // .fpga_axi_i_ar_prot           ( fpga_axi_i_ar_prot           ),
      // .fpga_axi_i_ar_valid          ( fpga_axi_i_ar_valid          ),
      // .fpga_axi_i_ar_ready          ( fpga_axi_i_ar_ready          ),
      // .fpga_axi_i_r_data            ( fpga_axi_i_r_data            ),
      // .fpga_axi_i_r_resp            ( fpga_axi_i_r_resp            ),
      // .fpga_axi_i_r_valid           ( fpga_axi_i_r_valid           ),
      // .fpga_axi_i_r_ready           ( fpga_axi_i_r_ready           ),

      // mfetch / bsfetch from dice_core
      .mfetch_req_i  (mfetch_req),
      .mfetch_resp_o (mfetch_resp),
      .bsfetch_req_i (bsfetch_req),
      .bsfetch_resp_o(bsfetch_resp),

      // dfetch from dice_core LDST FIFO
      .dfetch_awaddr_i (dfetch_awaddr_axi),
      .dfetch_awvalid_i(dfetch_awvalid),
      .dfetch_awready_o(dfetch_awready),
      .dfetch_wdata_i  (dfetch_wdata_axi),
      .dfetch_wstrb_i  (dfetch_wstrb),
      .dfetch_wvalid_i (dfetch_wvalid),
      .dfetch_wready_o (dfetch_wready),
      .dfetch_bresp_o  (dfetch_bresp),
      .dfetch_bvalid_o (dfetch_bvalid),
      .dfetch_bready_i (dfetch_bready),
      .dfetch_araddr_i (dfetch_araddr_axi),
      .dfetch_aruser_i (dfetch_aruser),
      .dfetch_arvalid_i(dfetch_arvalid),
      .dfetch_arready_o(dfetch_arready),
      .dfetch_rdata_o  (dfetch_rdata_axi),
      .dfetch_rresp_o  (dfetch_rresp),
      .dfetch_rvalid_o (dfetch_rvalid),
      .dfetch_rready_i (dfetch_rready),

      // Core-side bsg_link streams
      .link_rx_data_i (link_rx_data_i),
      .link_rx_valid_i(link_rx_valid_i),
      .link_rx_yumi_o (link_rx_yumi_o),
      .link_tx_data_o (link_tx_data_o),
      .link_tx_valid_o(link_tx_valid_o),
      .link_tx_ready_i(link_tx_ready_i),

      // CSR slave port
      .cgra_csr_req_o (csr_req),
      .cgra_csr_resp_i(csr_resp)
  );

  // --------------------------------------------------------------------------
  // cgra_io_csr — AXI4 CSR bank on the crossbar cgra_csr port
  // --------------------------------------------------------------------------
  cgra_io_csr u_csr (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .axi_req_i (csr_req),
      .axi_resp_o(csr_resp),

      // Regs 0-7: control outputs
      .start_o       (csr_start),
      .start_pc_o    (csr_start_pc),
      .thread_count_o(csr_thread_count),
      .cgra_reset_o  (csr_cgra_reset_o),
      .bsload_en_o   (csr_bsload_en_o),

      // hw_* status exposed through CSR STATUS.
      .hw_busy_i          (1'b0),
      .hw_complete_i      (cta_complete_fire),
      .hw_dispatching_i   (1'b0),
      .hw_stack_overflow_i(1'b0),
      .hw_stack_depth_i   ('0),
      .hw_error_info_i    ('0),
      .hw_bsload_cnt_i    ('0),

      // Regs 8-15: kernel argument outputs → dice_core csrX inputs
      .csrX0_o(csrX[0]),
      .csrX1_o(csrX[1]),
      .csrX2_o(csrX[2]),
      .csrX3_o(csrX[3]),
      .csrX4_o(csrX[4]),
      .csrX5_o(csrX[5]),
      .csrX6_o(csrX[6]),
      .csrX7_o(csrX[7])
  );

endmodule : mini_dice_top
