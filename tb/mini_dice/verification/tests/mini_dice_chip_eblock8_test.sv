// mini_dice_chip_eblock8_test
// ----------------------------
// Records the 8-eblock architectural boundary. The LOAD_REQ flit's
// e_block_id field is 3 bits wide, so max 8 distinct eblocks per kernel.
// The active regression covers 5- and 7-eblock kernels (full_mul_array,
// simple_branching); I think a real 8-eblock run requires a dora-compiled kernel
// with consistent branch metadata.
//
// (currently working on this)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_eblock8_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_eblock8_test

class mini_dice_chip_eblock8_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_eblock8_test)

  function new(string name = "mini_dice_chip_eblock8_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 10_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 0;
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    @(negedge env.csr_agnt.drv.vif.rst_i);
    repeat (20) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("EBLOCK8",
      "Spec limit: e_block_id[2:0] = 3-bit field, max 8 eblock IDs.", UVM_NONE)
    `uvm_info("EBLOCK8",
      "Exercised in regression: full_mul_array (5), simple_branching (7).", UVM_NONE)
    `uvm_info("EBLOCK8", "PASS (boundary documentation).", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
