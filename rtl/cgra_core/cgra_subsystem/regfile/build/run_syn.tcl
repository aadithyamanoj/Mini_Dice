# ======================================
# Auto-generated Genus synthesis script
# ======================================
set top_module    "dice_rf_ctrl"
set filelist      "src.f"
set sdc_file      "chip.sdc"
set mmmc_file     "freepdk45_mmmc.tcl"
set outputs_dir   "outputs"
set reports_dir   "reports"
set logs_dir      "logs"

set design $top_module

# -----------------------------------------
# Directory setup
# -----------------------------------------
foreach dir [list $logs_dir $outputs_dir $reports_dir] {
    if {![file exists $dir]} {
        file mkdir $dir
        puts "Creating directory $dir"
    }
}

# -----------------------------------------
# Genus setup
# -----------------------------------------
set_db hdl_error_on_blackbox true
set_db max_cpus_per_server 32
set_db hdl_auto_sync_set_reset true
set_db hdl_unconnected_value none
set_db hdl_language sv
set_db lp_clock_gating_infer_enable true
set_db lp_clock_gating_prefix {CKG}
set_db lp_insert_clock_gating true

set_db hdl_track_filename_row_col true
set_db lp_power_unit mW
set_db hdl_unconnected_input_port_value none
set_db hdl_undriven_output_port_value none
set_db hdl_undriven_signal_value none
set_db lib_lef_consistency_check_enable true
set_db tns_opto true
set_db optimize_constant_0_flops true
set_db optimize_constant_1_flops true
set_db enc_pre_place_opt 1
set_db delete_unloaded_seqs true
set_db pqos_placement_effort high 
set_db congestion_effort high
set_db lef_cap_consistency_check_enable false
set_db leakage_power_effort medium 

set_db hdl_resolve_instance_with_libcell true


# -----------------------------------------
# Constraints and LEF
# -----------------------------------------
create_constraint_mode -name my_constraint_mode -sdc_files [list $sdc_file]
read_mmmc $mmmc_file

# -----------------------------------------
# Read HDL
# -----------------------------------------


read_hdl -f $filelist
elaborate $design
init_design -top $top_module

# # Does the SRAM "cell/type" exist in the loaded libraries?
# set sram_lib_cells [get_db lib_cells -if {.name == "sram_512x32"}]
# puts "lib_cells named sram_512x32: [llength $sram_lib_cells]"

# # Does an RTL module definition exist (meaning you compiled a Verilog module called sram_512x32)?
# set sram_mods [get_db modules -if {.name == "sram_512x32"}]
# puts "RTL modules named sram_512x32: [llength $sram_mods]"

# # Do any instances reference that cell?
# set sram_insts [get_db insts -if {.cell.name == "sram_512x32"}]
# puts "Instances of sram_512x32: [llength $sram_insts]"
# foreach i $sram_insts { puts "  [get_db $i .hier_name]" }

set_db root: .auto_ungroup none

set_db lp_clock_gating_hierarchical true
#set_db lp_insert_clock_gating_incremental true
set_db lp_clock_gating_register_aware true

check_timing_intent


# ---------------
# Synthesis
# -----------------------------------------

set_db [current_design] .retime true
set_db / .retime_effort_level high


set_db syn_generic_effort high
syn_generic

set_db syn_map_effort high
syn_map


set_db syn_opt_effort high
syn_opt

write_db -to_file pre_add_tieoffs
set_db message:WSDF-201 .max_print 20
# -----------------------------------------
# Reports & Outputs
# -----------------------------------------
#write_reports -directory reports -tag final
write_db -to_file pre_write_outputs
update_names -suffix _mapped -module $design
# Create detailed area reports
report_timing > $reports_dir/${design}_timing.rpt
report_dp > $reports_dir/${design}_datapath_incr.rpt
report_messages > $reports_dir/${design}_messages.rpt
report_power  > $reports_dir/${design}_report_power.rpt
report_area > $reports_dir/${design}_report_area.rpt
report_area -summary  > $reports_dir/${design}_report_area_summary.rpt
report_qor    > $reports_dir/${design}_report_qor.rpt
write_snapshot -outdir $reports_dir -tag final
report_summary -directory $reports_dir

write_hdl > $outputs_dir/${design}.mapped.v
## write_script > $outputs_dir/${design}_m.script
write_sdc -view SS.setup_view > $outputs_dir/${design}.mapped.sdc

write_sdf -timescale ns -precision 3 > $outputs_dir/${design}.mapped.sdf

#write_design -innovus -hierarchical -gzip_files chip_top
quit
