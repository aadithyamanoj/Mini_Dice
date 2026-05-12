verdiSetActWin -dock widgetDock_<Message>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
simSetSimulator "-vcssv" -exec \
           "/data/enorman/vortex4dice/dice_new/tb/cgra_core/dispatcher/regfile/simv" \
           -args
debImport "-dbdir" \
          "/data/enorman/vortex4dice/dice_new/tb/cgra_core/dispatcher/regfile/simv.daidir"
debLoadSimResult \
           /data/enorman/vortex4dice/dice_new/tb/cgra_core/dispatcher/regfile/dice_rf_ctrl_tb.fsdb
wvCreateWindow
verdiFindBar -show -win nWave_2
verdiSetActWin -win $_nWave2
wvSetCursor -win $_nWave2 993.918986
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/DE_pkg"
wvGetSignalSetScope -win $_nWave2 "/dice_rf_ctrl_tb"
wvSetPosition -win $_nWave2 {("G4" 1)}
wvSetPosition -win $_nWave2 {("G4" 1)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/dice_rf_ctrl_tb/clk_i} -height 16 \
{/dice_rf_ctrl_tb/reset_i} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G2" \
{/dice_rf_ctrl_tb/cgra_data_i\[1023:0\]} -height 16 \
{/dice_rf_ctrl_tb/cgra_tid_i\[35:0\]} -height 16 \
{/dice_rf_ctrl_tb/cgra_valid_i} -height 16 \
{/dice_rf_ctrl_tb/wr_bitmap_i\[31:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G3" \
{/dice_rf_ctrl_tb/rd_bitmap_i\[31:0\]} -height 16 \
{/dice_rf_ctrl_tb/rd_en_i} -height 16 \
{/dice_rf_ctrl_tb/rd_tid_i\[35:0\]} -height 16 \
{/dice_rf_ctrl_tb/rd_tid_valid_i} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G4" \
{/dice_rf_ctrl_tb/rd_data_o\[1023:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G5" \
}
wvSelectSignal -win $_nWave2 {( "G4" 1 )} 
wvSetPosition -win $_nWave2 {("G4" 1)}
wvGetSignalClose -win $_nWave2
wvSelectSignal -win $_nWave2 {( "G2" 1 )} 
wvSelectSignal -win $_nWave2 {( "G2" 2 )} 
wvSelectSignal -win $_nWave2 {( "G2" 2 )} 
wvSetRadix -win $_nWave2 -format Bin
wvSelectSignal -win $_nWave2 {( "G2" 2 )} 
wvSetRadix -win $_nWave2 -format UDec
wvSelectSignal -win $_nWave2 {( "G2" 4 )} 
wvSetCursor -win $_nWave2 15454.756347 -snap {("G2" 3)}
wvSetCursor -win $_nWave2 15444.498009 -snap {("G2" 3)}
wvGetSignalOpen -win $_nWave2
wvGetSignalSetScope -win $_nWave2 "/DE_pkg"
wvGetSignalSetScope -win $_nWave2 "/dice_rf_ctrl_tb"
wvGetSignalSetScope -win $_nWave2 "/dice_rf_ctrl_tb/dut/read_org"
wvGetSignalSetScope -win $_nWave2 "/dice_rf_ctrl_tb/dut/registers"
wvSetPosition -win $_nWave2 {("G6" 1)}
wvSetPosition -win $_nWave2 {("G6" 1)}
wvAddSignal -win $_nWave2 -clear
wvAddSignal -win $_nWave2 -group {"G1" \
{/dice_rf_ctrl_tb/clk_i} -height 16 \
{/dice_rf_ctrl_tb/reset_i} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G2" \
{/dice_rf_ctrl_tb/cgra_data_i\[1023:0\]} -height 16 \
{/dice_rf_ctrl_tb/cgra_tid_i\[35:0\]} -height 16 \
{/dice_rf_ctrl_tb/cgra_valid_i} -height 16 \
{/dice_rf_ctrl_tb/wr_bitmap_i\[31:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G3" \
{/dice_rf_ctrl_tb/rd_bitmap_i\[31:0\]} -height 16 \
{/dice_rf_ctrl_tb/rd_en_i} -height 16 \
{/dice_rf_ctrl_tb/rd_tid_i\[35:0\]} -height 16 \
{/dice_rf_ctrl_tb/rd_tid_valid_i} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G4" \
{/dice_rf_ctrl_tb/rd_data_o\[1023:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G5" \
{/dice_rf_ctrl_tb/dut/read_org/rd_sel_o\[287:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G6" \
{/dice_rf_ctrl_tb/dut/registers/rd_addr\[287:0\]} -height 16 \
}
wvAddSignal -win $_nWave2 -group {"G7" \
}
wvSelectSignal -win $_nWave2 {( "G6" 1 )} 
wvSetPosition -win $_nWave2 {("G6" 1)}
wvGetSignalClose -win $_nWave2
wvSetCursor -win $_nWave2 14692.219877 -snap {("G7" 0)}
wvSetCursor -win $_nWave2 14712.736553 -snap {("G7" 0)}
wvDisplayGridCount -win $_nWave2 -off
wvCloseGetStreamsDialog -win $_nWave2
wvAttrOrderConfigDlg -win $_nWave2 -close
wvCloseDetailsViewDlg -win $_nWave2
wvCloseDetailsViewDlg -win $_nWave2 -streamLevel
wvCloseFilterColorizeDlg -win $_nWave2
wvGetSignalClose -win $_nWave2
wvReloadFile -win $_nWave2
wvSaveSignal -win $_nWave2 \
           "/data/enorman/vortex4dice/dice_new/tb/cgra_core/dispatcher/regfile/reg_file_2_4.rc"
debExit
