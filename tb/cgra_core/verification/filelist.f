// ============================================================================
// filelist.f — dice_core UVM verification environment
//
// Usage with VCS:
//   vcs -sverilog -f filelist.f +UVM_TESTNAME=dice_core_smoke_test \
//       +incdir+$UVM_HOME/src $UVM_HOME/src/uvm_pkg.sv \
//       -top tb_top
//
// Required env vars:
//   DICE_HOME  — root of the Mini_Dice repo  (e.g. /homes/rambodt/Mini_Dice)
//   BSG_HOME   — root of the BSG library     (bsg_fifo_1r1w_small etc.)
// ============================================================================

-sv
+libext+.v
+libext+.sv
+define+NO_SRAM

// ---- BSG library (bsg_fifo, bsg_mem, bsg_misc — not in this repo) ----
-y ${BSG_HOME}/bsg_dataflow
-y ${BSG_HOME}/bsg_mem
-y ${BSG_HOME}/bsg_misc
+incdir+${BSG_HOME}/bsg_dataflow
+incdir+${BSG_HOME}/bsg_misc

// ---- Include search paths ----
+incdir+${DICE_HOME}/rtl/includes
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/axi_crossbar/axi/axi/include
+incdir+${DICE_HOME}/rtl/axi_crossbar/axi/include
+incdir+${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/include

// ============================================================================
// RTL — compiled in dependency order
// ============================================================================

// ---- DICE configs and packages ----
${DICE_HOME}/rtl/includes/dice_config.vh
${DICE_HOME}/rtl/includes/dice_define.vh
${DICE_HOME}/rtl/includes/dice_pkg.sv
${DICE_HOME}/rtl/includes/dice_frontend_pkg.sv
${DICE_HOME}/rtl/includes/DE_pkg.sv

// ---- DICE interfaces ----
${DICE_HOME}/rtl/interfaces/dice_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/fetch_axi_read_if.sv

// ---- Third-party packages (axi + common_cells) ----
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/cf_math_pkg.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_pkg.sv

// ---- Third-party common_cells primitives ----
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/lzc.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/rr_arb_tree.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/onehot_to_bin.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/counter.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/delta_counter.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/fall_through_register.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/spill_register_flushable.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/spill_register.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/fifo_v3.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/id_queue.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/addr_decode.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/addr_decode_dync.sv

// ---- Third-party AXI primitives ----
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_intf.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/rand_id_queue_pkg.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_id_prepend.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux_id_counters.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux_simple.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_mux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_err_slv.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_multicut.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_cut.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_xbar_unmuxed.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_xbar.sv

// ---- AXI4 crossbar (contains axi4_xbar_pkg) ----
${DICE_HOME}/rtl/axi_crossbar/crossbar/axi4_full_crossbar.sv

// ---- Frontend: CTA schedule stage ----
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/simt_stack.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/simt_stack_controller.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/active_cta_table.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/cta_status_table.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/cta_controller.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/cta_scheduler.sv
${DICE_HOME}/rtl/cgra_core/FE/cta_schedule/cta_schedule_stage.sv

// ---- Frontend: fetch / decode / branch stage ----
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/rising_edge_detector.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/valid_check.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/meta_fetch.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/bitstream_fetch_load.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/decode.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/branch_handler.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/branch_handler_no_branches.sv
${DICE_HOME}/rtl/cgra_core/FE/fetch_stage/fdr_top.sv

// ---- Frontend top-level ----
${DICE_HOME}/rtl/cgra_core/FE/dice_frontend.sv

// ---- Backend: dispatcher ----
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/sync_fifo.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/sync_fifo_read_unreg.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/priority_encoder_8bit.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/priority_encoder_64bit.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/active_mask_mapper.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/register_to_bank_mapper.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/reverse_mapper.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/thread_filter.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/thread_lane_reroute.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/next_active_thread_logic.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/next_thread_logic_top.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/scoreboard_refactor.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/constant_scoreboard.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_ctrl.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_df.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_fsm.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_refactored.sv

// ---- Backend: register file ----
${DICE_HOME}/rtl/cgra_core/BE/regfile/reg_wr_buffer.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_register_file.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_read_org.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_wr_ctrl_bank.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_rf_ctrl.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_shift_reg.sv

// ---- Backend: LDST unit ----
+incdir+${DICE_HOME}/rtl/cgra_core/BE/ldst_unit
${DICE_HOME}/rtl/cgra_core/BE/ldst_unit/mem_req_fifo_4port.sv
${DICE_HOME}/rtl/cgra_core/BE/ldst_unit/mem_req_fifo.sv

// ---- Backend: CGRA misc ----
${DICE_HOME}/rtl/cgra_core/BE/misc/cgra_bitstream_buf_serial.sv
${DICE_HOME}/rtl/cgra_core/BE/misc/dice_cgra_rf.sv
${DICE_HOME}/rtl/cgra_core/BE/misc/dice_cgra_subs.sv
${DICE_HOME}/rtl/cgra_core/BE/misc/dice_ready_to_credit_flow_converter.sv

// ---- Backend: commit stage ----
${DICE_HOME}/rtl/cgra_core/BE/commit_stage/block_commit_table.sv
${DICE_HOME}/rtl/cgra_core/BE/commit_stage/dice_brt.sv

// ---- Backend top-level ----
${DICE_HOME}/rtl/cgra_core/BE/dice_backend.sv

// ---- Generated CGRA RTL (via rtl/cgra_core/BE/cgra symlink → build_nopred) ----
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu/alu_add.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu/alu_mul.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu/fu_int16_add_int16_sub_int16_mul_control.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu/fu_int16_add_int16_sub_int16_mul.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu/mux_generic.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/phi_mux_pred16_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/pred_nonzero_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/pred_to_data_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/reg_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sb.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sb_xbar_tap_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d1_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d2_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d3_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d16_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d50_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_data_d72_contexts_1.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/scanchain_delim.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sw_2_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sw_3_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sw_4_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sw_5_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/sw_8_16b.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/xbar_data_in.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/xbar_data_out.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/xbar_mem_addr.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/xbar_mem_data.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/pe.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/mini_dice.sv
${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/dice_top.sv

// ---- DUT ----
${DICE_HOME}/rtl/cgra_core/dice_core.sv

// ============================================================================
// Verification
// ============================================================================
${DICE_HOME}/tb/cgra_core/verification/dice_core_vif.sv
${DICE_HOME}/tb/cgra_core/verification/dice_core_pkg.sv
${DICE_HOME}/tb/cgra_core/verification/tb_top.sv
