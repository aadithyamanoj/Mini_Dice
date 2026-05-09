module dice_core
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    // AXI4 read master ports to the fetch memory system
    output slv_req_t  mfetch_req_o,
    input  slv_resp_t mfetch_resp_i,
    output slv_req_t  bsfetch_req_o,
    input  slv_resp_t bsfetch_resp_i,

    // Input-only CSR sources exposed to the CGRA input crossbar
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX1_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX2_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX3_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX5_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX6_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX7_i,

    // CGRA scan chain / bitstream outputs
    output logic cgra_prog_dout_o,
    output logic cgra_prog_we_o,

    // Hardware status outputs → cgra_io_csr
    output logic        hw_busy_o,
    output logic        dispatch_busy_o,
    output logic [15:0] bsload_cnt_o,
    output logic        stack_overflow_o,
    output logic [15:0] stack_depth_o,
    output logic [15:0] stack_error_pc_o,

    // AXI-Lite master interface from LDST FIFO
    output logic [NUM_MEM_PORTS-1:0][DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o,
    output logic [NUM_MEM_PORTS-1:0]                          axi_awvalid_o,
    input  logic [NUM_MEM_PORTS-1:0]                          axi_awready_i,
    output logic [NUM_MEM_PORTS-1:0][DICE_REG_DATA_WIDTH-1:0] axi_wdata_o,
    output logic [NUM_MEM_PORTS-1:0][1:0]                     axi_wstrb_o,
    output logic [NUM_MEM_PORTS-1:0]                          axi_wvalid_o,
    input  logic [NUM_MEM_PORTS-1:0]                          axi_wready_i,
    input  logic [NUM_MEM_PORTS-1:0][1:0]                     axi_bresp_i,
    input  logic [NUM_MEM_PORTS-1:0]                          axi_bvalid_i,
    output logic [NUM_MEM_PORTS-1:0]                          axi_bready_o,
    output logic [NUM_MEM_PORTS-1:0][DICE_REG_DATA_WIDTH-1:0] axi_araddr_o,
    output logic [NUM_MEM_PORTS-1:0][AxiUserWidth-1:0]        axi_aruser_o,
    output logic [NUM_MEM_PORTS-1:0]                          axi_arvalid_o,
    input  logic [NUM_MEM_PORTS-1:0]                          axi_arready_i,
    input  logic [AxiDataWidth-1:0]                           axi_rdata_i,
    input  logic [1:0]                                        axi_rresp_i,
    input  logic                                              axi_rvalid_i,
    output logic                                              axi_rready_o
);

  // =========================================================================
  // Internal interfaces
  // =========================================================================
  fdr_if fdr_out_if ();

  // Backend -> Frontend commit feedback
  logic bct_pop_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] bct_pop_e_block_id;
  logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] frontend_pred_regs;
  block_retire_status_t frontend_brt_info;
  logic hw_cta_pending_lo;
  logic cm_wr_buffer_lo;
  logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_lo;
  logic [AxiDataWidth-1:0] cm_wr_data_lo;
  logic cm_wr_valid_lo;
  logic prog_active_lo;
  logic prog_active_buffer_lo;


  assign frontend_brt_info.has_pending_eblock = hw_cta_pending_lo;
  assign hw_busy_o = hw_cta_pending_lo;

  // =========================================================================
  // Frontend — CTA scheduler + FDR
  // =========================================================================
  dice_frontend u_dice_frontend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .cta_if_inst   (cta_if_inst),
      .mfetch_req_o  (mfetch_req_o),
      .mfetch_resp_i (mfetch_resp_i),
      .bsfetch_req_o (bsfetch_req_o),
      .bsfetch_resp_i(bsfetch_resp_i),

      .fdr_if_o      (fdr_out_if),
      .cm_wr_buffer_o(cm_wr_buffer_lo),
      .cm_wr_addr_o  (cm_wr_addr_lo),
      .cm_wr_data_o  (cm_wr_data_lo),
      .cm_wr_valid_o (cm_wr_valid_lo),
      .pred_regs_i   (frontend_pred_regs),
      .prog_active_i (prog_active_lo),
      .prog_active_buffer_i(prog_active_buffer_lo),

      .eblock_commit_valid_i  (bct_pop_valid),
      .eblock_commit_id_i     (bct_pop_e_block_id),
      .brt_info_i             (frontend_brt_info),
      .brt_info_write_enable_i('1),
      .stack_overflow_o       (stack_overflow_o),
      .stack_depth_o          (stack_depth_o),
      .stack_error_pc_o       (stack_error_pc_o)
  );

  // =========================================================================
  // Backend — dispatcher, register file, TMCU, block commit table
  // =========================================================================
  dice_backend u_dice_backend (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // FDR interface
      .fdr_valid_i(fdr_out_if.valid),
      .fdr_data_i (fdr_out_if.data),
      .fdr_ready_o(fdr_out_if.ready),

      // Block commit table outputs
      .eblock_commit_valid_o(bct_pop_valid),
      .eblock_commit_id_o   (bct_pop_e_block_id),
      .eblock_commit_ready_i('1),
      .hw_cta_pending_o     (hw_cta_pending_lo),

      // Frontend configuration-memory write stream
      .cm_wr_buffer_i(cm_wr_buffer_lo),
      .cm_wr_addr_i  (cm_wr_addr_lo),
      .cm_wr_data_i  (cm_wr_data_lo),
      .cm_wr_valid_i (cm_wr_valid_lo),
      .prog_active_o (prog_active_lo),
      .prog_active_buffer_o(prog_active_buffer_lo),

      // CGRA scan chain / bitstream outputs
      .cgra_prog_dout_o(cgra_prog_dout_o),
      .cgra_prog_we_o  (cgra_prog_we_o),
      .dispatch_busy_o (dispatch_busy_o),
      .bsload_cnt_o    (bsload_cnt_o),

      // Input-only CSR sources exposed to the CGRA input crossbar
      .csrX0_i(csrX0_i),
      .csrX1_i(csrX1_i),
      .csrX2_i(csrX2_i),
      .csrX3_i(csrX3_i),
      .csrX4_i(csrX4_i),
      .csrX5_i(csrX5_i),
      .csrX6_i(csrX6_i),
      .csrX7_i(csrX7_i),

      // for branch handler
      .cgra_pred_all_o(frontend_pred_regs),

      // AXI-Lite master interface from LDST FIFO
      .axi_awaddr_o (axi_awaddr_o),
      .axi_awvalid_o(axi_awvalid_o),
      .axi_awready_i(axi_awready_i),
      .axi_wdata_o  (axi_wdata_o),
      .axi_wstrb_o  (axi_wstrb_o),
      .axi_wvalid_o (axi_wvalid_o),
      .axi_wready_i (axi_wready_i),
      .axi_bresp_i  (axi_bresp_i),
      .axi_bvalid_i (axi_bvalid_i),
      .axi_bready_o (axi_bready_o),
      .axi_araddr_o (axi_araddr_o),
      .axi_aruser_o (axi_aruser_o),
      .axi_arvalid_o(axi_arvalid_o),
      .axi_arready_i(axi_arready_i),
      .axi_rdata_i  (axi_rdata_i),
      .axi_rresp_i  (axi_rresp_i),
      .axi_rvalid_i (axi_rvalid_i),
      .axi_rready_o (axi_rready_o)
  );

endmodule
