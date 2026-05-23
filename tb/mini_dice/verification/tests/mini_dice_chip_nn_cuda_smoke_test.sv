// mini_dice_chip_nn_cuda_smoke_test
// ----------------------------------
// End-to-end smoke for the dora-compiled nn_cuda kernel (5 eblocks,
// 4 CTAs * 16 threads each). Inherits base_test's run_grid path and
// final DPI check_done verification.
//
// Kernel: nn_cuda (multi-CTA, 5 eblocks, 4 CTAs, MUL + squared-distance)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_nn_cuda_smoke_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_nn_cuda_smoke_test

class mini_dice_chip_nn_cuda_smoke_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_nn_cuda_smoke_test)

  function new(string name = "mini_dice_chip_nn_cuda_smoke_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_dir  = "tb/test_vectors/nn_cuda";
    test_vector_name = "nn_cuda";
    SETTLE_CYCLES    = 1_000_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 64;  // 4 CTAs * 16 threads * 1 store each
  endfunction
endclass
