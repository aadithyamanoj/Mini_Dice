+define+NO_SRAM
+libext+.sv

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/cgra_core/cgra_subsystem/regfile
+incdir+${DICE_HOME}/rtl/dice_ram

// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv

// ==== DICE interfaces ====
${DICE_HOME}/rtl/interfaces/VX_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv

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
