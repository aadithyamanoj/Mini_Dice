python3 generate_cgra_config.py 
python3 generate_cgra_bitstream.py \
  cgra_systolic_config.json \
  --selmap2_1 $DICE_HOME/rtl/cgra_core/cgra_subsystem/router_generator/output/dice_2_1_router_selmap.json \
  --selmap2_32 $DICE_HOME/rtl/cgra_core/cgra_subsystem/router_generator/output/dice_2_32_router_selmap.json \
  --opcode_map $DICE_HOME/rtl/cgra_core/cgra_subsystem/alu_generator/output/dice_alu_opcodes.json \
  -o ./bitstreams/cgra_bitstream.txt
python3 generate_rf_bitstream.py gprf_config.json
python3 generate_rf_bitstream.py pred_config.json
python3 generate_gprf_data.py 
python3 generate_predrf_data.py

vcs -full64 -sverilog -f filelist.f \
    -debug_access+all -kdb -lca +vpi \
    +define+FSDB \
    -o simv

./simv