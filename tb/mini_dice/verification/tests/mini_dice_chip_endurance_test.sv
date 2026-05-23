// mini_dice_chip_endurance_test
// ------------------------------
// Launches full_mul_array NUM_ITERS times back-to-back through the same
// single-CTA slot, re-pulsing CTRL.START between dispatches. Checks that
// each iteration retires its 64 stores. Catches FIFO leaks, counter
// rollover, and slot-reuse state-machine bugs.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL) — dispatched N times
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_endurance_test +ITERS=50
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_endurance_test +ITERS=50

class mini_dice_chip_endurance_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_endurance_test)

  int unsigned NUM_ITERS = 50;
  // full_mul_array is ~30k cycles; 200k per-iter timeout has plenty of slack.
  int unsigned PER_ITER_TIMEOUT = 200_000;

  function new(string name = "mini_dice_chip_endurance_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
    SETTLE_CYCLES = 5_000_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return NUM_ITERS * 64;
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq sub;
    int unsigned iter, cyc;
    int unsigned base_writes;
    int unsigned fails = 0;
    phase.raise_objection(this);

    load_collateral();
    void'($value$plusargs("ITERS=%d", NUM_ITERS));
    `uvm_info("ENDUR",
      $sformatf("Running %0d back-to-back full_mul_array iterations", NUM_ITERS),
      UVM_LOW)

    // First iteration uses full CSR program + start; later iterations
    // only re-pulse CTRL.START.
    program_and_launch();

    for (iter = 0; iter < NUM_ITERS; iter++) begin
      base_writes = (iter == 0) ? 0 : env.mem_resp.writes_observed;

      // Wait for this iteration's 64 stores.
      for (cyc = 0; cyc < PER_ITER_TIMEOUT; cyc++) begin
        @(posedge env.csr_agnt.drv.vif.clk_i);
        if ((env.mem_resp.writes_observed - base_writes) >= 64) break;
      end
      repeat (100) @(posedge env.csr_agnt.drv.vif.clk_i);

      if ((env.mem_resp.writes_observed - base_writes) < 64) begin
        fails++;
        `uvm_error("ENDUR",
          $sformatf("iter %0d: timed out at %0d stores (base=%0d)",
                    iter, env.mem_resp.writes_observed, base_writes))
        break;
      end

      if ((iter % 10) == 0)
        `uvm_info("ENDUR",
          $sformatf("iter %0d/%0d OK (writes_total=%0d)",
                    iter, NUM_ITERS, env.mem_resp.writes_observed),
          UVM_LOW)

      // Re-pulse CTRL.START for the next iteration (single-CTA slot reuse).
      if (iter + 1 < NUM_ITERS) begin
        sub = csr_one_shot_seq::type_id::create("sub_restart");
        sub.addr = REG_CTRL; sub.data = CTRL_START;
        sub.start(env.csr_agnt.seqr);
      end
    end

    if (fails == 0)
      `uvm_info("ENDUR",
        $sformatf("PASS: %0d iterations × 64 stores = %0d total writes observed",
                  NUM_ITERS, env.mem_resp.writes_observed), UVM_NONE)
    else
      `uvm_error("ENDUR",
        $sformatf("FAIL: %0d iterations did not complete", fails))

    #100;
    phase.drop_objection(this);
  endtask
endclass
