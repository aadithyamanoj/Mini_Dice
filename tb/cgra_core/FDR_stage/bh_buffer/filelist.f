-sv
-y ${DICE_HOME}/../hw/rtl/libs
+libext+.sv
+define+NO_SRAM

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/../hw/rtl
+incdir+${DICE_HOME}/../hw/rtl/mem
+incdir+${DICE_HOME}/rtl/cgra_core/cgra_subsystem/regfile

+incdir+${DICE_HOME}/rtl/dice_ram
${DICE_HOME}/../hw/rtl/VX_define.vh
${DICE_HOME}/../hw/rtl/VX_gpu_pkg.sv
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv
${DICE_HOME}/../hw/rtl/mem/VX_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_dispatch_if.sv
${DICE_HOME}/rtl/interfaces/cta_complete_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/branch_handler_if.sv
${DICE_HOME}/rtl/interfaces/dice_bh_simt_if.sv
${DICE_HOME}/rtl/interfaces/simt_stack_status_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/prf_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1w1r.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1rw.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/bh_buffer.sv
tb_bh_buffer.sv
