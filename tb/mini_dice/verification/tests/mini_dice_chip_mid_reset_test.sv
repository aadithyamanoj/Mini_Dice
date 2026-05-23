// mini_dice_chip_mid_reset_test
// ------------------------------
// Asserts reset mid-kernel, then re-launches full_mul_array and checks
// the chip recovers.
//   FAST: drives rst_i via the vif's force_rst_* hooks.
//   CHIP: pulses vif.force_bringup; tb_chip's watcher calls
//         bsg_link_bringup() which pulses hard_reset PAD (re-triggering
//         chip_top's internal reset_cnt staging) AND re-handshakes the
//         FPGA-side link counters, so both sides come out in sync.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_mid_reset_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_mid_reset_test

class mini_dice_chip_mid_reset_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_mid_reset_test)

  function new(string name = "mini_dice_chip_mid_reset_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    bit chip_mode;
    phase.raise_objection(this);

    chip_mode = 0;
    void'(uvm_config_db #(int)::get(null, "*", "CHIP_MODE", chip_mode));

    load_collateral();
    program_and_launch();

    `uvm_info("MID_RST", "Letting kernel run 20K cycles before reset...", UVM_LOW)
    repeat (20_000) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("MID_RST", $sformatf("Asserting reset (writes_so_far=%0d)",
              env.mem_resp.writes_observed), UVM_LOW)

    if (chip_mode) begin
      // Pulse the vif trigger; tb_chip's watcher runs bsg_link_bringup
      // (asserts hard_reset + all FPGA-side link resets, then walks the
      // staged release). Watcher clears force_bringup when done.
      env.csr_agnt.drv.vif.force_bringup = 1'b1;
      wait(env.csr_agnt.drv.vif.force_bringup == 1'b0);
    end else begin
      // FAST-mode: drive rst_i directly via the vif force hook.
      env.csr_agnt.drv.vif.force_rst_val = 1'b1;
      env.csr_agnt.drv.vif.force_rst_en  = 1'b1;
      repeat (50) @(posedge env.csr_agnt.drv.vif.clk_i);
      env.csr_agnt.drv.vif.force_rst_val = 1'b0;
      repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
      env.csr_agnt.drv.vif.force_rst_en  = 1'b0;
    end
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
