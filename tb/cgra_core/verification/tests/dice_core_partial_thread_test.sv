// dice_core_partial_thread_test
// -----------------------------
// full_mul_array_test dispatched with thread_count=17 (a non-power-of-two
// count that's < 32). Exercises the dispatcher with active_mask=0x0001FFFF
// — the only test in the suite that uses a partial mask. Expected count:
// 68 stores (17 threads * 4 lanes).
//
// Subclass and override `tcount` to sweep other counts (1, 16, 24, 31, ...).
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_partial_thread_test +UVM_VERBOSITY=UVM_LOW

class cta_partial_thread_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_partial_thread_seq)
  cta_seq_item item;
  int unsigned tcount = 17;
  function new(string name = "cta_partial_thread_seq"); super.new(name); endfunction
  task body();
    item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = 16'h1000;
    item.thread_count = tcount;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = '{x: 0, y: 0, z: 0};
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_partial_thread_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_partial_thread_test)

  // Number of active threads in the CTA. 17 is the canonical non-power-of-two
  // probe; subclasses can override for sweeps (1, 5, 16, 17, 24, 31).
  int unsigned tcount = 17;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Same canonical kernel data, but trim the expected stores to only the
  // first `tcount` threads worth (4 * tcount). Stores from tids >= tcount
  // would be a bug — they get caught as "unexpected store" by the scoreboard.
  virtual function void setup_thread_inputs_and_expectations();
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;

    super.setup_thread_inputs_and_expectations();   // 128 canonical expects
    env.sb.expected_data.delete();                   // wipe
    env.sb.stores_expected = 0;

    // Re-register only the first `tcount * 4` stores.
    // read_mem[i] = i, so A[t][k] = mem[1+4t+k] = 1+4t+k and similarly for B.
    for (int t = 0; t < int'(tcount); t++) begin
      for (int k = 0; k < 4; k++) begin
        a_addr   = 16'(1   + 4*t + k);
        b_addr   = 16'(128 + 4*t + k);
        c_addr   = 16'(256 + 4*t + k);
        a_val    = a_addr;
        b_val    = b_addr;
        expected = a_val * b_val;
        env.sb.expect_store(c_addr, expected);
      end
    end

    `uvm_info("PARTIAL",
      $sformatf("Expecting %0d stores from tids 0..%0d (thread_count=%0d, active_mask=0x%08x)",
                tcount*4, tcount-1, tcount, (32'h1 << tcount) - 1), UVM_LOW)
  endfunction

  // Override run_body to dispatch with `tcount` threads instead of 32.
  virtual task run_body(uvm_phase phase);
    cta_partial_thread_seq seq;
    setup_thread_inputs_and_expectations();

    seq = cta_partial_thread_seq::type_id::create("seq");
    seq.tcount = tcount;
    seq.start(env.cta_agnt.seqr);
    `uvm_info("PARTIAL",
      $sformatf("CTA dispatched: %s", seq.item.convert2string()), UVM_NONE)

    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("PARTIAL", "cta_complete_valid asserted", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("PARTIAL",
          $sformatf("Timeout after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    #100;
  endtask

endclass
