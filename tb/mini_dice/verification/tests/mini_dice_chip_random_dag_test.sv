// mini_dice_chip_random_dag_test
// -------------------------------
// Constrained-random kernel + data + dispatch test. Per run randomizes:
//   - kernel op (MUL or ADD, picks the matching .mem files)
//   - thread_count 1..16
//   - disjoint A/B/C base addresses
//   - per-(tid,lane) A and B values
//   - mem_responder fetch latency
//   - optional SLVERR injection on one A or B load address
// Builds a local expected_data map (A op B mod 2^16) and compares against
// mem_responder.local_writes. Samples cg_dag covergroup.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_random_dag_test +ntb_random_seed=42
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_random_dag_test +ntb_random_seed=42

class mini_dice_chip_random_dag_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_random_dag_test)

  typedef enum bit { OP_MUL = 1'b0, OP_ADD = 1'b1 } op_e;

  rand op_e         r_kernel;
  rand int unsigned r_tcount;
  rand logic [15:0] r_csrX0;       // A_base
  rand logic [15:0] r_csrX1;       // B_base
  rand logic [15:0] r_csrX2;       // C_base
  rand logic [15:0] r_A [64];      // per-(tid,lane) A
  rand logic [15:0] r_B [64];      // per-(tid,lane) B
  rand bit          r_inject_err;
  rand logic [15:0] r_err_addr;
  rand int unsigned r_fetch_latency;

  // Expected local map populated after randomize().
  logic [15:0] expected_data [logic [15:0]];

  constraint c_kernel  { r_kernel inside {OP_MUL, OP_ADD}; }
  constraint c_tcount  { r_tcount inside {[1:16]}; }

  // Disjoint A/B/C regions in the slave's 0x0000..0x01FF window.
  // Per region, max addr touched = base + 15*4 + 3 = base + 63.
  constraint c_csrs {
    r_csrX0 inside {[16'd0 : 16'd64]};
    r_csrX1 == r_csrX0 + 16'd128;
    r_csrX2 == r_csrX1 + 16'd128;
    r_csrX2 + 16'd63 <= 16'h01FF;
  }

  constraint c_err {
    r_inject_err dist {0 := 1, 1 := 1};
    if (r_inject_err) r_err_addr inside {[16'h0000:16'h00FF]};
    else              r_err_addr == 16'h0000;
  }

  constraint c_latency { r_fetch_latency inside {0, 1, 2, 4, 8, 16}; }

  covergroup cg_dag;
    cp_kernel: coverpoint r_kernel {
      bins b_mul = {OP_MUL};
      bins b_add = {OP_ADD};
    }
    cp_tcount: coverpoint r_tcount {
      bins b_1     = {1};
      bins b_2_4   = {[2:4]};
      bins b_5_8   = {[5:8]};
      bins b_9_12  = {[9:12]};
      bins b_13_15 = {[13:15]};
      bins b_16    = {16};
    }
    cp_csr0: coverpoint r_csrX0 {
      bins b_low  = {[0:15]};
      bins b_mid  = {[16:32]};
      bins b_high = {[33:64]};
    }
    cp_err: coverpoint r_inject_err {
      bins b_no  = {0};
      bins b_yes = {1};
    }
    cross_kernel_tcount: cross cp_kernel, cp_tcount;
    cross_kernel_err:    cross cp_kernel, cp_err;
  endgroup

  function new(string name = "mini_dice_chip_random_dag_test", uvm_component parent = null);
    super.new(name, parent);
    cg_dag = new();
  endfunction

  virtual function int unsigned expected_write_count();
    return r_tcount * 4;
  endfunction

  function void install_random_inputs();
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;
    int unsigned t, k;
    for (t = 0; t < r_tcount; t++) begin
      for (k = 0; k < 4; k++) begin
        a_addr = r_csrX0 + 16'(4*t + k);
        b_addr = r_csrX1 + 16'(4*t + k);
        c_addr = r_csrX2 + 16'(4*t + k);
        a_val  = r_A[t*4 + k];
        b_val  = r_B[t*4 + k];
        env.mem_resp.override_data[a_addr] = a_val;
        env.mem_resp.override_data[b_addr] = b_val;
        expected = (r_kernel == OP_MUL) ? (a_val * b_val) : (a_val + b_val);
        expected_data[c_addr] = expected;
      end
    end
  endfunction

  function void compare_results();
    int unsigned n_match = 0, miss = 0, mismatch = 0, extra = 0;
    logic [15:0] addr;
    foreach (expected_data[addr]) begin
      if (!env.mem_resp.local_writes.exists(addr)) begin
        miss++;
        `uvm_error("RAND_DAG",
          $sformatf("MISSING addr=0x%04x (exp=0x%04x)", addr, expected_data[addr]))
      end else if (env.mem_resp.local_writes[addr] !== expected_data[addr]) begin
        mismatch++;
        `uvm_error("RAND_DAG",
          $sformatf("MISMATCH addr=0x%04x got=0x%04x exp=0x%04x",
                    addr, env.mem_resp.local_writes[addr], expected_data[addr]))
      end else begin
        n_match++;
      end
    end
    foreach (env.mem_resp.local_writes[addr])
      if (!expected_data.exists(addr)) extra++;
    if (n_match == expected_data.size() && miss == 0 && mismatch == 0 && extra == 0)
      `uvm_info("RAND_DAG",
        $sformatf("PASS: %0d/%0d %s stores match; cov=%.1f%%",
                  n_match, expected_data.size(),
                  (r_kernel==OP_MUL)?"MUL":"ADD", cg_dag.get_coverage()), UVM_NONE)
    else
      `uvm_error("RAND_DAG",
        $sformatf("FAIL: match=%0d miss=%0d mismatch=%0d extra=%0d",
                  n_match, miss, mismatch, extra))
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    phase.raise_objection(this);

    if (!this.randomize()) `uvm_fatal("RAND_DAG", "randomize() failed");
    cg_dag.sample();

    // load_collateral() reads the .mem files named by test_vector_name,
    // so the kernel must be selected before that call.
    test_vector_name = (r_kernel == OP_MUL) ?
        "full_mul_array_test_vector" : "add_array_test_vector";
    `uvm_info("RAND_DAG",
      $sformatf("op=%s tcount=%0d csrX0..2={%04x %04x %04x} err=%0b lat=%0d → %0d stores",
                (r_kernel==OP_MUL)?"MUL":"ADD",
                r_tcount, r_csrX0, r_csrX1, r_csrX2,
                r_inject_err, r_fetch_latency, r_tcount*4), UVM_LOW)

    env.mem_resp.response_delay_cyc = r_fetch_latency;
    load_collateral();

    // Override A/B/C bases; csrX3..7 keep the canonical stride + lane offsets.
    csr_values[0] = r_csrX0;
    csr_values[1] = r_csrX1;
    csr_values[2] = r_csrX2;
    thread_count  = 16'(r_tcount);

    install_random_inputs();
    if (r_inject_err)
      env.mem_resp.read_resp_err[r_err_addr] = 2'b10;

    program_and_launch();

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= r_tcount * 4) break;
    end
    repeat (300) @(posedge env.csr_agnt.drv.vif.clk_i);

    compare_results();
    #100;
    phase.drop_objection(this);
  endtask
endclass
