// dice_core_full_mul_array_test
// -----------------------------
// Baseline end-to-end test: 5-eblock A*B pipeline, 16 threads, 64 stores.
// Parent class for most other tests — they override
// setup_thread_inputs_and_expectations() to swap in different data.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_full_mul_array_test +UVM_VERBOSITY=UVM_LOW

class cta_full_mul_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_full_mul_seq)
  cta_seq_item item;
  function new(string name = "cta_full_mul_seq"); super.new(name); endfunction
  task body();
    item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = 16'h1000;
    item.thread_count = 16;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = '{x: 0, y: 0, z: 0};
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_full_mul_array_test extends dice_core_base_test;
  `uvm_component_utils(dice_core_full_mul_array_test)

  // ~50M cycles: 16 threads × 5 kernels × ~1100-cycle programming amortized,
  // plus AXI-Lite traffic. Generous to avoid premature timeout while we shake
  // out the new design.
  localparam int TIMEOUT_CYCLES = 50_000_000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Subclasses can override to swap inputs/CSRs/expectations.
  // Default loads everything from the auto-generated include file.
  virtual function void setup_thread_inputs_and_expectations();
    `include "test_data_full_mul_array.svh"
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_full_mul_seq seq;

    // Load metadata, bitstreams, AXI-Lite mem, expected stores, CSRs
    setup_thread_inputs_and_expectations();

    // Dispatch
    seq = cta_full_mul_seq::type_id::create("seq");
    seq.start(env.cta_agnt.seqr);
    `uvm_info("FULL_MUL",
      $sformatf("CTA dispatched: %s", seq.item.convert2string()), UVM_NONE)

    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("FULL_MUL", "cta_complete_valid asserted", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("FULL_MUL",
          $sformatf("Timeout after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    #100;
  endtask

endclass
