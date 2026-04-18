+define+NO_SRAM
+libext+.sv

-y ${DICE_HOME}/rtl/cgra_core/axi/src
-y ${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/dice_ram
+incdir+${DICE_HOME}/rtl/cgra_core/axi/include
+incdir+${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/include
+incdir+${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src

${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv

${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv

${DICE_HOME}/rtl/dice_ram/dice_ram_1w1r.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1rw.sv

${DICE_HOME}/rtl/cgra_core/common_cells/common_cells/src/cf_math_pkg.sv
${DICE_HOME}/rtl/cgra_core/axi/src/axi_pkg.sv
${DICE_HOME}/rtl/cgra_core/crossbar/axi4_full_crossbar.sv

${DICE_HOME}/rtl/cgra_core/cta_schedule/active_cta_table.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_controller.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_scheduler.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_status_table.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/simt_stack.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/simt_stack_controller.sv
${DICE_HOME}/rtl/cgra_core/cta_schedule/cta_schedule_stage.sv

${DICE_HOME}/rtl/cgra_core/fetch_stage/rising_edge_detector.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/valid_check.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/meta_fetch.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/bitstream_fetch_load.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/decode.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/branch_handler.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/branch_handler_no_branches.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/fdr_top.sv

${DICE_HOME}/rtl/cgra_core/dice_frontend.sv

${DICE_HOME}/tb/cgra_core/dice_frontend_top/tb_dice_frontend_top.sv
