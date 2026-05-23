// mini_dice_chip_partial_thread_test
// -----------------------------------
// Runs full_mul_array with thread_count=9 (non-power-of-two < 16) to
// exercise the dispatcher's partial active mask. Expected store count
// is tcount * 4 = 36.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL) with tcount=9
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_partial_thread_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_partial_thread_test

class mini_dice_chip_partial_thread_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_partial_thread_test)
  int unsigned tcount = 9;

  function new(string name = "mini_dice_chip_partial_thread_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  virtual function int unsigned expected_write_count();
    return tcount * 4;
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    phase.raise_objection(this);
    load_collateral();
    // Overwrite the 16-thread default loaded from the vector.
    thread_count = 16'(tcount);
    `uvm_info("PARTIAL", $sformatf("Override thread_count -> %0d", tcount), UVM_LOW)
    program_and_launch();

    // Skip DPI check_done — the runtime JSON expects all 16 threads' writes.
    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= expected_write_count()) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    if (env.mem_resp.writes_observed == expected_write_count())
      `uvm_info("PARTIAL", $sformatf("PASS: %0d writes observed (= tcount*4)",
                env.mem_resp.writes_observed), UVM_NONE)
    else
      `uvm_error("PARTIAL", $sformatf("FAIL: %0d writes (expected %0d)",
                 env.mem_resp.writes_observed, expected_write_count()))

    #100;
    phase.drop_objection(this);
  endtask
endclass
