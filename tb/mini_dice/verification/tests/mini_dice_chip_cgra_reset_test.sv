// mini_dice_chip_cgra_reset_test
// -------------------------------
// Pulses CTRL.CGRA_RESET (bit 1 of REG_CTRL) to soft-reset the CGRA
// fabric only, then launches full_mul_array and checks it completes.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_cgra_reset_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_cgra_reset_test

class mini_dice_chip_cgra_reset_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_cgra_reset_test)

  function new(string name = "mini_dice_chip_cgra_reset_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq sub;
    int unsigned cyc;
    phase.raise_objection(this);

    load_collateral();

    // Assert CGRA reset.
    sub = csr_one_shot_seq::type_id::create("sub_cgra_rst_asrt");
    sub.addr = REG_CTRL; sub.data = CTRL_CGRA_RESET;
    sub.start(env.csr_agnt.seqr);
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    // Release CGRA reset.
    sub = csr_one_shot_seq::type_id::create("sub_cgra_rst_rels");
    sub.addr = REG_CTRL; sub.data = 16'h0000;
    sub.start(env.csr_agnt.seqr);
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("CGRA_RST", "Soft CGRA reset cycle complete", UVM_LOW)

    // Launch full_mul_array and check it completes after the soft reset.
    program_and_launch();
    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= 64) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    env.sb.final_writes_seen = env.mem_resp.writes_observed;
    env.sb.check_done();
    #100;
    phase.drop_objection(this);
  endtask
endclass
