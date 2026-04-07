+define+NO_SRAM
+libext+.sv

+incdir+${DICE_HOME}/rtl

// ==== DICE configs and packages ====
${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
${DICE_HOME}/rtl/dice_frontend_pkg.sv

// ==== valid_check dependencies ====
${DICE_HOME}/rtl/cgra_core/fetch_stage/valid_check.sv
