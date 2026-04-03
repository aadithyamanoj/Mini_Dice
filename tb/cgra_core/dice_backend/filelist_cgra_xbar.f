-sv
+libext+.sv
+define+NO_SRAM

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/cgra_core/regfile


// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv
${DICE_HOME}/rtl/DE_pkg.sv

// ==== DICE interfaces ====
${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv

// ==== DICE RAM primitives ====
${DICE_HOME}/rtl/dice_ram/dice_ram_1w1r.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1rw.sv

// ==== CTA Schedule Stage ====
${DICE_HOME}/rtl/cgra_core/cta_schedule/simt_stack.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/simt_stack_controller.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/active_cta_table.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_status_table.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_controller.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_scheduler.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_schedule_stage.sv

// ==== AXI4 Crossbar (contains axi4_xbar_pkg) ====
${DICE_HOME}/rtl/cgra_core/crossbar/axi4_full_crossbar.sv

// ==== Fetch Stage (FDR) ====
${DICE_HOME}/rtl/cgra_core/fetch_stage/rising_edge_detector.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/valid_check.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/meta_fetch.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/bitstream_fetch_load.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/decode.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/branch_handler_no_branches.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/fdr_top.sv

// ==== Dispatcher and sub-modules ====
${DICE_HOME}/rtl/cgra_core/dispatcher/sync_fifo.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/sync_fifo_read_unreg.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/priority_encoder_8bit.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/priority_encoder_64bit.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/active_mask_mapper.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/register_to_bank_mapper.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/reverse_mapper.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/thread_filter.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/thread_lane_reroute.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/next_active_thread_logic.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/next_thread_logic_top.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/scoreboard_refactor.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/constant_scoreboard.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/dispatcher_refactor/dispatcher_ctrl.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/dispatcher_refactor/dispatcher_df.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/dispatcher_refactor/dispatcher_fsm.sv
${DICE_HOME}/rtl/cgra_core/dispatcher/dispatcher_refactor/dispatcher_refactored.sv

// ==== Register File ====
${DICE_HOME}/rtl/cgra_core/regfile/addr_swizzle.sv
${DICE_HOME}/rtl/cgra_core/regfile/fifo_ctrl_credit.sv
${DICE_HOME}/rtl/cgra_core/regfile/reg_wr_single_entry.sv
${DICE_HOME}/rtl/cgra_core/regfile/reg_wr_buffer.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_register_file.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_rd_ctrl_bank.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_read_org.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_wr_ctrl_bank.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_special_reg.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_rf_ctrl.sv

// ==== CGRA ====
${DICE_HOME}/rtl/cgra_core/cgra/mini_dice.sv

// ==== DUT ====
${DICE_HOME}/rtl/cgra_core/dice_core.sv

// ==== Testbench ====

${DICE_HOME}/tb/cgra_core/dice_core/cgra_xbar/tb_dice_core_cgra_xbar.sv
