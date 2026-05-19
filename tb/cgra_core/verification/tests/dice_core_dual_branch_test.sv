// dice_core_dual_branch_test
// --------------------------
// 10-eblock pipeline with two sequential branches in the same CTA. Stresses
// the SIMT stack with two push/pop cycles back-to-back. Same predicate both
// times (tid != 0) so each branch sends tid 0 through ADD and the rest
// through MUL. Final GPR[i] = (A+2B) for tid 0, (A*B^2) for tids 1..31.
//
// Test vector locally generated (tb/test_vectors/dual_branch_test_vector.json)
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_dual_branch_test +UVM_VERBOSITY=UVM_LOW

class dice_core_dual_branch_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_dual_branch_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    `include "test_data_dual_branch.svh"
  endfunction

endclass
