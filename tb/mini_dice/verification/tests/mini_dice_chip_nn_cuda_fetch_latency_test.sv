// mini_dice_chip_nn_cuda_fetch_latency_test
// ------------------------------------------
// nn_cuda under elevated mem_responder read latency. Same idea as
// gemm_fetch_latency_test but on the shallower 5-eblock kernel, checks
// that the slower per-CTA churn (nn_cuda finishes a CTA in ~6k cycles
// vs gemm's ~16k) doesn't expose a kernel shape-dependent timing window.
// response_delay can be overridden via +RD_DELAY=N (default 32).
//
// Kernel: nn_cuda (multi-CTA, 5 eblocks, 4 CTAs, MUL + squared-distance)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_nn_cuda_fetch_latency_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_nn_cuda_fetch_latency_test

class mini_dice_chip_nn_cuda_fetch_latency_test extends mini_dice_chip_nn_cuda_smoke_test;
  `uvm_component_utils(mini_dice_chip_nn_cuda_fetch_latency_test)
  int unsigned rd_delay = 32;

  function new(string name = "mini_dice_chip_nn_cuda_fetch_latency_test", uvm_component parent = null);
    super.new(name, parent);
    PER_CTA_TIMEOUT = 500_000;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    void'($value$plusargs("RD_DELAY=%d", rd_delay));
    env.mem_resp.response_delay_cyc = rd_delay;
    `uvm_info("NN_CUDA_LAT",
      $sformatf("response_delay_cyc=%0d", rd_delay), UVM_LOW)

    load_collateral();
    run_grid();
    finalize_grid_check();
    #100;
    phase.drop_objection(this);
  endtask
endclass
