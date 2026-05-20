// mini_dice_chip_meta_error_test
// -------------------------------
// Runs full_mul_array with SLVERR injected on the eblock-0 metadata fetch
// burst (kind=0). Exercises the mfetch unit's rresp path, which is a
// different code branch from the data-load rresp path.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_meta_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_meta_error_test

class mini_dice_chip_meta_error_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_meta_error_test)

  // Eblock 0 metadata sits at start_pc = 0x1000 for full_mul_array.
  logic [15:0] err_addr = 16'h1000;

  function new(string name = "mini_dice_chip_meta_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    env.mem_resp.meta_resp_err[err_addr] = 2'b10;   // SLVERR on meta fetch
    `uvm_info("META_ERR",
      $sformatf("Injecting SLVERR on metadata fetch addr=0x%04x (eblock 0)",
                err_addr), UVM_LOW)
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
