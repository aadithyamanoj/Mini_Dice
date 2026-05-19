// dice_core_fetch_latency_test
// ----------------------------
// full_mul_array_test with 8-cycle response latency on mfetch + bsfetch.
// Exercises AR-to-first-R backpressure handling in the FE.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_fetch_latency_test +UVM_VERBOSITY=UVM_LOW
class dice_core_fetch_latency_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_fetch_latency_test)

  // Cycles between AR accept and first R beat on each fetch port.
  // 8 is enough to make the FE wait visibly without bloating runtime.
  int unsigned fetch_resp_latency = 8;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_body(uvm_phase phase);
    env.mfetch_agnt.drv.resp_latency  = fetch_resp_latency;
    env.bsfetch_agnt.drv.resp_latency = fetch_resp_latency;
    `uvm_info("LAT_TEST",
      $sformatf("AXI read latency = %0d cycles on mfetch and bsfetch",
                fetch_resp_latency), UVM_NONE)
    super.run_body(phase);
  endtask

endclass
