+incdir+$DICE_HOME/rtl
+incdir+$HW_HOME/rtl/
+incdir+$HW_HOME/rtl/libs
+incdir+$HW_HOME/rtl/cache

${DICE_HOME}/rtl/dice_config.vh
${DICE_HOME}/rtl/dice_define.vh
${DICE_HOME}/rtl/dice_pkg.sv
$HW_HOME/rtl/VX_define.vh
$HW_HOME/rtl/VX_platform.vh
$HW_HOME/rtl/cache/VX_cache_define.vh
$HW_HOME/rtl/VX_gpu_pkg.sv
$HW_HOME/rtl/cache/VX_cache_top.sv
$HW_HOME/rtl/cache/VX_cache_wrap.sv
$HW_HOME/rtl/cache/VX_cache_tags.sv
$HW_HOME/rtl/cache/VX_cache_repl.sv
$HW_HOME/rtl/cache/VX_cache_mshr.sv
$HW_HOME/rtl/cache/VX_cache_flush.sv
$HW_HOME/rtl/cache/VX_cache_data.sv
$HW_HOME/rtl/cache/VX_cache_cluster.sv
$HW_HOME/rtl/cache/VX_cache_bypass.sv
$HW_HOME/rtl/cache/VX_cache_bank.sv
$HW_HOME/rtl/mem/VX_mem_bus_if.sv
$HW_HOME/rtl/libs/VX_stream_xbar.sv
$HW_HOME/rtl/libs/VX_stream_omega.sv
$HW_HOME/rtl/libs/VX_stream_arb.sv
$HW_HOME/rtl/libs/VX_elastic_buffer.sv
$HW_HOME/rtl/libs/VX_pipe_register.sv
$HW_HOME/rtl/libs/VX_shift_register.sv

$HW_HOME/rtl/libs/VX_popcount.sv
$HW_HOME/rtl/cache/VX_cache_init.sv
$DICE_HOME/rtl/cgra_core/ldst_unit/temporal_coalescing_unit.sv
$DICE_HOME/rtl/cgra_core/ldst_unit/memory_cmd_coalesce_buffer.sv
$DICE_HOME/rtl/cgra_core/dispatcher/sync_fifo_read_unreg.sv
$HW_HOME/rtl/cache/VX_cache.sv
$DICE_HOME/rtl/cgra_core/ldst_unit/VX_cache_with_temporal.sv
$DICE_HOME/rtl/cgra_core/ldst_unit/smem.sv


./tb_vx_cache_with_temporal.sv