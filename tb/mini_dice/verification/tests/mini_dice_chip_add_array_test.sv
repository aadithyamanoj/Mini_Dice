// mini_dice_chip_add_array_test
// ------------------------------
// Runs the add_array_test_vector (5-eblock kernel using ADD ALU op).
// Verifies the ADD datapath through the chip IO stack.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_add_array_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_add_array_test

class mini_dice_chip_add_array_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_add_array_test)
  function new(string name = "mini_dice_chip_add_array_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "add_array_test_vector";
  endfunction
  virtual function int unsigned expected_write_count();
    return 64;
  endfunction
endclass
