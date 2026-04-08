`define DICE_RF_DEBUG
module dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // FDR interface fields (flattened for synthesis friendliness)
    input  logic fdr_valid_i,
    input  logic [$bits(fdr_t)-1:0] fdr_data_i,
    output logic fdr_ready_o,

    // Block commit table outputs
    output logic                               eblock_commit_valid_o,
    output logic [   DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_o,
    input  logic                               eblock_commit_ready_i,
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_pending_o,

    // CGRA Configuration Memory
    input logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm0_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm0_chunk_en_i,
    input logic [DICE_MEM_DATA_WIDTH-1:0] cgra_cm1_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1) / DICE_MEM_DATA_WIDTH)-1:0]     cgra_cm1_chunk_en_i,

    // CGRA Scan chain / bitstream interface
    input  logic       en_i,
    input  logic       prog_v_i,
    input  logic       cm_bank_i,
    output logic       prog_ready_o,
    output logic       prog_busy_o,
    output logic [1:0] cm_bank_valid_o,
    output logic       cgra_prog_dout_o,
    output logic       cgra_prog_we_o,

    // for branch handler
    output logic [DICE_NUM_MAX_THREADS_PER_CORE*DICE_NUM_PRED-1:0] cgra_pred_all_o,

    // AXI-Lite master interface from LDST FIFO
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o,
    output logic                            axi_awvalid_o,
    input  logic                            axi_awready_i,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_wdata_o,
    output logic [1:0]                      axi_wstrb_o,
    output logic                            axi_wvalid_o,
    input  logic                            axi_wready_i,
    input  logic [1:0]                      axi_bresp_i,
    input  logic                            axi_bvalid_i,
    output logic                            axi_bready_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_araddr_o,
    output logic                            axi_arvalid_o,
    input  logic                            axi_arready_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] axi_rdata_i,
    input  logic [1:0]                      axi_rresp_i,
    input  logic                            axi_rvalid_i,
    output logic                            axi_rready_o

`ifdef DICE_RF_DEBUG
    , output logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_rd_data_o
    , output logic [DICE_NUM_PRED-1:0]                                        dbg_pred_o
    , output logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_launch_data_o
    , output logic [DICE_NUM_PRED-1:0]                                        dbg_pred_launch_o
    , output logic [((DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH)-1:0] dbg_cgra_data_o
    , output logic [DICE_TOTAL_REGS-1:0]                                      dbg_cgra_wr_bitmap_o
    , output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]               dbg_cgra_tid_o
    , output logic                                                            dbg_cgra_valid_o
    , output logic                                                            dbg_rf_rd_valid_o
`endif
);

  // Dispatcher
  logic                                            dispatch_busy;
  logic                                            dispatcher_done;
  logic                                            dispatch_fifo_empty;
  logic        [     NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic        [                    NUM_LANES-1:0] rd_tid_valid;
  logic        [                    NUM_LANES-1:0] disp_tid_valid;  
  logic        [              DICE_TOTAL_REGS-1:0] full_reg_bitmap_lo;
  fdr_t                                            fdr_data_li;

  // RF + CGRA wrapper outputs
  logic                                            rf_rd_ready_lo;
  logic        [             DICE_NUM_BANKS-1:0]   ldst_ready_lo;
  logic                                            cgra_v_lo;
  logic        [               DICE_TID_WIDTH-1:0] cgra_tid_lo;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_0;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_0;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_1;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_1;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_2;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_2;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_3;
  logic        [          DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_3;
  logic        [              NUM_MEM_PORTS-1:0] cgra_mem_port_valid_lo;
  logic        [              NUM_MEM_PORTS-1:0] cgra_mem_port_op_lo;
  logic        [             DICE_NUM_BANKS-1:0] ldst_pop_lo;
  logic                                           ldst_special_pop_lo;
  logic                                           ldst_special_ready_lo;

  // LDST write interface — pack module inputs into cache_wr_cmd
  cache_wr_cmd                                     ldst_cmd;
  logic        [          $bits(cache_wr_cmd)-1:0] ldst_wr_li;
  logic                                            ldst_valid_li;
  logic        [               DICE_TID_WIDTH-1:0] mem_rsp_tid_lo;
  logic        [          DICE_REG_ADDR_WIDTH-1:0] mem_rsp_addr_lo;
  logic        [          DICE_REG_DATA_WIDTH-1:0] mem_rsp_data_lo;
  logic                                            mem_rsp_valid_lo;

  // One-hot TID bitmap for scoreboard writeback release
  logic        [DICE_NUM_MAX_THREADS_PER_CORE-1:0] cgra_wb_tid_bitmap;
  assign cgra_wb_tid_bitmap = cgra_v_lo ? (DICE_NUM_MAX_THREADS_PER_CORE'(1'b1) << cgra_tid_lo) : '0;



  //credit signals

  logic cgra_credit_ready_lo;
  logic load_credit_fire_lo;
  logic [$clog2(NUM_MEM_PORTS+1)-1:0] peek_num_load_lo;
  logic [$clog2(DICE_NUM_BANKS+1)-1:0] ldst_pop_count_lo;
  logic [$clog2(DICE_NUM_BANKS+1)-1:0] load_credit_up_li;
  logic [$clog2(DICE_NUM_BANKS+1)-1:0] load_credit_need_li;

  logic mem_req_fifo_ready_lo;
  logic mem_req_fifo_pop_lo;

  // Block Commit Table
  logic                               bct_insert_valid;
  logic [   DICE_HW_CTA_ID_WIDTH-1:0] bct_insert_hw_cta_id;
  logic [   DICE_EBLOCK_ID_WIDTH-1:0] bct_insert_e_block_id;
  logic [                       13:0] bct_insert_pending_reads;
  logic [                       13:0] bct_insert_pending_writes;

  logic                               bct_update_valid;
  logic [   DICE_EBLOCK_ID_WIDTH-1:0] bct_update_e_block_id;
  logic                               bct_update_is_write;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0] bct_update_reduce_count;

  assign fdr_data_li         = fdr_data_i;
  assign fdr_ready_o        = ~dispatch_busy;

  assign ldst_cmd.tid       = mem_rsp_tid_lo;
  assign ldst_cmd.data      = mem_rsp_data_lo;
  assign ldst_cmd.wr_bitmap = DICE_TOTAL_REGS'(1'b1) << mem_rsp_addr_lo;

  assign ldst_wr_li         = ldst_cmd;
  assign ldst_valid_li      = mem_rsp_valid_lo;
  assign peek_num_load_lo   = gen_num_loads(fdr_data_li.metadata.ld_dest_regs, fdr_data_li.metadata.num_stores);

  // =========================================================================
  // Dispatcher
  // =========================================================================

  wire disp_pop = load_credit_fire_lo & !prog_busy_o;
  assign rd_tid_valid = disp_tid_valid & {NUM_LANES{disp_pop}};

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .ld_dest_regs(fdr_data_li.metadata.ld_dest_regs),
      .input_register_bitmap(fdr_data_li.metadata.in_regs_bitmap),
      .active_mask(fdr_data_li.real_active_mask),
      .fetch_done(fdr_valid_i),
      .wb_valid(cgra_v_lo),  // CGRA writeback pulse (lat-shifted RF read valid)
      .wb_tid_bitmap(cgra_wb_tid_bitmap),  // one-hot TID that just completed
      .dispatch_fifo_pop(disp_pop),  // advance FIFO when we have credits
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(disp_tid_valid),
      .full_reg_bitmap_o(full_reg_bitmap_lo),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done(dispatcher_done)
  );


  // =========================================================================
  // Load credit counter
  // =========================================================================

  always_comb begin
    ldst_pop_count_lo = '0;
    for (int i = 0; i < DICE_NUM_BANKS; i++) begin
      ldst_pop_count_lo += ldst_pop_lo[i];
    end
    ldst_pop_count_lo += ldst_special_pop_lo;
  end

  assign load_credit_up_li = ldst_pop_count_lo;
  assign load_credit_need_li = {{($bits(load_credit_need_li)-$bits(peek_num_load_lo)){1'b0}}, peek_num_load_lo};

  dice_ready_to_credit_flow_converter #(
      .credit_initial_p(NUM_CREDITS),
      .credit_max_val_p(NUM_CREDITS),
      .max_step_p(DICE_NUM_BANKS)
  ) credit_ctrl (
      .clk_i(clk_i),
      .reset_i(rst_i),
      .v_i((|disp_tid_valid) && !prog_busy_o),
      .ready_o(cgra_credit_ready_lo),
      .v_o(load_credit_fire_lo),
      .credit_i(load_credit_up_li),
      .credit_need_i(load_credit_need_li)
  );



  // =========================================================================
  // Register File + CGRA Wrapper
  // =========================================================================

  dice_cgra_rf u_dice_cgra_rf (
      .clk_i  (clk_i),
      .reset_i(rst_i),
      .en_i   (1'b1),

      // Configuration memory
      .cm0_data_i    (cgra_cm0_data_i),
      .cm0_chunk_en_i(cgra_cm0_chunk_en_i),
      .cm1_data_i    (cgra_cm1_data_i),
      .cm1_chunk_en_i(cgra_cm1_chunk_en_i),

      // Scan chain / bitstream
      .v_i         (prog_v_i),
      .bank_i      (cm_bank_i),
      .ready_o     (prog_ready_o),
      .busy_o      (prog_busy_o),
      .bank_valid_o(cm_bank_valid_o),
      .prog_dout_o (cgra_prog_dout_o),
      .prog_we_o   (cgra_prog_we_o),

      .mem_data_o_0(cgra_mem_data_lo_0),
      .mem_addr_o_0(cgra_mem_addr_lo_0),
      .mem_data_o_1(cgra_mem_data_lo_1),
      .mem_addr_o_1(cgra_mem_addr_lo_1),
      .mem_data_o_2(cgra_mem_data_lo_2),
      .mem_addr_o_2(cgra_mem_addr_lo_2),
      .mem_data_o_3(cgra_mem_data_lo_3),
      .mem_addr_o_3(cgra_mem_addr_lo_3),
      .mem_valid_o (cgra_v_lo),
      .cgra_tid_o  (cgra_tid_lo),
      .pred_all_o  (cgra_pred_all_o),
      .ldst_pop_o  (ldst_pop_lo),
      .ldst_special_pop_o(ldst_special_pop_lo),
      .ldst_special_ready_o(ldst_special_ready_lo),
      .mem_port_valid_o(cgra_mem_port_valid_lo),
      .mem_port_op_o(cgra_mem_port_op_lo),
      .ld_dest_regs_i(fdr_data_li.metadata.ld_dest_regs),
      .num_stores_i (fdr_data_li.metadata.num_stores),

      // CGRA latency from instruction metadata
      .latency_i(fdr_data_li.metadata.lat),

      // RF read interface (from dispatcher)
      .rd_tid_valid_i(rd_tid_valid),
      .rd_tid_ready_o(rf_rd_ready_lo),
    //   .rd_en_i       (1'b1),
      .rd_tid_i      (rd_tid),
      .rd_bitmap_i   (full_reg_bitmap_lo),
      .wr_bitmap_i   (fdr_data_li.metadata.out_regs_bitmap),

      // LDST write back interface
      .ldst_wr_i   (ldst_wr_li),
      .ldst_valid_i(ldst_valid_li),
      .ldst_ready_o(ldst_ready_lo)
`ifdef DICE_RF_DEBUG
      , .dbg_rf_rd_data_o(dbg_rf_rd_data_o)
      , .dbg_pred_o(dbg_pred_o)
      , .dbg_rf_launch_data_o(dbg_rf_launch_data_o)
      , .dbg_pred_launch_o(dbg_pred_launch_o)
      , .dbg_cgra_data_o(dbg_cgra_data_o)
      , .dbg_cgra_wr_bitmap_o(dbg_cgra_wr_bitmap_o)
      , .dbg_cgra_tid_o(dbg_cgra_tid_o)
      , .dbg_cgra_valid_o(dbg_cgra_valid_o)
      , .dbg_rf_rd_valid_o(dbg_rf_rd_valid_o)
`endif
  );

  // =========================================================================
  // LDST FIFO
  // =========================================================================

  mem_req_fifo u_mem_req_fifo (
      .clk_i(clk_i),
      .rst_i(rst_i),

      .enq_valid_i_0(cgra_mem_port_valid_lo[0]),
      .enq_valid_i_1(cgra_mem_port_valid_lo[1]),
      .enq_valid_i_2(cgra_mem_port_valid_lo[2]),
      .enq_valid_i_3(cgra_mem_port_valid_lo[3]),
      .enq_ready_o(mem_req_fifo_ready_lo),

      .enq_tid_i(cgra_tid_lo),
      .enq_addr_i_0(cgra_mem_addr_lo_0),
      .enq_addr_i_1(cgra_mem_addr_lo_1),
      .enq_addr_i_2(cgra_mem_addr_lo_2),
      .enq_addr_i_3(cgra_mem_addr_lo_3),
      .enq_data_i_0(cgra_mem_data_lo_0),
      .enq_data_i_1(cgra_mem_data_lo_1),
      .enq_data_i_2(cgra_mem_data_lo_2),
      .enq_data_i_3(cgra_mem_data_lo_3),
      .enq_op_i_0(cgra_mem_port_op_lo[0]),
      .enq_op_i_1(cgra_mem_port_op_lo[1]),
      .enq_op_i_2(cgra_mem_port_op_lo[2]),
      .enq_op_i_3(cgra_mem_port_op_lo[3]),

      .axi_awaddr_o(axi_awaddr_o),
      .axi_awvalid_o(axi_awvalid_o),
      .axi_awready_i(axi_awready_i),
      .axi_wdata_o(axi_wdata_o),
      .axi_wstrb_o(axi_wstrb_o),
      .axi_wvalid_o(axi_wvalid_o),
      .axi_wready_i(axi_wready_i),
      .axi_bresp_i(axi_bresp_i),
      .axi_bvalid_i(axi_bvalid_i),
      .axi_bready_o(axi_bready_o),
      .axi_araddr_o(axi_araddr_o),
      .axi_arvalid_o(axi_arvalid_o),
      .axi_arready_i(axi_arready_i),
      .axi_rdata_i(axi_rdata_i),
      .axi_rresp_i(axi_rresp_i),
      .axi_rvalid_i(axi_rvalid_i),
      .axi_rready_o(axi_rready_o),

      .rsp_data_ready_i(ldst_ready_lo),
      .rsp_special_ready_i(ldst_special_ready_lo),
      .pop_o(mem_req_fifo_pop_lo),
      .rsp_valid_o(mem_rsp_valid_lo),
      .rsp_tid_o(mem_rsp_tid_lo),
      .rsp_addr_o(mem_rsp_addr_lo),
      .rsp_data_o(mem_rsp_data_lo)
  );



  // =========================================================================
  // Block Commit Table
  // =========================================================================

  block_commit_table u_block_commit_table (
      .clk(clk_i),
      .rst(rst_i),

      // Insert interface
      .insert_valid         (bct_insert_valid),
      .insert_hw_cta_id     (bct_insert_hw_cta_id),
      .insert_e_block_id    (bct_insert_e_block_id),
      .insert_pending_reads (bct_insert_pending_reads),
      .insert_pending_writes(bct_insert_pending_writes),

      // Update interface
      .update_valid       (bct_update_valid),
      .update_e_block_id  (bct_update_e_block_id),
      .update_is_write    (bct_update_is_write),
      .update_reduce_count(bct_update_reduce_count),

      // Commit interface
      .pop_valid     (eblock_commit_valid_o),
      .pop_e_block_id(eblock_commit_id_o),
      .pop_ready     (eblock_commit_ready_i),

      // Status
      .hw_cta_pending(hw_cta_pending_o)
  );

endmodule
