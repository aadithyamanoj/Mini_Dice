// mini_dice_chip_gemm_cgra_reset_test
// ------------------------------------
// Pulses CTRL.CGRA_RESET between CTA 1 and CTA 2 of the gemm grid, then
// verifies the remaining CTAs still complete. Stresses the interaction
// between the CGRA soft-reset path and the per-CTA dispatch loop
// (sequential dispatch through the single CTA slot) — neither was
// exercised together before.
//
// Kernel: gemm (multi-CTA, 14 eblocks, 4 CTAs, MUL + MAC)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_gemm_cgra_reset_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_gemm_cgra_reset_test

class mini_dice_chip_gemm_cgra_reset_test extends mini_dice_chip_gemm_smoke_test;
  `uvm_component_utils(mini_dice_chip_gemm_cgra_reset_test)

  function new(string name = "mini_dice_chip_gemm_cgra_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq sub;
    phase.raise_objection(this);
    load_collateral();

    // Kernel-wide CSRs first.
    sub = csr_one_shot_seq::type_id::create("sub_pc");
    sub.addr = REG_STARTPC; sub.data = start_pc;
    sub.start(env.csr_agnt.seqr);
    sub = csr_one_shot_seq::type_id::create("sub_tc");
    sub.addr = REG_THREAD_COUNT; sub.data = thread_count;
    sub.start(env.csr_agnt.seqr);

    // Dispatch CTAs 0, 1.
    for (int unsigned c = 0; c < 2; c++) begin
      program_csrs_for_cta(c);
      pulse_start();
      wait_for_cta_done(c);
    end

    // Soft-reset the CGRA between CTA 1 and CTA 2.
    `uvm_info("GEMM_CGRA_RST",
      "Pulsing CTRL.CGRA_RESET between CTA 1 and CTA 2", UVM_LOW)
    sub = csr_one_shot_seq::type_id::create("sub_cgra_asrt");
    sub.addr = REG_CTRL; sub.data = CTRL_CGRA_RESET;
    sub.start(env.csr_agnt.seqr);
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
    sub = csr_one_shot_seq::type_id::create("sub_cgra_rels");
    sub.addr = REG_CTRL; sub.data = 16'h0000;
    sub.start(env.csr_agnt.seqr);
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    // Dispatch CTAs 2, 3.
    for (int unsigned c = 2; c < num_ctas; c++) begin
      program_csrs_for_cta(c);
      pulse_start();
      wait_for_cta_done(c);
    end

    finalize_grid_check();
    #100;
    phase.drop_objection(this);
  endtask
endclass
