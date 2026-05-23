// mini_dice_chip_full_mul_array_test
// ----------------------------------
// Canonical end-to-end smoke test: runs the full_mul_array 5-eblock kernel
// (16 threads * 4 mem ports = 64 stores) through the chip-level env.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_full_mul_array_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_full_mul_array_test

class mini_dice_chip_full_mul_array_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_full_mul_array_test)

  function new(string name = "mini_dice_chip_full_mul_array_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  virtual function int unsigned expected_write_count();
    return 64;
  endfunction

endclass
