// mini_dice_chip_gemm_fetch_latency_test
// ---------------------------------------
// gemm under elevated mem_responder read latency. Stresses the per-CTA
// dispatch loop (run_grid path: program-START-poll repeated for each CTA
// in the 4-CTA grid through the chip's single CTA slot) against slow
// metadata/bitstream/data fetches. Override delay via +RD_DELAY=N
// (default 32 cycles).
//
// Kernel: gemm (multi-CTA, 14 eblocks, 4 CTAs, MUL + MAC)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_gemm_fetch_latency_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_gemm_fetch_latency_test

class mini_dice_chip_gemm_fetch_latency_test extends mini_dice_chip_gemm_smoke_test;
  `uvm_component_utils(mini_dice_chip_gemm_fetch_latency_test)
  int unsigned rd_delay = 32;

  function new(string name = "mini_dice_chip_gemm_fetch_latency_test", uvm_component parent = null);
    super.new(name, parent);
    // Each CTA takes longer with slow fetches; bump per-CTA timeout.
    PER_CTA_TIMEOUT = 1_000_000;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    void'($value$plusargs("RD_DELAY=%d", rd_delay));
    env.mem_resp.response_delay_cyc = rd_delay;
    `uvm_info("GEMM_LAT",
      $sformatf("response_delay_cyc=%0d", rd_delay), UVM_LOW)

    load_collateral();
    run_grid();
    finalize_grid_check();
    #100;
    phase.drop_objection(this);
  endtask
endclass
