// dice_core_simple_branching_test
// -------------------------------
// 7-eblock pipeline with one predicate-driven branch. gen_tid_nonzero_pred
// produces PR0 = (tid != 0); tid 0 takes the ADD path, tids 1..15 take MUL.
// Exercises the FE's branch_handler, SIMT stack push/pop, and active-mask
// propagation. Test vector authored by the dora team; we just run it.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_simple_branching_test +UVM_VERBOSITY=UVM_LOW
class dice_core_simple_branching_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_simple_branching_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Replace the canonical mul setup with the simple_branching variant.
  // start_pc and thread_count are identical (0x1000 / 16), so the parent's
  // run_body dispatches the same CTA — only the 7-eblock metadata graph
  // and the 64 expected stores differ.
  virtual function void setup_thread_inputs_and_expectations();
    `include "test_data_simple_branching.svh"
  endfunction

endclass
