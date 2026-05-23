// mini_dice_chip_axil_error_test
// -------------------------------
// Runs full_mul_array with SLVERR (rresp=2'b10) injected on one A-load
// address. Verifies the chip does not deadlock and the remaining lanes
// still deliver correct store data.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_axil_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_axil_error_test

class mini_dice_chip_axil_error_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_axil_error_test)

  // tid 0, lane 0 A address: csrX0=1, csrX3=4, csrX4=0 → addr 0x01.
  logic [15:0] err_addr = 16'h0001;

  function new(string name = "mini_dice_chip_axil_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    load_collateral();
    // mem_responder still returns correct read data; only rresp is non-OKAY.
    env.mem_resp.read_resp_err[err_addr] = 2'b10;
    `uvm_info("AXIL_ERR",
      $sformatf("Injecting SLVERR (rresp=2'b10) on read addr 0x%04x", err_addr),
      UVM_LOW)

    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
