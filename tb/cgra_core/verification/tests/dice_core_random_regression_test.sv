// dice_core_random_regression_test
// --------------------------------
// Constrained-random regression with functional coverage. Randomizes:
//   - thread_count    (1..32)
//   - inject_err      (whether to inject SLVERR on one load)
//   - err_addr        (which load address if injecting)
//   - fetch_latency   (mfetch/bsfetch resp_latency, 0..16)
//
// Run many seeds and merge coverage to see which (thread_count × error ×
// latency) bins have been hit. Each invocation runs one random config.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_random_regression_test \
//           +UVM_VERBOSITY=UVM_LOW +ntb_random_seed=<N>
//
// For coverage sweeps, run with many seeds and merge with `urg`.

// Local sequence: dispatches one CTA with a caller-set thread_count.
class cta_random_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_random_seq)
  cta_seq_item item;
  int unsigned tcount = 32;
  function new(string name = "cta_random_seq"); super.new(name); endfunction
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


class dice_core_random_regression_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_random_regression_test)

  // Randomizable knobs
  rand int unsigned r_tcount;
  rand bit          r_inject_err;
  rand logic [15:0] r_err_addr;
  rand int unsigned r_fetch_latency;

  constraint c_tcount  { r_tcount inside {[1:32]}; }
  constraint c_err     {
    // 50/50 error injection
    r_inject_err dist {0 := 1, 1 := 1};
    // If injecting, pick a real load address (A or B range under csrX0=1)
    if (r_inject_err) r_err_addr inside {[16'h0001:16'h00FF]};
    else              r_err_addr == 16'h0000;
  }
  constraint c_latency { r_fetch_latency inside {0, 1, 2, 4, 8, 16}; }

  // Functional coverage. Sampled once per test invocation. To get meaningful
  // numbers, run many seeds with simv and merge coverage with urg.
  covergroup cg_random;
    cp_tcount: coverpoint r_tcount {
      bins b_one      = {1};
      bins b_2_8      = {[2:8]};
      bins b_9_16     = {[9:16]};
      bins b_17_24    = {[17:24]};
      bins b_25_31    = {[25:31]};
      bins b_32       = {32};
    }
    cp_err: coverpoint r_inject_err {
      bins b_no_err   = {0};
      bins b_with_err = {1};
    }
    cp_lat: coverpoint r_fetch_latency {
      bins b_0   = {0};
      bins b_1   = {1};
      bins b_2_4 = {[2:4]};
      bins b_5_8 = {[5:8]};
      bins b_hi  = {[9:16]};
    }
    // The crosses are where bugs hide
    cross_tcount_err: cross cp_tcount, cp_err;
    cross_tcount_lat: cross cp_tcount, cp_lat;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_random = new();
  endfunction

  // Compute expected stores for the randomized tcount and (optionally) the
  // SLVERR injection. Same A*B math as partial_thread_test.
  virtual function void setup_thread_inputs_and_expectations();
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;

    super.setup_thread_inputs_and_expectations();  // canonical 128 expects
    env.sb.expected_data.delete();
    env.sb.stores_expected = 0;

    for (int t = 0; t < int'(r_tcount); t++) begin
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

    if (r_inject_err) begin
      env.axil_agnt.drv.read_resp_err[r_err_addr] = 2'b10;
      env.sb.expect_axil_error(r_err_addr);
    end

    `uvm_info("RAND_REG",
      $sformatf("Random config: tcount=%0d err=%0b err_addr=0x%04x lat=%0d → %0d stores expected",
                r_tcount, r_inject_err, r_err_addr, r_fetch_latency, r_tcount*4),
      UVM_LOW)
  endfunction

  // Override run_body to randomize first, then dispatch with the random tcount.
  virtual task run_body(uvm_phase phase);
    if (!this.randomize()) `uvm_fatal("RAND_REG", "test-level randomize() failed");
    cg_random.sample();

    // Apply latency knob before setup so it's in place when fetches begin
    env.mfetch_agnt.drv.resp_latency  = r_fetch_latency;
    env.bsfetch_agnt.drv.resp_latency = r_fetch_latency;

    setup_thread_inputs_and_expectations();

    // Dispatch with the random tcount
    begin
      cta_random_seq seq = cta_random_seq::type_id::create("seq");
      seq.tcount = r_tcount;
      seq.start(env.cta_agnt.seqr);
    end

    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("RAND_REG", "cta_complete_valid asserted", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("RAND_REG", $sformatf("Timeout after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    `uvm_info("RAND_REG",
      $sformatf("Single-seed coverage: cg_random=%.1f%% (run more seeds for meaningful aggregate)",
                cg_random.get_coverage()),
      UVM_NONE)

    #100;
  endtask

endclass
