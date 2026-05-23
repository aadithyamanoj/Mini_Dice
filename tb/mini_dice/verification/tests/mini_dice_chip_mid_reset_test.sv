// mini_dice_chip_mid_reset_test
// ------------------------------
// In FAST mode: asserts reset mid-kernel via the vif force hooks, then
// re-launches full_mul_array and checks recovery.
// In CHIP mode: logs-and-exits — a runtime hard_reset PAD pulse alone
// does not fully reset the bsg_link credit counters, and the test cannot
// replay the multi-step bsg_link bringup from inside run_phase. Would
// need that bringup factored out into a reusable task in tb_chip.sv.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL) — FAST only
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_mid_reset_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_mid_reset_test  (skips)

class mini_dice_chip_mid_reset_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_mid_reset_test)

  function new(string name = "mini_dice_chip_mid_reset_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq sub;
    int unsigned cyc;
    bit chip_mode;
    phase.raise_objection(this);

    // tb_chip.sv sets CHIP_MODE; tb_top.sv leaves it unset.
    chip_mode = 0;
    void'(uvm_config_db #(int)::get(null, "*", "CHIP_MODE", chip_mode));

    if (chip_mode) begin
      `uvm_info("MID_RST",
        "Skipped in CHIP mode (bsg_link credit counters require full bringup).",
        UVM_NONE)
      phase.drop_objection(this);
      return;
    end

    load_collateral();
    program_and_launch();

    `uvm_info("MID_RST", "Letting kernel run 20K cycles before reset...", UVM_LOW)
    repeat (20_000) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("MID_RST", $sformatf("Asserting reset (writes_so_far=%0d)",
              env.mem_resp.writes_observed), UVM_LOW)
    // Drive rst_i via the vif force hooks (only available in FAST mode).
    env.csr_agnt.drv.vif.force_rst_val = 1'b1;
    env.csr_agnt.drv.vif.force_rst_en  = 1'b1;
    repeat (50) @(posedge env.csr_agnt.drv.vif.clk_i);
    env.csr_agnt.drv.vif.force_rst_val = 1'b0;
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
    env.csr_agnt.drv.vif.force_rst_en = 1'b0;
    `uvm_info("MID_RST", "Reset deasserted", UVM_LOW)
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    // Clear pre-reset write tracking so the post-reset count starts at 0.
    env.mem_resp.writes_observed = 0;
    env.mem_resp.local_writes.delete();

    `uvm_info("MID_RST", "Re-launching", UVM_LOW)
    program_and_launch();

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= 64) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    if (env.mem_resp.writes_observed >= 64)
      `uvm_info("MID_RST",
        $sformatf("PASS: chip recovered after mid-test reset; %0d post-reset writes",
                  env.mem_resp.writes_observed), UVM_NONE)
    else
      `uvm_error("MID_RST",
        $sformatf("FAIL: only %0d writes after re-launch", env.mem_resp.writes_observed))

    #100;
    phase.drop_objection(this);
  endtask
endclass
