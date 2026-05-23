// mini_dice_chip_branch_axil_error_test
// --------------------------------------
// Runs simple_branching with SLVERR injected on tid 0's A-load. Exercises
// rresp routing through the SIMT divergence + reconvergence machinery.
//
// Kernel: simple_branching (single-CTA, 7 eblocks, MUL + ADD via divergence)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_branch_axil_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_branch_axil_error_test

class mini_dice_chip_branch_axil_error_test extends mini_dice_chip_simple_branching_test;
  `uvm_component_utils(mini_dice_chip_branch_axil_error_test)

  // tid 0, lane 0 A address.
  logic [15:0] err_addr = 16'h0001;

  function new(string name = "mini_dice_chip_branch_axil_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    env.mem_resp.read_resp_err[err_addr] = 2'b10;
    `uvm_info("BRANCH_ERR",
      $sformatf("simple_branching + SLVERR on 0x%04x", err_addr), UVM_LOW)
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
