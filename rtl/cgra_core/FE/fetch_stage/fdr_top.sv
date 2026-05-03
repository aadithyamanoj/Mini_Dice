module fdr_top
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
#(
    parameter int BITSTREAM_SIZE = DICE_BITSTREAM_SIZE
) (
    input logic clk_i,
    input logic rst_i,

    // AXI4 crossbar slave-port interfaces (read-only masters)
    output slv_req_t  mfetch_req_o,
    input  slv_resp_t mfetch_resp_i,
    output slv_req_t  bsfetch_req_o,
    input  slv_resp_t bsfetch_resp_i,

    // Scheduler / FDR interfaces
    cta_sched_if.slave schedule_if,
    fdr_if.master      fdr_if,

    // SIMT stack status
    input simt_stack_status_entry_t simt_status_i,
    input logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] pred_regs_i,
    input logic prog_active_i,
    input logic prog_active_buffer_i,

    // Branch prediction outputs (to CS stage)
    output branch_predict_interface_t bh_branch_predict_info_o,
    output logic                      bh_branch_predict_info_we_o,
    input dice_cta_status_t cta_status_data_i,

    // SIMT stack update outputs (to CS stage)
    output logic                            simt_update_valid_o,
    input logic                             simt_update_ready_i,
    output simt_stack_update_t              simt_update_stack_data_o,

    // Direct write interface to configuration memory DFFs
    output logic                              cm_wr_buffer_o,
    output logic [$clog2(DICE_BITSTREAM_SIZE)-1:0] cm_wr_addr_o,
    output logic [AxiDataWidth-1:0]           cm_wr_data_o,
    output logic                              cm_wr_valid_o,

    // Eblock flush notification (predict-miss → scheduler)
    output logic                       eblock_flush_valid_o,
    output logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_o
);

  // ---- Registered schedule data (captured on handshake) ----
  schedule_eblock_t schedule_data_q;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      schedule_data_q <= '0;
    end else if (schedule_if.valid && schedule_if.ready) begin
      schedule_data_q <= schedule_if.data;
    end
  end
  logic [DICE_ADDR_WIDTH-1:0] simt_stack_pc;
  assign simt_stack_pc = simt_status_i.next_pc;

  // Forward declarations (needed before use below)
  logic schedule_ready_internal;
  thread_mask_t branch_mask_internal;

  assign schedule_if.ready = schedule_ready_internal;

  // ---- FDR output pass-through (schedule_data_q → fdr_if) ----
  assign fdr_if.data.schedule_eblock_id        = schedule_data_q.schedule_eblock_id;
  assign fdr_if.data.schedule_cta_id           = schedule_data_q.schedule_cta_id;
  assign fdr_if.data.schedule_grid_size        = schedule_data_q.schedule_grid_size;
  assign fdr_if.data.real_active_mask          = branch_mask_internal;

  // ---- Branch prediction output ----
  branch_predict_interface_t predict_interface_internal;
  logic predict_we_internal;

  assign predict_we_internal       = |predict_interface_internal.valid_edits_bitmap;
  assign bh_branch_predict_info_o    = predict_interface_internal;
  assign bh_branch_predict_info_we_o = predict_we_internal;

  // ---- Internal signals: meta fetch / decoder ----
  pgraph_meta_t meta_internal;
  logic         meta_valid_internal;
  logic         fire_eblock_internal;

  // ---- Internal signals: bitstream ----
  logic [DICE_ADDR_WIDTH-1:0]        bitstream_addr;
  logic [BITSTREAM_LENGTH_WIDTH-1:0] bitstream_length;
  logic                              bitstream_addr_valid_internal;
  logic                              done_streaming_internal;
  logic                              cm_num_internal;

  // ---- Internal signals: branch handler ----
  branch_meta_t branch_meta_internal;
  logic         branch_mask_valid;
  logic         branch_req_valid_internal;
  logic         is_barrier_internal;
  logic [(`DICE_PR_NUM*`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] branch_handler_pred_regs;

  logic         bh_update_valid;
  logic         bh_update_ready;
  simt_stack_update_t bh_simt_update;
  assign branch_mask_valid = branch_req_valid_internal;
  assign branch_handler_pred_regs = pred_regs_i;

  // ---- Internal signals: branch handler outputs ----
  logic bh_done_internal;
  logic predict_miss_internal;

  // ---- Branch Handler ----
  branch_handler u_branch_handler (
      .clk_i                           (clk_i),
      .rst_i                           (rst_i),
      .branch_predict_info_o           (predict_interface_internal),
      .branch_meta_i                   (branch_meta_internal),
      .branch_meta_valid_i             (branch_req_valid_internal),
      .real_active_thread_mask_o       (branch_mask_internal),
      .cs_active_mask_i                (schedule_data_q.schedule_active_mask),
      .pc_i                            (schedule_data_q.schedule_next_pc),
      .update_valid_o                  (bh_update_valid),
      .update_ready_i                  (bh_update_ready),
      .simt_stack_update_o             (bh_simt_update),
      .pred_regs_i                     (branch_handler_pred_regs),
      .has_pending_eblock_i            (cta_status_data_i.has_pending_eblock),
      .unresolved_control_divergence_i (cta_status_data_i.unresolved_control_divergence),
      .is_prefetch_i                   (schedule_data_q.schedule_prefetch_block),
      .fire_eblock_i                   (fire_eblock_internal),
      .simt_stack_pc_i                 (simt_stack_pc),
      .bh_done_o                       (bh_done_internal),
      .predict_miss_o                  (predict_miss_internal)
  );

  // SIMT stack update wiring (branch_handler → CS stage)
  assign simt_update_valid_o       = bh_update_valid;
  assign simt_update_stack_data_o  = bh_simt_update;
  assign bh_update_ready           = simt_update_ready_i;

  // ---- Meta Fetch ----
  meta_fetch u_meta_fetch (
      .clk_i               (clk_i),
      .rst_i               (rst_i),
      .schedule_valid_i    (schedule_if.valid),
      .fdr_next_pc_i       (schedule_data_q.schedule_next_pc),
      .schedule_ready_o    (schedule_ready_internal),
      .meta_req_o          (mfetch_req_o),
      .meta_resp_i         (mfetch_resp_i),
      .outgoing_meta_o     (meta_internal),
      .meta_valid_o        (meta_valid_internal),
      .fire_eblock_i       (fire_eblock_internal),
      .flush_i             (predict_miss_internal)
  );

  // ---- Decoder ----
  decode u_decode (
      .metadata_i               (meta_internal),
      .meta_in_valid_i          (meta_valid_internal),
      .real_active_thread_mask_i(branch_mask_internal),
      .bitstream_addr_o         (bitstream_addr),
      .bitstream_addr_valid_o   (bitstream_addr_valid_internal),
      .bitstream_length_o       (bitstream_length),
      .branch_metadata_o        (branch_meta_internal),
      .branch_req_valid_o       (branch_req_valid_internal),
      .is_barrier_o             (is_barrier_internal),
      .meta_o                   (fdr_if.data.metadata)
  );

  // ---- Bitstream Fetch/Load ----
  bitstream_fetch_load u_bitstream_fetch_load (
      .clk_i           (clk_i),
      .rst_i           (rst_i),
      .flush_i         (predict_miss_internal),
      .meta_valid_i    (bitstream_addr_valid_internal),
      .bitstream_addr_i(bitstream_addr),
      .prog_active_i   (prog_active_i),
      .prog_active_buffer_i(prog_active_buffer_i),
      .cm_wr_addr_o    (cm_wr_addr_o),
      .cm_wr_data_o    (cm_wr_data_o),
      .cm_wr_valid_o   (cm_wr_valid_o),
      .done_streaming_o(done_streaming_internal),
      .bs_req_o        (bsfetch_req_o),
      .bs_resp_i       (bsfetch_resp_i),
      .cm_num_o        (cm_num_internal)
  );

  assign cm_wr_buffer_o = cm_num_internal;
  assign fdr_if.data.loaded_buffer = cm_num_internal;

  // ---- Valid Checker ----
  valid_check u_valid_check (
      .barrier_indicator_i(is_barrier_internal),
      .decode_done_i      (branch_mask_valid),
      .bh_done_i          (bh_done_internal),
      .bitstream_loaded_i (done_streaming_internal),
      .barrier_complete_i (1'b1),
      .fdr_valid_o        (fdr_if.valid),
      .ex_ready_i         (fdr_if.ready),
      .fire_eblock_o      (fire_eblock_internal)
  );

  // ---- Eblock flush output (predict-miss → scheduler) ----
  assign eblock_flush_valid_o = predict_miss_internal;
  assign eblock_flush_id_o    = schedule_data_q.schedule_eblock_id;

`ifndef SYNTHESIS
  logic meta_valid_prev_q;
  logic bitstream_addr_valid_prev_q;
  logic done_streaming_prev_q;
  logic fdr_valid_prev_q;
  logic fire_eblock_prev_q;
  logic cm_wr_valid_prev_q;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      meta_valid_prev_q           <= 1'b0;
      bitstream_addr_valid_prev_q <= 1'b0;
      done_streaming_prev_q       <= 1'b0;
      fdr_valid_prev_q            <= 1'b0;
      fire_eblock_prev_q          <= 1'b0;
      cm_wr_valid_prev_q          <= 1'b0;
    end else begin
      if (schedule_if.valid && schedule_if.ready) begin
        $display(
            "[FDR] t=%0t schedule accepted: eblock=%0d cta_id=%0d next_pc=%0d active_mask=%h",
            $time,
            schedule_if.data.schedule_eblock_id,
            schedule_if.data.schedule_cta_id,
            schedule_if.data.schedule_next_pc,
            schedule_if.data.schedule_active_mask
        );
      end

      if (!meta_valid_prev_q && meta_valid_internal) begin
        $display(
            "[FDR] t=%0t metadata fetched: bitstream_addr=%0d bitstream_len=%0d latency=%0d branch=%0b barrier=%0b",
            $time,
            meta_internal.bitstream_addr,
            meta_internal.bitstream_length,
            meta_internal.lat,
            meta_internal.branch_meta.branch_ena,
            meta_internal.barrier
        );
      end

      if (!bitstream_addr_valid_prev_q && bitstream_addr_valid_internal) begin
        $display(
            "[FDR] t=%0t starting bitstream fetch/load: addr=%0d len=%0d",
            $time,
            bitstream_addr,
            bitstream_length
        );
      end

      if (!cm_wr_valid_prev_q && cm_wr_valid_o) begin
        $display(
            "[FDR] t=%0t first config-memory write: buffer=%0d addr=%0d data=%h",
            $time,
            cm_num_internal,
            cm_wr_addr_o,
            cm_wr_data_o
        );
      end

      if (!done_streaming_prev_q && done_streaming_internal) begin
        $display(
            "[FDR] t=%0t bitstream load complete: buffer=%0d",
            $time,
            cm_num_internal
        );
      end

      if (!fire_eblock_prev_q && fire_eblock_internal) begin
        $display(
            "[FDR] t=%0t execution block fired: eblock=%0d loaded_buffer=%0d",
            $time,
            schedule_data_q.schedule_eblock_id,
            cm_num_internal
        );
      end

      if (!fdr_valid_prev_q && fdr_if.valid) begin
        $display(
            "[FDR] t=%0t backend payload ready: eblock=%0d cta_id=%0d active_mask=%h",
            $time,
            fdr_if.data.schedule_eblock_id,
            fdr_if.data.schedule_cta_id,
            fdr_if.data.real_active_mask
        );
      end

      if (fdr_if.valid && fdr_if.ready) begin
        $display(
            "[FDR] t=%0t backend accepted payload: eblock=%0d",
            $time,
            fdr_if.data.schedule_eblock_id
        );
      end

      if (bh_update_valid && bh_update_ready) begin
        $display(
            "[FDR] t=%0t branch handler issued SIMT update: with_div=%0b next_pc=%0d not_taken=%0d reconv=%0d",
            $time,
            bh_simt_update.update_with_divergence,
            bh_simt_update.update_next_pc,
            bh_simt_update.branch_not_taken_pc,
            bh_simt_update.branch_reconvergence_pc
        );
      end

      if (predict_miss_internal) begin
        $display(
            "[FDR] t=%0t branch prediction miss: flushing eblock=%0d",
            $time,
            schedule_data_q.schedule_eblock_id
        );
      end

      meta_valid_prev_q           <= meta_valid_internal;
      bitstream_addr_valid_prev_q <= bitstream_addr_valid_internal;
      done_streaming_prev_q       <= done_streaming_internal;
      fdr_valid_prev_q            <= fdr_if.valid;
      fire_eblock_prev_q          <= fire_eblock_internal;
      cm_wr_valid_prev_q          <= cm_wr_valid_o;
    end
  end
`endif

endmodule
