+define+NO_SRAM
+libext+.sv

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/cgra_core/regfile
+incdir+${DICE_HOME}/rtl/dice_ram

// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv

// ==== DICE interfaces ====
${DICE_HOME}/rtl/interfaces/VX_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv

// ==== DICE RAM primitives ====
${DICE_HOME}/rtl/dice_ram/dice_ram_1w1r.sv
${DICE_HOME}/rtl/dice_ram/dice_ram_1rw.sv

// ==== Fetch Stage (FDR) ====
${DICE_HOME}/rtl/cgra_core/fetch_stage/rising_edge_detector.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/valid_check.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/meta_fetch.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/bitstream_fetch_load.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/decode.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/branch_handler_no_branches.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/fdr_top.sv
