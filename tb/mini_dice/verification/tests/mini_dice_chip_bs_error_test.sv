// mini_dice_chip_bs_error_test
// -----------------------------
// Runs full_mul_array with SLVERR injected on the eblock-0 bitstream
// fetch burst. Verifies the chip does not deadlock on a non-OKAY rresp
// from the kind=2 (bitstream) fetch path.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_bs_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_bs_error_test

class mini_dice_chip_bs_error_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_bs_error_test)

  // Eblock 0 bitstream base for full_mul_array.
  logic [15:0] err_addr = 16'h0000;

  function new(string name = "mini_dice_chip_bs_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    env.mem_resp.bs_resp_err[err_addr] = 2'b10;   // SLVERR on bs fetch
    `uvm_info("BS_ERR",
      $sformatf("Injecting SLVERR on bitstream fetch addr=0x%04x (eblock 0)",
                err_addr), UVM_LOW)
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
