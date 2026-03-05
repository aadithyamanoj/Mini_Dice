// mini_dice_filelist.f - source files for mini_dice synthesis
// All paths are relative to the Mini_Dice repo root.

// BSG BaseJump STL include path (for `include "bsg_defines.sv")
+incdir+rtl/cgra_core/cgra

// BSG BaseJump STL leaf cells
rtl/cgra_core/cgra/bsg_buf.sv
rtl/cgra_core/cgra/bsg_mux.sv
rtl/cgra_core/cgra/bsg_reduce.sv
rtl/cgra_core/cgra/bsg_dff_reset_en.sv
rtl/cgra_core/cgra/bsg_dff_async_reset.sv

// Dora stdlib primitives
rtl/cgra_core/cgra/simple_buf.sv
rtl/cgra_core/cgra/simple_bufr.sv

// Device-specific primitives
rtl/cgra_core/cgra/sb_xbar_tap_8b.sv
rtl/cgra_core/cgra/sb_xbar_tap_1b.sv
rtl/cgra_core/cgra/reg_8b.sv
rtl/cgra_core/cgra/reg_1b.sv
rtl/cgra_core/cgra/pred_nonzero_8b.sv
rtl/cgra_core/cgra/phi_mux_8b.sv

// ALU
rtl/cgra_core/cgra/mux_generic.sv
rtl/cgra_core/cgra/alu_add.sv
rtl/cgra_core/cgra/alu_mul.sv
rtl/cgra_core/cgra/fu_int8_add_int8_sub_int8_mul_control.sv
rtl/cgra_core/cgra/fu_int8_add_int8_sub_int8_mul.sv

// Generated switches (configuration muxes)
rtl/cgra_core/cgra/sw_2_1b.sv
rtl/cgra_core/cgra/sw_2_8b.sv
rtl/cgra_core/cgra/sw_3_8b.sv
rtl/cgra_core/cgra/sw_4_8b.sv
rtl/cgra_core/cgra/sw_5_1b.sv
rtl/cgra_core/cgra/sw_8_1b.sv
rtl/cgra_core/cgra/sw_8_8b.sv

// Configuration fabric (scan chain)
rtl/cgra_core/cgra/scanchain_data_d1_contexts_1.sv
rtl/cgra_core/cgra/scanchain_data_d2_contexts_1.sv
rtl/cgra_core/cgra/scanchain_data_d3_contexts_1.sv
rtl/cgra_core/cgra/scanchain_delim.sv

// Tiles
rtl/cgra_core/cgra/pe.sv
rtl/cgra_core/cgra/sb.sv

// Top-level
rtl/cgra_core/cgra/mini_dice.sv
