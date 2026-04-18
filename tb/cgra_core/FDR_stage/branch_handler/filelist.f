+define+NO_SRAM
+libext+.sv

+incdir+${DICE_HOME}/rtl

// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv

// ==== branch_handler dependencies ====
${DICE_HOME}/rtl/cgra_core/fetch_stage/rising_edge_detector.sv
${DICE_HOME}/rtl/cgra_core/fetch_stage/branch_handler.sv

// ==== testbench ====
${DICE_HOME}/tb/cgra_core/FDR_stage/branch_handler/tb_branch_handler.sv
