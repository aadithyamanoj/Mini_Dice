// mini_dice_chip_port_contention_test
// ------------------------------------
// Runs full_mul_array with csrX4..7 forced to 0 so all four mem ports
// collide on the same A/B/C address per tid. Stresses crossbar
// arbitration with 4-way same-address store contention. Expects 64
// store ops total but only 16 unique addresses.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL) with csrX4..7=0
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_port_contention_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_port_contention_test

class mini_dice_chip_port_contention_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_port_contention_test)

  function new(string name = "mini_dice_chip_port_contention_test", uvm_component parent = null);
    super.new(name, parent);
    test_vector_name = "full_mul_array_test_vector";
  endfunction

  virtual function int unsigned expected_write_count();
    // 16 tids * 4 ports = 64 store ops emitted; only 16 unique addresses.
    return 64;
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    int unsigned unique_addrs;
    logic [15:0] a;
    phase.raise_objection(this);

    load_collateral();
    // Collapse lane offsets so all 4 ports compute the same address per tid.
    csr_values[4] = 16'd0;
    csr_values[5] = 16'd0;
    csr_values[6] = 16'd0;
    csr_values[7] = 16'd0;
    `uvm_info("CONTEND",
      "csrX4..7 = 0 → all 4 mem ports collide on the same addr per tid",
      UVM_LOW)

    program_and_launch();

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= 64) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    unique_addrs = env.mem_resp.local_writes.size();
    `uvm_info("CONTEND",
      $sformatf("writes_observed=%0d, unique_addrs=%0d (expected 16 unique)",
                env.mem_resp.writes_observed, unique_addrs), UVM_LOW)

    if (env.mem_resp.writes_observed >= 64 && unique_addrs <= 16)
      `uvm_info("CONTEND",
        $sformatf("PASS: 4-port store contention handled (%0d writes, %0d unique)",
                  env.mem_resp.writes_observed, unique_addrs), UVM_NONE)
    else
      `uvm_error("CONTEND",
        $sformatf("FAIL: writes=%0d unique=%0d (chip may have deadlocked or duplicated)",
                  env.mem_resp.writes_observed, unique_addrs))

    #100;
    phase.drop_objection(this);
  endtask
endclass
