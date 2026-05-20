// mini_dice_chip_simple_branching_test
// -------------------------------------
// Runs simple_branching_test_vector (7-eblock divergent kernel: tid 0
// takes the ADD path, tids 1..15 take MUL). Exercises the FE SIMT stack,
// branch_handler, and active-mask propagation.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_simple_branching_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_simple_branching_test

class mini_dice_chip_simple_branching_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_simple_branching_test)
  function new(string name = "mini_dice_chip_simple_branching_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "simple_branching_test_vector";
  endfunction
  virtual function int unsigned expected_write_count();
    return 64;
  endfunction
endclass
