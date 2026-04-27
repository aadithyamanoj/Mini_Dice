#------------------------------------------------------------------------
# Clock Definitions
#------------------------------------------------------------------------

#   PAD[0]  core clock
#   PAD[2]  bsg_link upstream IO/master clock
#   PAD[5]  token clock returned by the remote downstream endpoint
#   PAD[7]  bsg_link downstream source-synchronous clock

create_clock -name core_clk -period 20.0 [get_ports PAD[0]]
create_clock -name io_master_clk -period 20.0 [get_ports PAD[2]]
create_clock -name token_clk -period 20.0 [get_ports PAD[5]]
create_clock -name downstream_io_clk -period 20.0 [get_ports PAD[7]]

set_clock_uncertainty 0.5 [get_clocks {core_clk io_master_clk token_clk downstream_io_clk}]
set_clock_transition -rise 0.1 [get_clocks {core_clk io_master_clk token_clk downstream_io_clk}]
set_clock_transition -fall 0.1 [get_clocks {core_clk io_master_clk token_clk downstream_io_clk}]


set_clock_groups -asynchronous \
  -group {core_clk} \
  -group {io_master_clk} \
  -group {token_clk} \
  -group {downstream_io_clk}

#------------------------------------------------------------------------
# Link IO Timing
#------------------------------------------------------------------------

# Downstream bsg_link input bundle, relative to the source-synchronous clock.
set_input_delay 2.0 -max -clock [get_clocks downstream_io_clk] \
  [get_ports {PAD[8] PAD[9] PAD[10] PAD[11] PAD[12] PAD[13] PAD[14] PAD[15] PAD[16]}]
set_input_delay 0.0 -min -clock [get_clocks downstream_io_clk] \
  [get_ports {PAD[8] PAD[9] PAD[10] PAD[11] PAD[12] PAD[13] PAD[14] PAD[15] PAD[16]}]

# Upstream bsg_link output bundle, relative to the local IO/master clock.
set_output_delay 2.0 -max -clock [get_clocks io_master_clk] \
  [get_ports {PAD[17] PAD[18] PAD[19] PAD[20] PAD[21] PAD[22] PAD[23] PAD[24] PAD[25] PAD[26]}]
set_output_delay 0.0 -min -clock [get_clocks io_master_clk] \
  [get_ports {PAD[17] PAD[18] PAD[19] PAD[20] PAD[21] PAD[22] PAD[23] PAD[24] PAD[25] PAD[26]}]

# Downstream token returned to the remote endpoint.
set_output_delay 2.0 -max -clock [get_clocks core_clk] [get_ports PAD[27]]
set_output_delay 0.0 -min -clock [get_clocks core_clk] [get_ports PAD[27]]

#------------------------------------------------------------------------
# False Paths for Async Reset / Control Pads
#------------------------------------------------------------------------

set_false_path -from [get_ports {PAD[1] PAD[3] PAD[4] PAD[6]}] -to [all_registers]

set_load 1 [all_outputs]
