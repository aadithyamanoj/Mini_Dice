create_clock [get_ports clk]  -period 2.5 -waveform {0 1.25} -name clk

set_clock_uncertainty 0.05  [get_clocks clk]
set_clock_transition -fall 0.05 [get_clocks clk]
set_clock_transition -rise 0.05 [get_clocks clk]
#
set_input_delay 0 -clock clk [remove_from_collection [all_inputs] clk]
set_output_delay 0 -clock clk  [all_outputs]
#set_max_delay 4000 -from [all_inputs] -to [all_outputs]

#set_max_area 0