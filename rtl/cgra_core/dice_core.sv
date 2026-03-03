
module dice_core
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    cta_if.slave cta_if_inst,

    // Memory Bus Interfaces
    VX_mem_bus_if.master metacache_mem_if,
    VX_mem_bus_if.master bitstream_cache_mem_if

);
  // Internal Interfaces
  cta_sched_if         schedule_if          (); // between cta scheduler and fdr stages
  fdr_if               fdr_out_if           (); // between fdr and backend stages
  simt_stack_status_entry_t simt_status; // exposes simt stack entry to modules that need it
  cgra_cm_if           cm0_if               ();
  cgra_cm_if           cm1_if               ();

  // FDR -> scheduler status table/branch prediction wires
  branch_predict_interface_t bh_branch_predict_info;
  logic                      bh_branch_predict_info_we; //after recent chances i don't think this signal is needed
  // but i haven't deleted it from all modules yet (enable signal is now a bitmap and is part of the struct)
  dice_cta_status_t cta_status_data;

  // FDR -> scheduler SIMT update wires
  logic                            simt_update_valid;
  logic                            simt_update_ready;
  simt_stack_update_t              simt_update_stack_data;

  // Eblock flush wires (FDR -> Scheduler)
  logic                       eblock_flush_valid;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id;

  cta_schedule_stage u_cta_schedule_stage (
      .clk_i                   (clk_i),
      .rst_i                   (rst_i),
      .cta_if_inst             (cta_if_inst),
      .schedule_if             (schedule_if),
      .eblock_commit_valid_i   (),
      .eblock_commit_id_i      (),
      .eblock_flush_valid_i    (eblock_flush_valid),
      .eblock_flush_id_i       (eblock_flush_id),
      .bh_branch_predict_info_i(bh_branch_predict_info),
      .bh_branch_predict_info_we_i(bh_branch_predict_info_we),
      .cta_status_data_o       (cta_status_data),
      .brt_info_i              (),
      .brt_info_write_enable_i (),
      .simt_update_valid_i     (simt_update_valid),
      .simt_update_ready_o     (simt_update_ready),
      .simt_update_stack_data_i(simt_update_stack_data),
      .simt_status_o           (simt_status)
  );

  fdr_top u_fdr_top (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .metacache_mem_if(metacache_mem_if),
      .bitstream_cache_mem_if(bitstream_cache_mem_if),
      .schedule_if(schedule_if),
      .fdr_if(fdr_out_if),
      .simt_status_i(simt_status),
      .bh_branch_predict_info_o(bh_branch_predict_info),
      .bh_branch_predict_info_we_o(bh_branch_predict_info_we),
      .cta_status_data_i(cta_status_data),
      .simt_update_valid_o(simt_update_valid),
      .simt_update_ready_i(simt_update_ready),
      .simt_update_stack_data_o(simt_update_stack_data),
      .cm0_if(cm0_if),
      .cm1_if(cm1_if),
      .eblock_flush_valid_o(eblock_flush_valid),
      .eblock_flush_id_o   (eblock_flush_id)
  );

  logic dispatch_busy;
  

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .unrolling_factor(fdr_out_if.data.metadata.unrolling_factor),
      .input_register_bitmap(fdr_out_if.data.metadata.in_regs_bitmap),
      .active_mask(fdr_out_if.data.real_active_mask),
      .cta_size(fdr_out_if.data.schedule_hw_cta_size),
      .fetch_done(fdr_out_if.valid),
      .wb_valid(),          // comes from cgra
      .wb_tid_bitmap(),     // comes from cgra
      .ld_dest_regs(fdr_out_if.data.metadata.ld_dest_regs),       // comes from cgra
      .dispatch_fifo_pop('1), // cgra ready
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(rd_tid_valid),
      .dispatch_fifo_empty(),
      .gpr_bitmap_o(gpr_bitmap),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done()
  );

  assign fdr_out_if.ready = ~dispatch_busy;

  logic [4*DICE_TID_WIDTH-1:0] rd_tid;
  logic [3:0] rd_tid_valid;
  logic [`DICE_GPR_NUM-1:0] gpr_bitmap;

  logic rf_rd_valid_lo;

  logic [DICE_NUM_BANKS*DICE_REG_DATA_WIDTH-1:0] rd_data_lo;
dice_rf_ctrl #(
    .NUM_PORTS(DICE_NUM_BANKS),
    .DATA_WIDTH(DICE_REG_DATA_WIDTH),
    .NUM_TID(512),
    .TID_WIDTH($clog2(512)),
    .DEPTH(512),
    .ADDR_WIDTH($clog2(512)),
    .NUM_SPECIAL_REG(16),
    .MAX_CTA_ID(65535),
    .CTA_ID_WIDTH($clog2(65535)),
    .BUF_DEPTH(8)
) u_dice_rf_ctrl (


    .clk_i(clk_i),
    .reset_i(rst_i),

    // Read Input Ports
    .rd_tid_valid_i(rd_tid_valid),
    .rd_tid_ready_o(),
    .rd_unroll_factor_i(fdr_out_if.data.metadata.unrolling_factor),
    .rd_en_i(rd_tid_valid),
    .rd_tid_i(rd_tid),
    .rd_bitmap_i(gpr_bitmap),
    .rd_data_o(rd_data_lo),
    .rf_rd_valid_o(rf_rd_valid_lo),

    // Write Input Ports
    .cgra_tid_i(cgra_tid_lo),         // comes from cgra
    .cgra_data_i(cgra_data_lo),        // comes from cgra
    .wr_bitmap_i(fdr_out_if.data.metadata.out_regs_bitmap), // TODO: add shift reg
    .cgra_valid_i(cgra_v_lo),       // comes from cgra

    // init test no LDST and no special register for now
    .ldst_wr_i(),
    .ldst_valid_i(),
    .ldst_ready_o(),

    .clear_i(),
    .spec_rd_enable_i(),
    .spec_reg_sel_i(),
    .const_reg_i(),
    .tid_x_i(),
    .tid_y_i(),
    .tid_z_i(),
    .ntid_x_i(),
    .ntid_y_i(),
    .ntid_z_i(),
    .ctaid_x_i(),
    .ctaid_y_i(),
    .ctaid_z_i(),
    .nctaid_x_i(),
    .nctaid_y_i(),
    .nctaid_z_i(),
    .spec_reg_out_o()
);



// add dummy cgra

logic cgra_v_lo;
logic [DICE_NUM_BANKS*DICE_REG_DATA_WIDTH-1:0] cgra_data_lo;
logic [DICE_TID_WIDTH-1:0] cgra_tid_lo;

dummy_cgra u_dummy_cgra (
  .clk_i(clk_i),
  .rst_i(rst_i),
  .v_i(rf_rd_valid_lo),
  .ready_o(),
  .data_i(rd_data_lo),
  .tid_i(rd_tid),
  .v_o(cgra_v_lo),
  .tid_o(cgra_tid_lo),
  .data_o(cgra_data_lo)
);

// This should be an output of the module, will wire tomorrow
/*
temporal_coalescing_unit #(
    .NUMBER_OF_MAX_COALESCED_INTERVAL(),
    .CACHE_LINE_SIZE(),
    .NUMBER_OF_MAX_COALESCED_COMMANDS(),
    .BASE_ADDRESS_OFFSET(),
    .BASE_TID_ADDRESS_OFFSET(),
    .DATA_WIDTH(),
    .MAX_REG_WIDTH(),
    .TID_BITMAP_WIDTH()
) u_temporal_coalescing_unit (
    .clk_i(clk_i),
    .rst(rst_i),
    .incmd_valid(cgra_v_lo),
    .incmd_block_id(),
    .incmd_tid(cgra_tid_lo),
    .incmd_write_enable(),
    .incmd_write_data(cgra_data_lo),
    .incmd_write_mask(),
    .incmd_address(),
    .incmd_size(),
    .incmd_ld_dest_reg(),
    .incmd_ready(),
    .outcmd_valid(),
    .outcmd_block_id(),
    .outcmd_base_tid(),
    .outcmd_tid_bitmap(),
    .outcmd_write_enable(),
    .outcmd_write_data(),
    .outcmd_write_mask(),
    .outcmd_address(),
    .outcmd_size(),
    .outcmd_ld_dest_reg(),
    .outcmd_address_map(),
    .outcmd_ready()
);
*/



// block_commit_table u_block_commit_table (
//     .clk(clk_i),
//     .rst(~rst_i),
//     .insert_valid(),
//     .insert_hw_cta_id(),
//     .insert_e_block_id(),
//     .insert_pending_reads(),
//     .insert_pending_writes(),
//     .update_valid(),
//     .update_e_block_id(),
//     .update_is_write(),
//     .update_reduce_count(),
//     .pop_valid(),
//     .pop_e_block_id(),
//     .pop_ready(),
//     .hw_cta_pending()
// );

endmodule
