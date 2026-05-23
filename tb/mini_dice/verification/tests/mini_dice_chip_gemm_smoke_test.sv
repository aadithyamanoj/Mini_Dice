// mini_dice_chip_gemm_smoke_test
// -------------------------------
// End-to-end smoke for the dora-compiled gemm kernel (14 eblocks,
// 4 CTAs * 16 threads each). Uses base_test's run_grid path: per-CTA
// CSR programming, CTRL.START pulse, REG_STATUS[0] polling, then a
// final DPI check_done comparing every store against expected_writes
// from gemm_runtime.json.
//
// Kernel: gemm (multi-CTA, 14 eblocks, 4 CTAs, MUL + MAC)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_gemm_smoke_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_gemm_smoke_test

class mini_dice_chip_gemm_smoke_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_gemm_smoke_test)

  function new(string name = "mini_dice_chip_gemm_smoke_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_dir  = "tb/test_vectors/gemm";
    test_vector_name = "gemm";
    SETTLE_CYCLES    = 2_000_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 64;  // 4 CTAs * 16 threads * 1 store each
  endfunction
endclass
