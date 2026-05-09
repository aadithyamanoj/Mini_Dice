// UVM package for dice_core verification.
// Include this package (after uvm_pkg) in tb_top and anywhere else that
// needs access to the verification classes.
package dice_core_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "dice_define.vh"
  import dice_pkg::*;
  import axi4_xbar_pkg::*;

  typedef enum { MFETCH, BSFETCH } mem_port_sel_e;

  // Sequence items
  `include "cta_seq_item.sv"
  `include "mem_seq_item.sv"
  `include "axil_seq_item.sv"
  `include "cgra_prog_item.sv"
  `include "cgra_bitstream_item.sv"

  // CTA agent
  `include "cta_driver.sv"
  `include "cta_monitor.sv"
  `include "cta_agent.sv"

  // Memory fetch slave agent
  `include "mem_slave_driver.sv"
  `include "mem_slave_monitor.sv"
  `include "mem_slave_agent.sv"

  // AXI-Lite slave agent
  `include "axil_slave_driver.sv"
  `include "axil_slave_monitor.sv"
  `include "axil_slave_agent.sv"

  // CGRA programming monitor (passive, no driver)
  `include "cgra_prog_monitor.sv"

  // Scoreboard and environment
  `include "dice_core_scoreboard.sv"
  `include "dice_core_env.sv"

  // Tests
  `include "dice_core_base_test.sv"
  `include "dice_core_full_mul_array_test.sv"
  // Subclass tests pending data-regen for cgra-nopred (DICE_BITSTREAM_SIZE=1074
  // and 32-thread CTA). They override setup_thread_inputs_and_expectations()
  // with cgra-v0 data and won't compile/run on the new design until updated.
  // Re-enable once their data is regenerated alongside full_mul_array.
  // `include "dice_core_smoke_test.sv"
  // `include "dice_core_multi_cta_test.sv"
  // `include "dice_core_fetch_latency_test.sv"
  // `include "dice_core_multi_cta_full_test.sv"
  // `include "dice_core_mul_edge_data_test.sv"
  // `include "dice_core_axil_error_test.sv"
  // `include "dice_core_mul_random_data_test.sv"

endpackage
