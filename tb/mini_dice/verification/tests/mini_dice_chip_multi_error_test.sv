// mini_dice_chip_multi_error_test
// --------------------------------
// Runs full_mul_array with SLVERR injected on all 4 A-load addresses of
// tid 0 simultaneously. Checks the chip handles concurrent error rresps
// across all four mem ports without deadlock.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_multi_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_multi_error_test

class mini_dice_chip_multi_error_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_multi_error_test)

  function new(string name = "mini_dice_chip_multi_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    // tid 0, lanes 0..3 A-loads: csrX0 + 4*0 + lane = 1, 2, 3, 4.
    env.mem_resp.read_resp_err[16'h0001] = 2'b10;
    env.mem_resp.read_resp_err[16'h0002] = 2'b10;
    env.mem_resp.read_resp_err[16'h0003] = 2'b10;
    env.mem_resp.read_resp_err[16'h0004] = 2'b10;
    `uvm_info("MULTI_ERR",
      "Injecting SLVERR on 4 addresses (tid 0 lanes 0..3 A-loads)", UVM_LOW)
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
