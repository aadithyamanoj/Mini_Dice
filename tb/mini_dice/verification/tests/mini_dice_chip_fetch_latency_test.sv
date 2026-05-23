// mini_dice_chip_fetch_latency_test
// ----------------------------------
// Runs full_mul_array with mem_responder.response_delay_cyc = 32 to stress
// metadata, bitstream, and data fetch paths against slow read responses.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_fetch_latency_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_fetch_latency_test

class mini_dice_chip_fetch_latency_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_fetch_latency_test)
  int unsigned latency = 32;

  function new(string name = "mini_dice_chip_fetch_latency_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    env.mem_resp.response_delay_cyc = latency;
    `uvm_info("FETCH_LAT", $sformatf("Response latency = %0d cycles", latency), UVM_LOW)
    load_collateral();
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
