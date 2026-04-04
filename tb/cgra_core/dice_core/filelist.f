-sv
+libext+.v
+libext+.sv
+define+NO_SRAM
-y ${BSG_HOME}/bsg_dataflow
-y ${BSG_HOME}/bsg_misc
-y ${DICE_HOME}/rtl/cgra_core/regfile
-y ${DICE_HOME}/rtl/cgra_core/dispatcher/dispatcher_refactor
-y ${DICE_HOME}/rtl/cgra_core/cgra
-y ${DICE_HOME}/rtl/cgra_core/axi/src
-y ${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/cgra_core/regfile
+incdir+${DICE_HOME}/rtl/cgra_core/cgra
+incdir+${DICE_HOME}/rtl/cgra_core/axi/include
+incdir+${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/include
+incdir+${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src
+incdir+${BSG_HOME}/bsg_dataflow
+incdir+${BSG_HOME}/bsg_misc

// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv
${DICE_HOME}/rtl/DE_pkg.sv

// ==== DICE interfaces ====
${DICE_HOME}/rtl/interfaces/dice_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv

// ==== DICE RAM primitives ====
${DICE_HOME}/rtl/dice_ram/dice_ram_1w1r.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1rw.sv

// ==== Common cells / AXI packages ====
${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src/cf_math_pkg.sv
${DICE_HOME}/rtl/cgra_core/axi/src/axi_pkg.sv

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
${DICE_HOME}/rtl/cgra_core/regfile/reg_wr_buffer.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_register_file.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_read_org.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_wr_ctrl_bank.sv
${DICE_HOME}/rtl/cgra_core/regfile/dice_rf_ctrl.sv

// ==== Backend / CGRA / commit stage ====
${DICE_HOME}/rtl/cgra_core/cgra_crossbar.sv
${DICE_HOME}/rtl/cgra_core/cgra/shift_reg.sv
${DICE_HOME}/rtl/cgra_core/cgra/mini_dice.sv
${DICE_HOME}/rtl/cgra_core/commit_stage/block_commit_table.sv

// ==== Frontend / backend top-levels ====
${DICE_HOME}/rtl/cgra_core/dice_frontend.sv
${DICE_HOME}/rtl/cgra_core/dice_backend.sv

// ==== DUT ====
${DICE_HOME}/rtl/cgra_core/dice_core.sv

// ==== Testbench ====
${DICE_HOME}/tb/cgra_core/dice_core/dice_local_mem.sv
${DICE_HOME}/tb/cgra_core/dice_core/tb_dice_core.sv
