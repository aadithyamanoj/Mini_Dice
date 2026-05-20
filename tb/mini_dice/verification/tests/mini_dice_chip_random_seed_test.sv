// mini_dice_chip_random_seed_test
// --------------------------------
// Runs the canonical full_mul_array with randomized mem_responder
// response delay (1..32) and settle window (200k..1M cycles). Complements
// the directed fetch_latency test by exercising a spread of delay values.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_random_seed_test +ntb_random_seed=42
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_random_seed_test +ntb_random_seed=42

class mini_dice_chip_random_seed_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_random_seed_test)

  rand int unsigned r_delay;
  rand int unsigned r_settle;
  constraint c_delay  { r_delay  inside {[1:32]}; }
  constraint c_settle { r_settle inside {[200_000:1_000_000]}; }

  function new(string name = "mini_dice_chip_random_seed_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    if (!this.randomize()) `uvm_fatal("RAND", "randomize() failed");
    env.mem_resp.response_delay_cyc = r_delay;
    SETTLE_CYCLES = r_settle;
    `uvm_info("RAND", $sformatf("delay=%0d settle=%0d", r_delay, SETTLE_CYCLES), UVM_LOW)
    load_collateral();
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask
endclass
