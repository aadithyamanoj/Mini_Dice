gcc -fPIC -shared -O2 -m64 -I${XCELIUM_HOME}/tools/include -o ./dice_alu_dpi.so ../output/dice_alu_dpi.c
xrun -64bit -sv -access +rwc ../output/dice_alu_pkg.sv ../output/dice_alu.sv tb_dice_alu.sv -sv_lib ./dice_alu_dpi
