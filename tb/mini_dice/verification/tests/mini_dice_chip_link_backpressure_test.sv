// mini_dice_chip_link_backpressure_test
// --------------------------------------
// Runs full_mul_array with mem_responder.response_delay_cyc = 64
// (~6.4x baseline) to back-pressure the chip read path and stress the
// chip-internal axi_link FIFOs and crossbar against slow responses.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_link_backpressure_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_link_backpressure_test

class mini_dice_chip_link_backpressure_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_link_backpressure_test)
  function new(string name = "mini_dice_chip_link_backpressure_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    env.mem_resp.response_delay_cyc = 64;
    `uvm_info("LINK_BP",
      $sformatf("Setting response_delay_cyc = %0d", env.mem_resp.response_delay_cyc),
      UVM_LOW)
    load_collateral();
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
