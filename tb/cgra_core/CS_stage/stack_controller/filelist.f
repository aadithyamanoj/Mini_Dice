-sv
-y ${DICE_HOME}/../hw/rtl/libs
+libext+.sv
+define+NO_SRAM

+incdir+${DICE_HOME}/rtl
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/../hw/rtl
+incdir+${DICE_HOME}/../hw/rtl/mem
+incdir+${DICE_HOME}/rtl/cgra_core/regfile

../../../../cgra_core/cta_schedule/simt_stack_controller.sv
../../../../cgra_core/cta_schedule/simt_stack.sv
../../../../dice_ram/dice_ram_1w1r.sv
../../../../sram/v/sram_0rw1r1w_320_32_freepdk45.v
./tb_simt_stack_controller.sv
