// mini_dice_chip_csr_smoke_test
// ------------------------------
// CSR-only sanity check: writes 8 CSRs plus start_pc / thread_count and
// confirms the link traffic completes without errors. Does not launch a CTA.
//
// Kernel: none (CSR-only, no CTA dispatch)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_csr_smoke_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_csr_smoke_test

class mini_dice_chip_csr_smoke_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_csr_smoke_test)

  function new(string name = "mini_dice_chip_csr_smoke_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 20_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 0;
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq sub;
    int unsigned i;
    phase.raise_objection(this);

    @(negedge env.csr_agnt.drv.vif.rst_i);
    repeat (20) @(posedge env.csr_agnt.drv.vif.clk_i);

    // 8 distinct CSR writes.
    for (i = 0; i < 8; i++) begin
      sub = csr_one_shot_seq::type_id::create("sub");
      sub.addr = REG_CSRX0 + 16'(i * 2);
      sub.data = 16'h1100 + 16'(i);
      sub.start(env.csr_agnt.seqr);
    end

    // Program start_pc + thread_count, but do NOT pulse CTRL.START.
    sub = csr_one_shot_seq::type_id::create("sub_pc");
    sub.addr = REG_STARTPC;     sub.data = 16'h1000;
    sub.start(env.csr_agnt.seqr);
    sub = csr_one_shot_seq::type_id::create("sub_tc");
    sub.addr = REG_THREAD_COUNT; sub.data = 16'd16;
    sub.start(env.csr_agnt.seqr);

    repeat (500) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("CSR_SMOKE", "10 CSR writes traversed link without errors", UVM_LOW)

    phase.drop_objection(this);
  endtask
endclass
