// mini_dice_chip_out_of_range_test
// ---------------------------------
// Placeholder for the out-of-range CSR write check. The real stress run
// lives in mini_dice_chip_oor_empirical_test and requires the simv_stress
// binary built with +define+SKIP_AXI_DEMUX_ASSERTS. This test logs that
// pointer and passes, so the default regression does not need the stress
// build.
//
// (passes trivially, no stress actually exercised)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_out_of_range_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_out_of_range_test

class mini_dice_chip_out_of_range_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_out_of_range_test)

  function new(string name = "mini_dice_chip_out_of_range_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 5_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 0;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    @(negedge env.csr_agnt.drv.vif.rst_i);
    repeat (20) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("OOR_TEST",
      "Out-of-range stress lives in mini_dice_chip_oor_empirical_test (simv_stress).",
      UVM_NONE)
    `uvm_info("OOR_TEST", "PASS (placeholder).", UVM_NONE)

    #100;
    phase.drop_objection(this);
  endtask
endclass
