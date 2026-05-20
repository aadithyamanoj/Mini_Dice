// ============================================================================
// filelist.f — mini_dice_top UVM verification environment (chip-level)
//
// Drives mini_dice_top directly via its link_rx/link_tx flit interface,
// skipping the chip_top pad ring + bsg_link DDR for simulation speed. The
// FPGA-side bsg_link_wrapper is included so the chip-internal bsg_link can
// negotiate, but the TB side talks flits directly through axi_link_rx/tx
// instantiated in tb_top.
//
// Usage:
//   vcs -sverilog -full64 -timescale=1ns/1ps -ntb_opts uvm \
//       -f filelist.f -top tb_top \
//       +UVM_TESTNAME=mini_dice_chip_full_mul_array_test
//
// Required env vars:
//   DICE_HOME — root of Mini_Dice repo
//   BSG_HOME  — root of basejump_stl (rtl/basejump_stl)
// ============================================================================

-sv
+libext+.v
+libext+.sv
+define+NO_SRAM

// ---- BSG library auto-resolve dirs ----
-y ${BSG_HOME}/bsg_dataflow
-y ${BSG_HOME}/bsg_mem
-y ${BSG_HOME}/bsg_misc
-y ${BSG_HOME}/bsg_async
-y ${BSG_HOME}/bsg_link
+incdir+${BSG_HOME}/bsg_dataflow
+incdir+${BSG_HOME}/bsg_misc
+incdir+${BSG_HOME}/bsg_async
+incdir+${BSG_HOME}/bsg_link

// ---- Include search paths ----
+incdir+${DICE_HOME}/rtl/includes
+incdir+${DICE_HOME}/rtl/interfaces
+incdir+${DICE_HOME}/rtl/axi_crossbar/axi/axi/include
+incdir+${DICE_HOME}/rtl/axi_crossbar/axi/include
+incdir+${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/include
+incdir+${DICE_HOME}/rtl/cgra_core/BE/ldst_unit
+incdir+${DICE_HOME}/tb/mini_dice/verification

// ============================================================================
// Packages and includes — order matters
// ============================================================================
${DICE_HOME}/rtl/includes/dice_config.vh
${DICE_HOME}/rtl/includes/dice_define.vh
${DICE_HOME}/rtl/includes/dice_pkg.sv
${DICE_HOME}/rtl/includes/dice_frontend_pkg.sv
${DICE_HOME}/rtl/includes/DE_pkg.sv
${DICE_HOME}/rtl/interfaces/dice_mem_bus_if.sv
${DICE_HOME}/rtl/interfaces/cta_if.sv
${DICE_HOME}/rtl/interfaces/cta_sched_if.sv
${DICE_HOME}/rtl/interfaces/fdr_if.sv
${DICE_HOME}/rtl/interfaces/cgra_cm_if.sv
${DICE_HOME}/rtl/interfaces/fetch_axi_read_if.sv

// ============================================================================
// AXI crossbar and common cells
// ============================================================================
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/cf_math_pkg.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_pkg.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/lzc.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/rr_arb_tree.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/onehot_to_bin.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/counter.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/delta_counter.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/fall_through_register.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/spill_register_flushable.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/spill_register.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/fifo_v3.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/id_queue.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/addr_decode.sv
${DICE_HOME}/rtl/axi_crossbar/common_cells/common_cells/src/addr_decode_dync.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_intf.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/rand_id_queue_pkg.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_id_prepend.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux_id_counters.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux_simple.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_demux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_mux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_err_slv.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_multicut.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_cut.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_xbar_unmuxed.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_xbar.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_lite_demux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_lite_mux.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_lite_to_axi.sv
${DICE_HOME}/rtl/axi_crossbar/axi/axi/src/axi_lite_xbar.sv

${DICE_HOME}/rtl/axi_crossbar/crossbar/axi4_full_crossbar.sv
${DICE_HOME}/rtl/axi_crossbar/crossbar/cgra_io_axi4_top.sv

// ============================================================================
// CGRA core RTL (same as core-level filelist — let -y resolve the deep deps)
// ============================================================================
-y ${DICE_HOME}/rtl/cgra_core/FE/cta_schedule
-y ${DICE_HOME}/rtl/cgra_core/FE/fetch_stage
-y ${DICE_HOME}/rtl/cgra_core/FE
-y ${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor
-y ${DICE_HOME}/rtl/cgra_core/BE/dispatcher
-y ${DICE_HOME}/rtl/cgra_core/BE/regfile
// Explicit includes for modules whose filename doesn't match the module name
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_refactored.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_ctrl.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_df.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/dispatcher_refactor/dispatcher_fsm.sv
${DICE_HOME}/rtl/cgra_core/BE/dispatcher/scoreboard_refactor.sv
${DICE_HOME}/rtl/cgra_core/BE/regfile/dice_shift_reg.sv
-y ${DICE_HOME}/rtl/cgra_core/BE/ldst_unit
-y ${DICE_HOME}/rtl/cgra_core/BE/misc
-y ${DICE_HOME}/rtl/cgra_core/BE
-y ${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl
-y ${DICE_HOME}/rtl/cgra_core/BE/cgra/rtl/alu
-y ${DICE_HOME}/rtl/cgra_core/cgra-v0
-y ${DICE_HOME}/rtl/cgra_core/BE/commit_stage
-y ${DICE_HOME}/rtl/cgra_core/dice_brt
-y ${DICE_HOME}/rtl/cgra_core/dice_brt/cgra_bitstream_buf
-y ${DICE_HOME}/rtl/cgra_core/dice_brt/cgra_bitstream_buf/cgra_bitstream_buf_serial

${DICE_HOME}/rtl/cgra_core/dice_core.sv

// ============================================================================
// Internal memory (CSR + FPGA mem wraps)
// ============================================================================
${DICE_HOME}/rtl/cgra_core/internal_memory/cgra_io_csr.sv
${DICE_HOME}/rtl/cgra_core/internal_memory/io_csr_cta_desc_info.sv

// ============================================================================
// IO link (axi_link_rx/tx, top_level_io, etc.)
// ============================================================================
${DICE_HOME}/rtl/IO/axi_link_rx.sv
${DICE_HOME}/rtl/IO/axi_link_tx.sv
${DICE_HOME}/rtl/IO/top_level_io.sv
${DICE_HOME}/rtl/IO/bsg_link_wrapper.sv

// ============================================================================
// mini_dice_top (the DUT)
// ============================================================================
${DICE_HOME}/rtl/mini_dice_top/mini_dice_top.sv

// ============================================================================
// UVM verification environment
// ============================================================================
${DICE_HOME}/tb/mini_dice/verification/mini_dice_chip_vif.sv
${DICE_HOME}/tb/mini_dice/verification/mini_dice_chip_pkg.sv
${DICE_HOME}/tb/mini_dice/verification/tb_top.sv
