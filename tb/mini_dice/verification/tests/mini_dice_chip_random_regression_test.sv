// mini_dice_chip_random_regression_test
// --------------------------------------
// Constrained-random dispatch test on the canonical full_mul_array.
// Per run randomizes thread_count (1..16), SLVERR injection on/off and
// its address, and the mem_responder fetch_latency. Samples cg_random
// covergroup. Designed to be re-run across many seeds with urg merge.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_random_regression_test +ntb_random_seed=42
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_random_regression_test +ntb_random_seed=42

class mini_dice_chip_random_regression_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_random_regression_test)

  rand int unsigned r_tcount;
  rand bit          r_inject_err;
  rand logic [15:0] r_err_addr;
  rand int unsigned r_fetch_latency;

  constraint c_tcount  { r_tcount inside {[1:16]}; }
  constraint c_err {
    r_inject_err dist {0 := 1, 1 := 1};
    // Canonical full_mul_array A range or B range.
    if (r_inject_err) r_err_addr inside {[16'h0001:16'h0040], [16'h0080:16'h00BF]};
    else              r_err_addr == 16'h0000;
  }
  constraint c_latency { r_fetch_latency inside {0, 1, 2, 4, 8, 16}; }

  covergroup cg_random;
    cp_tcount: coverpoint r_tcount {
      bins b_one    = {1};
      bins b_2_4    = {[2:4]};
      bins b_5_8    = {[5:8]};
      bins b_9_12   = {[9:12]};
      bins b_13_15  = {[13:15]};
      bins b_16     = {16};
    }
    cp_err: coverpoint r_inject_err {
      bins b_no_err   = {0};
      bins b_with_err = {1};
    }
    cp_lat: coverpoint r_fetch_latency {
      bins b_0    = {0};
      bins b_1    = {1};
      bins b_2_4  = {[2:4]};
      bins b_5_8  = {[5:8]};
      bins b_hi   = {[9:16]};
    }
    cross_tcount_err: cross cp_tcount, cp_err;
    cross_tcount_lat: cross cp_tcount, cp_lat;
  endgroup

  function new(string name = "mini_dice_chip_random_regression_test", uvm_component parent = null);
    super.new(name, parent);
    cg_random = new();
  endfunction

  virtual function int unsigned expected_write_count();
    return r_tcount * 4;
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    phase.raise_objection(this);

    if (!this.randomize()) `uvm_fatal("RAND_REG", "randomize() failed");
    cg_random.sample();
    `uvm_info("RAND_REG",
      $sformatf("config: tcount=%0d err=%0b err_addr=0x%04x lat=%0d → %0d stores",
                r_tcount, r_inject_err, r_err_addr, r_fetch_latency, r_tcount*4),
      UVM_LOW)

    env.mem_resp.response_delay_cyc = r_fetch_latency;
    load_collateral();
    thread_count = 16'(r_tcount);
    if (r_inject_err)
      env.mem_resp.read_resp_err[r_err_addr] = 2'b10;

    program_and_launch();

    // Skip DPI check_done — runtime JSON assumes all 16 threads.
    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= r_tcount * 4) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    if (env.mem_resp.writes_observed == r_tcount * 4)
      `uvm_info("RAND_REG",
        $sformatf("PASS: %0d/%0d writes; single-seed cov=%.1f%%",
                  env.mem_resp.writes_observed, r_tcount*4, cg_random.get_coverage()),
        UVM_NONE)
    else
      `uvm_error("RAND_REG",
        $sformatf("FAIL: %0d/%0d writes",
                  env.mem_resp.writes_observed, r_tcount*4))
    #100;
    phase.drop_objection(this);
  endtask
endclass
