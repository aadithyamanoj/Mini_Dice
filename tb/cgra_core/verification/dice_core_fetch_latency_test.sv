// Fetch-latency test: identical to full_mul_array_test but with extra AXI4
// read latency injected on both fetch ports.
// Exercises AR-to-first-R backpressure handling in meta_fetch and
// bitstream_fetch_load while preserving end-to-end correctness checks
// (5 bitstream epochs + 4 store addr/data verified bit/word-exact).
//
// Inheriting from full_mul_array_test (rather than smoke_test) avoids the
// IO-less single-eblock kernel premature-complete race and gives us real
// observable IO to verify under slow-fetch conditions.
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
