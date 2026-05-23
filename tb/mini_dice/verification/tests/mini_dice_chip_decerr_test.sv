// mini_dice_chip_decerr_test
// ---------------------------
// Runs full_mul_array with DECERR (rresp=2'b11) injected on one A-load.
// Companion to axil_error_test which uses SLVERR (2'b10) - DECERR takes
// a different path through the crossbar error slave.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_decerr_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_decerr_test

class mini_dice_chip_decerr_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_decerr_test)

  logic [15:0] err_addr = 16'h0001;

  function new(string name = "mini_dice_chip_decerr_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    env.mem_resp.read_resp_err[err_addr] = 2'b11;   // DECERR
    `uvm_info("DECERR",
      $sformatf("Injecting DECERR (rresp=2'b11) on addr 0x%04x", err_addr),
      UVM_LOW)
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
