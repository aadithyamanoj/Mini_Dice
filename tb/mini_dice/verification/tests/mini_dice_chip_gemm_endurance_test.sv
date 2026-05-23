// mini_dice_chip_gemm_endurance_test
// -----------------------------------
// Launches the gemm grid (4 CTAs * 16 threads) NUM_ITERS times back-to-back.
// Each iteration re-runs the full per-CTA program-START-poll sequence,
// stressing slot reuse with a 14-eblock multi-CTA workload over a
// long horizon (FIFO leaks, counter rollover, stale state between grids).
//
// Default NUM_ITERS=10 (~7M cycles total). Override with +ITERS=N.
//
// Kernel: gemm (multi-CTA, 14 eblocks, 4 CTAs, MUL + MAC) — N grids back-to-back
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_gemm_endurance_test +ITERS=10
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_gemm_endurance_test +ITERS=10

class mini_dice_chip_gemm_endurance_test extends mini_dice_chip_gemm_smoke_test;
  `uvm_component_utils(mini_dice_chip_gemm_endurance_test)
  int unsigned NUM_ITERS = 10;

  function new(string name = "mini_dice_chip_gemm_endurance_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 20_000_000;
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned iter;
    int unsigned base_writes;
    int unsigned per_iter_target;
    phase.raise_objection(this);
    void'($value$plusargs("ITERS=%d", NUM_ITERS));
    per_iter_target = 64;  // 4 CTAs * 16 threads

    load_collateral();
    `uvm_info("GEMM_ENDUR",
      $sformatf("Running %0d back-to-back gemm grids (%0d total stores expected)",
                NUM_ITERS, NUM_ITERS * per_iter_target), UVM_LOW)

    for (iter = 0; iter < NUM_ITERS; iter++) begin
      base_writes = env.mem_resp.writes_observed;
      run_grid();
      // Brief drain between iterations.
      repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
      if ((env.mem_resp.writes_observed - base_writes) < per_iter_target) begin
        `uvm_error("GEMM_ENDUR",
          $sformatf("iter %0d: only %0d stores in this grid (expected %0d, total=%0d)",
                    iter, env.mem_resp.writes_observed - base_writes,
                    per_iter_target, env.mem_resp.writes_observed))
        break;
      end
      if ((iter % 5) == 0)
        `uvm_info("GEMM_ENDUR",
          $sformatf("iter %0d/%0d OK (total writes=%0d)",
                    iter, NUM_ITERS, env.mem_resp.writes_observed), UVM_LOW)
    end

    `uvm_info("GEMM_ENDUR",
      $sformatf("Done: %0d iters * %0d expected = %0d, observed=%0d",
                NUM_ITERS, per_iter_target, NUM_ITERS * per_iter_target,
                env.mem_resp.writes_observed), UVM_NONE)

    // Each iteration writes to the same 64 addresses (same kernel, same
    // CSRs), so unique_addrs stays at 64. Pass criterion is the total
    // store COUNT — iterations * 64.
    if (env.mem_resp.writes_observed >= NUM_ITERS * per_iter_target)
      `uvm_info("GEMM_ENDUR",
        $sformatf("PASS: %0d back-to-back grids retired %0d stores",
                  NUM_ITERS, env.mem_resp.writes_observed), UVM_NONE)
    else
      `uvm_error("GEMM_ENDUR",
        $sformatf("FAIL: only %0d stores after %0d iterations (expected %0d)",
                  env.mem_resp.writes_observed, NUM_ITERS,
                  NUM_ITERS * per_iter_target))

    #100;
    phase.drop_objection(this);
  endtask
endclass
