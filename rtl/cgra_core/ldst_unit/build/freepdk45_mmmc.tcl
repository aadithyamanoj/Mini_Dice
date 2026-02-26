create_library_set -name SS.setup_set -timing [list /data/eda_tools/pdk/freepdk-45nm/stdcells-wc.lib]
create_timing_condition -name SS.setup_cond -library_sets [list SS.setup_set]
create_rc_corner -name SS.setup_rc -temperature 125.0 -cap_table /data/eda_tools/pdk/freepdk-45nm/rtk-typical.captable
create_delay_corner -name SS.setup_delay -timing_condition SS.setup_cond -rc_corner SS.setup_rc
create_analysis_view -name SS.setup_view -delay_corner SS.setup_delay -constraint_mode my_constraint_mode

create_library_set -name FF.hold_set -timing [list /data/eda_tools/pdk/freepdk-45nm/stdcells-bc.lib]
create_timing_condition -name FF.hold_cond -library_sets [list FF.hold_set]
create_rc_corner -name FF.hold_rc -temperature 0 -cap_table /data/eda_tools/pdk/freepdk-45nm/rtk-typical.captable
create_delay_corner -name FF.hold_delay -timing_condition FF.hold_cond -rc_corner FF.hold_rc
create_analysis_view -name FF.hold_view -delay_corner FF.hold_delay -constraint_mode my_constraint_mode


create_library_set -name TT.extra_set -timing [list /data/eda_tools/pdk/freepdk-45nm/stdcells.lib]
create_timing_condition -name TT.extra_cond -library_sets [list TT.extra_set]
create_rc_corner -name TT.extra_rc -temperature 25.0 -cap_table /data/eda_tools/pdk/freepdk-45nm/rtk-typical.captable
create_delay_corner -name TT.extra_delay -timing_condition TT.extra_cond -rc_corner TT.extra_rc
create_analysis_view -name TT.extra_view -delay_corner TT.extra_delay -constraint_mode my_constraint_mode
set_analysis_view -setup { SS.setup_view } -hold { FF.hold_view TT.extra_view }

read_physical -lef { \
    /data/eda_tools/pdk/freepdk-45nm/rtk-tech.lef \
    /data/eda_tools/pdk/freepdk-45nm/stdcells.lef \
}