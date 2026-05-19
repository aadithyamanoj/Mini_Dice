// dice_core_add_array_test
// ------------------------
// full_mul_array_test with eblock 2 swapped to add_array.bin — exercises the
// CGRA ALU ADD path. Expected stores = A+B mod 2^16.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_add_array_test +UVM_VERBOSITY=UVM_LOW
class dice_core_add_array_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_add_array_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Replace the canonical mul setup with the add variant.
  virtual function void setup_thread_inputs_and_expectations();
    `include "test_data_add_array.svh"
  endfunction

endclass
