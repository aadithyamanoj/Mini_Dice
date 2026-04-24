module dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // FDR interface fields (flattened for synthesis friendliness)
    input logic fdr_valid_i,
    input logic [$bits(fdr_t)-1:0] fdr_data_i,
    output logic fdr_ready_o,

    // Block commit table outputs
    output logic                            eblock_commit_valid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0] eblock_commit_id_o,
    input  logic                            eblock_commit_ready_i,
    output logic                            hw_cta_pending_o,

    // Frontend configuration-memory write stream
    input logic                                   cm_wr_buffer_i,
    input logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_i,
    input logic [        DICE_MEM_DATA_WIDTH-1:0] cm_wr_data_i,
    input logic                                   cm_wr_valid_i,

    // CGRA scan chain / bitstream outputs
    output logic cgra_prog_dout_o,
    output logic cgra_prog_we_o,

    // Input-only CSR sources exposed to the CGRA input crossbar
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX1_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX2_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX3_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX5_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX6_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX7_i,

    // for branch handler
    output logic [DICE_NUM_MAX_THREADS_PER_CORE*DICE_NUM_PRED-1:0] cgra_pred_all_o,

    // AXI-Lite master interface from LDST FIFO
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o,
    output logic                           axi_awvalid_o,
    input  logic                           axi_awready_i,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_wdata_o,
    output logic [                    1:0] axi_wstrb_o,
    output logic                           axi_wvalid_o,
    input  logic                           axi_wready_i,
    input  logic [                    1:0] axi_bresp_i,
    input  logic                           axi_bvalid_i,
    output logic                           axi_bready_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_araddr_o,
    output logic                           axi_arvalid_o,
    input  logic                           axi_arready_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] axi_rdata_i,
    input  logic [                    1:0] axi_rresp_i,
    input  logic                           axi_rvalid_i,
    output logic                           axi_rready_o
);

  localparam int CmChunkCount = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                / DICE_MEM_DATA_WIDTH;

  // Dispatcher
  logic dispatch_busy;
  logic dispatcher_done;
  logic dispatch_fifo_empty;
  logic [NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic [NUM_LANES-1:0] rd_tid_valid;
  logic [NUM_LANES-1:0] disp_tid_valid;
  logic [DICE_TOTAL_REGS-1:0] full_reg_bitmap_lo;
  fdr_t fdr_data_li;
  fdr_t fdr_active_q;
  fdr_t fdr_active_li;

  // RF + CGRA wrapper outputs
  logic rf_rd_ready_lo;
  logic [DICE_NUM_BANKS-1:0] ldst_ready_lo;
  logic cgra_v_lo;
  logic [DICE_TID_WIDTH-1:0] cgra_tid_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] cgra_e_block_id_lo;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_0;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_0;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_1;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_1;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_2;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_2;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_data_lo_3;
  logic [DICE_REG_DATA_WIDTH-1:0] cgra_mem_addr_lo_3;
  logic [DICE_REG_ADDR_WIDTH-1:0] cgra_mem_rsp_addr_lo_0;
  logic [DICE_REG_ADDR_WIDTH-1:0] cgra_mem_rsp_addr_lo_1;
  logic [DICE_REG_ADDR_WIDTH-1:0] cgra_mem_rsp_addr_lo_2;
  logic [DICE_REG_ADDR_WIDTH-1:0] cgra_mem_rsp_addr_lo_3;
  logic [NUM_MEM_PORTS-1:0] cgra_mem_port_valid_lo;
  logic [NUM_MEM_PORTS-1:0] cgra_mem_port_op_lo;
  logic [DICE_NUM_BANKS-1:0] ldst_pop_lo;
  logic [DICE_NUM_BANKS-1:0][DICE_EBLOCK_ID_WIDTH-1:0] ldst_pop_e_block_id_lo;
  logic ldst_special_pop_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] ldst_special_pop_e_block_id_lo;
  logic ldst_special_ready_lo;

  // LDST write interface — pack module inputs into cache_wr_cmd
  cache_wr_cmd ldst_cmd;
  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_li;
  logic ldst_valid_li;
  logic [DICE_TID_WIDTH-1:0] mem_rsp_tid_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] mem_rsp_e_block_id_lo;
  logic [DICE_REG_ADDR_WIDTH-1:0] mem_rsp_addr_lo;
  logic [DICE_REG_DATA_WIDTH-1:0] mem_rsp_data_lo;
  logic mem_rsp_valid_lo;

  // One-hot release for the scoreboard. Loads are released when the LDST
  // response is accepted by the RF writeback path, not when the CGRA pipeline
  // emits the memory request.
  logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] scoreboard_wb_tid_bitmap;
  logic [REG_NUM-1:0] scoreboard_wb_regs_bitmap;

  assign scoreboard_wb_tid_bitmap = mem_rsp_valid_lo
      ? (DICE_NUM_MAX_THREADS_PER_CORE'(1'b1) << mem_rsp_tid_lo)
      : '0;
  assign scoreboard_wb_regs_bitmap = mem_rsp_valid_lo ? (REG_NUM'(1'b1) << mem_rsp_addr_lo) : '0;



  //credit signals

  logic                                cgra_credit_ready_lo;
  logic                                mem_bundle_credit_ready_lo;
  logic                                load_credit_fire_lo;
  logic                                mem_bundle_credit_fire_lo;
  logic [ $clog2(NUM_MEM_PORTS+1)-1:0] peek_num_load_lo;
  logic [ $clog2(NUM_MEM_PORTS+1)-1:0] fdr_payload_num_load_lo;
  logic [$clog2(DICE_NUM_BANKS+1)-1:0] load_credit_up_li;
  logic [$clog2(DICE_NUM_BANKS+1)-1:0] load_credit_need_li;
  logic                                mem_bundle_credit_up_li;
  logic                                mem_bundle_credit_need_li;

  logic                                mem_req_fifo_ready_lo;
  logic                                mem_req_bundle_pop_lo;
  logic                                mem_stage_lo;
  logic                                dispatch_issue_req_lo;
  logic                                disp_pop;

  localparam int CgraPipeCountWidth = $clog2(DICE_NUM_MAX_THREADS_PER_CORE + 1) + 1;
  logic [  CgraPipeCountWidth-1:0] cgra_pipeline_count_q;
  logic [  CgraPipeCountWidth-1:0] cgra_pipeline_inc_li;
  logic [  CgraPipeCountWidth-1:0] cgra_pipeline_dec_li;
  logic                            cgra_pipeline_empty_lo;

  // CGRA programming glue
  logic [ DICE_MEM_DATA_WIDTH-1:0] cgra_cm0_data_li;
  logic [        CmChunkCount-1:0] cgra_cm0_chunk_en_li;
  logic [ DICE_MEM_DATA_WIDTH-1:0] cgra_cm1_data_li;
  logic [        CmChunkCount-1:0] cgra_cm1_chunk_en_li;
  logic                            prog_ready_lo;
  logic                            prog_busy_lo;
  logic [                     1:0] cm_bank_valid_lo;
  logic                            prog_v_li;
  logic                            prog_handshake_li;
  logic                            prog_pending_q;
  logic                            prog_pending_buffer_q;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] prog_pending_eblock_q;
  logic                            prog_active_buffer_q;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] prog_active_eblock_q;

  // Latched dispatch e_block_id (driven by dice_brt, also consumed by dice_cgra_rf)
  logic [DICE_EBLOCK_ID_WIDTH-1:0] dispatch_e_block_id;

  // Precomputed pending reads/stores passed into dice_brt
  logic [PENDING_MEM_COUNT_WIDTH-1:0] fdr_pending_reads_li;
  logic [PENDING_MEM_COUNT_WIDTH-1:0] fdr_pending_stores_li;
  logic                            fdr_accept_li;
  logic                            fdr_active_valid_q;
  logic                            scoreboard_clear_li;

  // Store completion from mem_req_fifo
  logic                            store_pop_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] store_pop_e_block_id_lo;

  assign fdr_data_li = fdr_data_i;
  assign fdr_active_li = fdr_accept_li ? fdr_data_li : fdr_active_q;
  assign cgra_pipeline_inc_li = CgraPipeCountWidth'($countones(rd_tid_valid));
  assign cgra_pipeline_dec_li = CgraPipeCountWidth'(cgra_v_lo && !cgra_pipeline_empty_lo);
  assign cgra_pipeline_empty_lo = (cgra_pipeline_count_q == '0);
  assign fdr_ready_o = ~dispatch_busy
                     && ~prog_busy_lo
                     && ~prog_pending_q
                     && ~cgra_v_lo
                     && cgra_pipeline_empty_lo;
  //  && !hw_cta_pending_o;
  assign fdr_accept_li = fdr_valid_i & fdr_ready_o;

  assign ldst_cmd.tid = mem_rsp_tid_lo;
  assign ldst_cmd.e_block_id = mem_rsp_e_block_id_lo;
  assign ldst_cmd.data = mem_rsp_data_lo;
  assign ldst_cmd.wr_bitmap = DICE_TOTAL_REGS'(1'b1) << mem_rsp_addr_lo;

  assign ldst_wr_li = ldst_cmd;
  assign ldst_valid_li = mem_rsp_valid_lo;
  assign peek_num_load_lo = gen_num_loads(
      fdr_active_li.metadata.ld_dest_regs, fdr_active_li.metadata.num_stores
  );
  assign fdr_payload_num_load_lo = gen_num_loads(
      fdr_data_li.metadata.ld_dest_regs, fdr_data_li.metadata.num_stores
  );
  assign mem_stage_lo = (peek_num_load_lo != '0) || (fdr_active_li.metadata.num_stores != '0);
  assign dispatch_issue_req_lo = (|disp_tid_valid) && !prog_busy_lo;
  assign fdr_pending_reads_li = PENDING_MEM_COUNT_WIDTH'(
      $countones(fdr_data_li.real_active_mask) * fdr_payload_num_load_lo
  );
  assign fdr_pending_stores_li = PENDING_MEM_COUNT_WIDTH'(
      $countones(fdr_data_li.real_active_mask) * fdr_data_li.metadata.num_stores
  );
  assign scoreboard_clear_li = fdr_accept_li
                             && fdr_active_valid_q
                             && (fdr_data_li.schedule_cta_id != fdr_active_q.schedule_cta_id);
  assign cgra_cm0_data_li = DICE_MEM_DATA_WIDTH'(cm_wr_data_i);
  assign cgra_cm1_data_li = DICE_MEM_DATA_WIDTH'(cm_wr_data_i);
  assign prog_handshake_li = prog_pending_q & prog_ready_lo;

  always_comb begin
    cgra_cm0_chunk_en_li = '0;
    cgra_cm1_chunk_en_li = '0;

    if (cm_wr_valid_i) begin
      if (cm_wr_buffer_i == 1'b0) begin
        cgra_cm0_chunk_en_li[cm_wr_addr_i/DICE_MEM_DATA_WIDTH] = 1'b1;
      end else begin
        cgra_cm1_chunk_en_li[cm_wr_addr_i/DICE_MEM_DATA_WIDTH] = 1'b1;
      end
    end
  end

  bsg_edge_detect u_prog_v_edge_detect (
      .clk_i   (clk_i),
      .reset_i (rst_i),
      .sig_i   (prog_handshake_li),
      .detect_o(prog_v_li)
  );

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      fdr_active_q          <= '0;
      fdr_active_valid_q    <= 1'b0;
      prog_pending_q        <= 1'b0;
      prog_pending_buffer_q <= 1'b0;
      prog_pending_eblock_q <= '0;
      prog_active_buffer_q  <= '0;
      prog_active_eblock_q  <= '0;
    end else begin
      if (fdr_accept_li) begin
        fdr_active_q          <= fdr_data_li;
        fdr_active_valid_q    <= 1'b1;
        prog_pending_q        <= 1'b1;
        prog_pending_buffer_q <= fdr_data_li.loaded_buffer;
        prog_pending_eblock_q <= fdr_data_li.schedule_eblock_id;
      end

      if (prog_v_li) begin
        prog_pending_q       <= 1'b0;
        prog_active_buffer_q <= prog_pending_buffer_q;
        prog_active_eblock_q <= prog_pending_eblock_q;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      cgra_pipeline_count_q <= '0;
    end else begin
      cgra_pipeline_count_q <= cgra_pipeline_count_q + cgra_pipeline_inc_li - cgra_pipeline_dec_li;
    end
  end

  // =========================================================================
  // Block Retire Table (BCT insert pipeline + retire FIFO + serializer + BCT)
  // =========================================================================

  dice_brt u_dice_brt (
      .clk_i(clk_i),
      .rst_i(rst_i),

      // Dispatcher handshake
      .fdr_valid_i         (fdr_accept_li),
      .dispatch_busy_i     (dispatch_busy),
      .fdr_e_block_id_i    (DICE_EBLOCK_ID_WIDTH'(fdr_data_li.schedule_eblock_id)),
      .fdr_pending_reads_i (fdr_pending_reads_li),
      .fdr_pending_stores_i(fdr_pending_stores_li),

      // Latched e_block_id (also consumed by dice_cgra_rf)
      .dispatch_e_block_id_o(dispatch_e_block_id),

      // Retire signals from dice_cgra_rf (load completions)
      .ldst_pop_i                   (ldst_pop_lo),
      .ldst_pop_e_block_id_i        (ldst_pop_e_block_id_lo),
      .ldst_special_pop_i           (ldst_special_pop_lo),
      .ldst_special_pop_e_block_id_i(ldst_special_pop_e_block_id_lo),

      // Store retire signals from mem_req_fifo
      .store_retire_valid_i      (store_pop_lo),
      .store_retire_e_block_id_i (store_pop_e_block_id_lo),

      // Commit interface
      .eblock_commit_valid_o(eblock_commit_valid_o),
      .eblock_commit_id_o   (eblock_commit_id_o),
      .eblock_commit_ready_i(eblock_commit_ready_i),
      .hw_cta_pending_o     (hw_cta_pending_o)
  );

  // =========================================================================
  // Dispatcher
  // =========================================================================

  assign rd_tid_valid = disp_tid_valid & {NUM_LANES{disp_pop}};

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .ld_dest_regs(fdr_active_li.metadata.ld_dest_regs),
      .input_register_bitmap(fdr_active_li.metadata.in_regs_bitmap),
      .active_mask(fdr_active_li.real_active_mask),
      .fetch_done(fdr_accept_li),
      .wb_valid(mem_rsp_valid_lo),
      .wb_tid_bitmap(scoreboard_wb_tid_bitmap),
      .wb_regs_bitmap(scoreboard_wb_regs_bitmap),
      .clear_scoreboard(scoreboard_clear_li),
      .dispatch_fifo_pop(disp_pop),  // advance FIFO when we have credits
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(disp_tid_valid),
      .full_reg_bitmap_o(full_reg_bitmap_lo),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done(dispatcher_done)
  );


  // =========================================================================
  // Dispatch credit counters
  // load_credit_* caps outstanding load work.
  // mem_bundle_credit_* reserves slots in the pre-PISO wide bundle FIFO.
  // =========================================================================

  assign load_credit_up_li = {{($bits(load_credit_up_li) - 1) {1'b0}}, mem_rsp_valid_lo};
  assign load_credit_need_li = {
    {($bits(load_credit_need_li) - $bits(peek_num_load_lo)) {1'b0}}, peek_num_load_lo
  };
  assign mem_bundle_credit_up_li = mem_req_bundle_pop_lo;
  assign mem_bundle_credit_need_li = mem_stage_lo;

  dice_ready_to_credit_flow_converter #(
      .credit_initial_p(NUM_CREDITS),
      .credit_max_val_p(NUM_CREDITS),
      .max_step_p(DICE_NUM_BANKS)
  ) credit_ctrl (
      .clk_i(clk_i),
      .reset_i(rst_i),
      .v_i(dispatch_issue_req_lo & (!mem_stage_lo || mem_bundle_credit_ready_lo)),
      .ready_o(cgra_credit_ready_lo),
      .v_o(load_credit_fire_lo),
      .credit_i(load_credit_up_li),
      .credit_need_i(load_credit_need_li)
  );

  dice_ready_to_credit_flow_converter #(
      .credit_initial_p(MEM_REQ_BUNDLE_FIFO_DEPTH),
      .credit_max_val_p(MEM_REQ_BUNDLE_FIFO_DEPTH),
      .max_step_p(1)
  ) mem_bundle_credit_ctrl (
      .clk_i(clk_i),
      .reset_i(rst_i),
      .v_i(dispatch_issue_req_lo & (!mem_stage_lo || cgra_credit_ready_lo)),
      .ready_o(mem_bundle_credit_ready_lo),
      .v_o(mem_bundle_credit_fire_lo),
      .credit_i(mem_bundle_credit_up_li),
      .credit_need_i(mem_bundle_credit_need_li)
  );



  // =========================================================================
  // Register File + CGRA Wrapper
  // =========================================================================

  dice_cgra_rf u_dice_cgra_rf (
      .clk_i  (clk_i),
      .reset_i(rst_i),
      .en_i   (~prog_busy_lo),

      // Configuration memory
      .cm0_data_i    (cgra_cm0_data_li),
      .cm0_chunk_en_i(cgra_cm0_chunk_en_li),
      .cm1_data_i    (cgra_cm1_data_li),
      .cm1_chunk_en_i(cgra_cm1_chunk_en_li),

      // Scan chain / bitstream
      .v_i         (prog_v_li),
      .bank_i      (prog_pending_buffer_q),
      .ready_o     (prog_ready_lo),
      .busy_o      (prog_busy_lo),
      .bank_valid_o(cm_bank_valid_lo),
      .prog_dout_o (cgra_prog_dout_o),
      .prog_we_o   (cgra_prog_we_o),

      .csrX0_i(csrX0_i),
      .csrX1_i(csrX1_i),
      .csrX2_i(csrX2_i),
      .csrX3_i(csrX3_i),
      .csrX4_i(csrX4_i),
      .csrX5_i(csrX5_i),
      .csrX6_i(csrX6_i),
      .csrX7_i(csrX7_i),

      .mem_data_o_0(cgra_mem_data_lo_0),
      .mem_addr_o_0(cgra_mem_addr_lo_0),
      .mem_data_o_1(cgra_mem_data_lo_1),
      .mem_addr_o_1(cgra_mem_addr_lo_1),
      .mem_data_o_2(cgra_mem_data_lo_2),
      .mem_addr_o_2(cgra_mem_addr_lo_2),
      .mem_data_o_3(cgra_mem_data_lo_3),
      .mem_addr_o_3(cgra_mem_addr_lo_3),
      .mem_valid_o(cgra_v_lo),
      .cgra_tid_o(cgra_tid_lo),
      .cgra_e_block_id_o(cgra_e_block_id_lo),
      .pred_all_o(cgra_pred_all_o),
      .ldst_pop_o(ldst_pop_lo),
      .ldst_pop_e_block_id_o(ldst_pop_e_block_id_lo),
      .ldst_special_pop_o(ldst_special_pop_lo),
      .ldst_special_pop_e_block_id_o(ldst_special_pop_e_block_id_lo),
      .ldst_special_ready_o(ldst_special_ready_lo),
      .mem_port_valid_o(cgra_mem_port_valid_lo),
      .mem_port_op_o(cgra_mem_port_op_lo),
      .mem_rsp_addr_o_0(cgra_mem_rsp_addr_lo_0),
      .mem_rsp_addr_o_1(cgra_mem_rsp_addr_lo_1),
      .mem_rsp_addr_o_2(cgra_mem_rsp_addr_lo_2),
      .mem_rsp_addr_o_3(cgra_mem_rsp_addr_lo_3),
      .ld_dest_regs_i(fdr_active_q.metadata.ld_dest_regs),
      .num_stores_i(fdr_active_q.metadata.num_stores),

      // CGRA latency from instruction metadata
      // Use registered fdr_active_q to break combinational loop:
      // fdr_active_li -> latency_i -> shift_reg out_data -> cgra_v_lo -> fdr_ready_o -> fdr_accept_li -> fdr_active_li
      .latency_i(fdr_active_q.metadata.lat),
      .shift_clear_i(fdr_accept_li),  // clear shift-reg ring buffers on eblock transition

      // RF read interface (from dispatcher)
      .rd_tid_valid_i(rd_tid_valid),
      .rd_tid_ready_o(rf_rd_ready_lo),
      //   .rd_en_i       (1'b1),
      .rd_tid_i      (rd_tid),
      .e_block_id_i  (dispatch_e_block_id),
      .rd_bitmap_i   (full_reg_bitmap_lo),
      .wr_bitmap_i   (fdr_active_q.metadata.out_regs_bitmap),

      // LDST write back interface
      .ldst_wr_i   (ldst_wr_li),
      .ldst_valid_i(ldst_valid_li),
      .ldst_ready_o(ldst_ready_lo)
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
      .enq_ready_o  (mem_req_fifo_ready_lo),

      .enq_tid_i(cgra_tid_lo),
      .enq_e_block_id_i(cgra_e_block_id_lo),
      .enq_addr_i_0(cgra_mem_addr_lo_0),
      .enq_addr_i_1(cgra_mem_addr_lo_1),
      .enq_addr_i_2(cgra_mem_addr_lo_2),
      .enq_addr_i_3(cgra_mem_addr_lo_3),
      .enq_data_i_0(cgra_mem_data_lo_0),
      .enq_data_i_1(cgra_mem_data_lo_1),
      .enq_data_i_2(cgra_mem_data_lo_2),
      .enq_data_i_3(cgra_mem_data_lo_3),
      .enq_rsp_addr_i_0(cgra_mem_rsp_addr_lo_0),
      .enq_rsp_addr_i_1(cgra_mem_rsp_addr_lo_1),
      .enq_rsp_addr_i_2(cgra_mem_rsp_addr_lo_2),
      .enq_rsp_addr_i_3(cgra_mem_rsp_addr_lo_3),
      .enq_op_i_0(cgra_mem_port_op_lo[0]),
      .enq_op_i_1(cgra_mem_port_op_lo[1]),
      .enq_op_i_2(cgra_mem_port_op_lo[2]),
      .enq_op_i_3(cgra_mem_port_op_lo[3]),

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
      .axi_arvalid_o(axi_arvalid_o),
      .axi_arready_i(axi_arready_i),
      .axi_rdata_i  (axi_rdata_i),
      .axi_rresp_i  (axi_rresp_i),
      .axi_rvalid_i (axi_rvalid_i),
      .axi_rready_o (axi_rready_o),

      .rsp_data_ready_i(ldst_ready_lo),
      .rsp_special_ready_i(ldst_special_ready_lo),
      .bundle_pop_o(mem_req_bundle_pop_lo),
      .pop_o(),
      .rsp_valid_o(mem_rsp_valid_lo),
      .rsp_tid_o(mem_rsp_tid_lo),
      .rsp_e_block_id_o(mem_rsp_e_block_id_lo),
      .rsp_addr_o(mem_rsp_addr_lo),
      .rsp_data_o(mem_rsp_data_lo),

      .store_pop_o(store_pop_lo),
      .store_pop_e_block_id_o(store_pop_e_block_id_lo)
  );

  assign disp_pop = load_credit_fire_lo & mem_bundle_credit_fire_lo;

`ifndef SYNTHESIS
  logic dispatch_busy_prev_q;
  logic prog_busy_prev_q;
  logic fdr_valid_prev_q;
  logic mem_rsp_valid_prev_q;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      dispatch_busy_prev_q <= 1'b0;
      prog_busy_prev_q     <= 1'b0;
      fdr_valid_prev_q     <= 1'b0;
      mem_rsp_valid_prev_q <= 1'b0;
    end else begin
      if (!fdr_valid_prev_q && fdr_valid_i) begin
        $display(
            "[BE:dice_backend] t=%0t FDR payload visible: eblock=%0d cta_id=%0d active_mask=%h loads=%0d stores=%0d lat=%0d ready=%0b dispatch_busy=%0b prog_busy=%0b prog_pending=%0b cgra_v=%0b pipe_empty=%0b",
            $time, fdr_data_li.schedule_eblock_id, fdr_data_li.schedule_cta_id,
            fdr_data_li.real_active_mask, fdr_payload_num_load_lo,
            fdr_data_li.metadata.num_stores, fdr_data_li.metadata.lat, fdr_ready_o,
            dispatch_busy, prog_busy_lo, prog_pending_q, cgra_v_lo, cgra_pipeline_empty_lo);
      end

      if (fdr_valid_i && fdr_ready_o) begin
        $display(
            "[BE:dice_backend] t=%0t backend accepted FDR packet: eblock=%0d loads=%0d stores=%0d lat=%0d pending_reads=%0d pending_stores=%0d",
            $time, fdr_data_li.schedule_eblock_id, fdr_payload_num_load_lo,
            fdr_data_li.metadata.num_stores, fdr_data_li.metadata.lat,
            fdr_pending_reads_li, fdr_pending_stores_li);
      end

      if (!dispatch_busy_prev_q && dispatch_busy) begin
        $display("[BE:dice_backend] t=%0t dispatcher became busy", $time);
      end

      if (dispatch_busy_prev_q && !dispatch_busy) begin
        $display("[BE:dice_backend] t=%0t dispatcher became idle", $time);
      end

      if (disp_pop) begin
        $display(
            "[BE:dice_backend] t=%0t dispatching threads: tids_valid=%b loads_needed=%0d load_credit_refund=%0d mem_stage=%0b bundle_refund=%0b load_ready=%0b bundle_ready=%0b",
            $time, disp_tid_valid, load_credit_need_li, load_credit_up_li, mem_stage_lo,
            mem_bundle_credit_up_li, cgra_credit_ready_lo, mem_bundle_credit_ready_lo);
      end

      if (!prog_busy_prev_q && prog_busy_lo) begin
        $display("[BE:dice_backend] t=%0t programming CGRA started: buffer=%0d eblock=%0d", $time,
                 prog_active_buffer_q, prog_active_eblock_q);
      end

      if (prog_v_li) begin
        $display("[BE:dice_backend] t=%0t programming pulse issued: buffer=%0d eblock=%0d", $time,
                 prog_pending_buffer_q, prog_pending_eblock_q);
      end

      if (prog_busy_prev_q && !prog_busy_lo) begin
        $display("[BE:dice_backend] t=%0t programming CGRA complete: buffer=%0d eblock=%0d", $time,
                 prog_active_buffer_q, prog_active_eblock_q);
      end

      if (|cgra_mem_port_valid_lo) begin
        $display(
            "[BE:dice_backend] t=%0t CGRA issued memory ops: valid=%b op=%b tid=%0d eblock=%0d",
            $time, cgra_mem_port_valid_lo, cgra_mem_port_op_lo, cgra_tid_lo, cgra_e_block_id_lo);
      end

      if (!mem_rsp_valid_prev_q && mem_rsp_valid_lo) begin
        $display(
            "[BE:dice_backend] t=%0t memory response returned: tid=%0d eblock=%0d addr=%0d data=%h",
            $time, mem_rsp_tid_lo, mem_rsp_e_block_id_lo, mem_rsp_addr_lo, mem_rsp_data_lo);
      end

      if (eblock_commit_valid_o) begin
        $display("[BE:dice_backend] t=%0t commit emitted: eblock=%0d hw_cta_pending=%0b", $time,
                 eblock_commit_id_o, hw_cta_pending_o);
      end

      // Watchdog: print fdr_ready_o blockers when stalled
      // if (fdr_valid_i && !fdr_ready_o && !dispatch_busy
      //     && !prog_busy_lo && !prog_pending_q) begin
      //   $display(
      //       "[BE:watchdog] t=%0t STALL cgra_v=%0b pipe_empty=%0b pipe_count=%0d",
      //       $time, cgra_v_lo, cgra_pipeline_empty_lo,
      //       cgra_pipeline_count_q);
      // end

      fdr_valid_prev_q     <= fdr_valid_i;
      dispatch_busy_prev_q <= dispatch_busy;
      prog_busy_prev_q     <= prog_busy_lo;
      mem_rsp_valid_prev_q <= mem_rsp_valid_lo;
    end
  end
`endif

endmodule
