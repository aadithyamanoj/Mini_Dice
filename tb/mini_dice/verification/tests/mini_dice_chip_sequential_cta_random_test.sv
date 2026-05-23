// mini_dice_chip_sequential_cta_random_test
// ------------------------------------------
// Dispatches two CTAs back-to-back through the single-CTA slot with
// random per-CTA config (thread_count, A/B/C base addresses, A/B input
// values). Both CTAs run full_mul_array — that matches how software
// actually uses the chip: a grid of N CTAs all share one kernel binary.
// CTA0's address region is in 0x000..0x1FF; CTA1's is in 0x200..0x3FF
// (disjoint). Builds a combined expected_data map across both CTAs and
// compares against observed writes.
//
// Kernel: full_mul_array (single-CTA, 5 eblocks, MUL) — dispatched twice
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_sequential_cta_random_test +ntb_random_seed=42
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_sequential_cta_random_test +ntb_random_seed=42

class mini_dice_chip_sequential_cta_random_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_sequential_cta_random_test)

  // Per-CTA randomized knobs; index 0 = CTA0, index 1 = CTA1.
  rand int unsigned r_tcount [2];
  rand logic [15:0] r_csr0   [2];   // A_base
  rand logic [15:0] r_csr1   [2];   // B_base
  rand logic [15:0] r_csr2   [2];   // C_base
  rand logic [15:0] r_A      [2][64];
  rand logic [15:0] r_B      [2][64];

  logic [15:0] expected_data [logic [15:0]];

  constraint c_per_cta {
    foreach (r_tcount[i]) r_tcount[i] inside {[1:16]};

    r_csr0[0] inside {[16'h0000 : 16'h0040]};
    r_csr1[0] == r_csr0[0] + 16'd128;
    r_csr2[0] == r_csr1[0] + 16'd128;

    r_csr0[1] inside {[16'h0200 : 16'h0240]};
    r_csr1[1] == r_csr0[1] + 16'd128;
    r_csr2[1] == r_csr1[1] + 16'd128;
  }

  covergroup cg_seq_cta;
    cp_cta0_tcount: coverpoint r_tcount[0] {
      bins b_lo  = {[1:4]}; bins b_mid = {[5:12]}; bins b_hi = {[13:16]};
    }
    cp_cta1_tcount: coverpoint r_tcount[1] {
      bins b_lo  = {[1:4]}; bins b_mid = {[5:12]}; bins b_hi = {[13:16]};
    }
    cross_tcount_pair: cross cp_cta0_tcount, cp_cta1_tcount;
  endgroup

  function new(string name = "mini_dice_chip_sequential_cta_random_test", uvm_component parent = null);
    super.new(name, parent);
    cg_seq_cta = new();
  endfunction

  function void install_cta(int unsigned i);
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;
    int unsigned t, k;
    for (t = 0; t < r_tcount[i]; t++) begin
      for (k = 0; k < 4; k++) begin
        a_addr = r_csr0[i] + 16'(4*t + k);
        b_addr = r_csr1[i] + 16'(4*t + k);
        c_addr = r_csr2[i] + 16'(4*t + k);
        a_val  = r_A[i][t*4 + k];
        b_val  = r_B[i][t*4 + k];
        env.mem_resp.override_data[a_addr] = a_val;
        env.mem_resp.override_data[b_addr] = b_val;
        expected = a_val * b_val;  // full_mul_array does A*B
        expected_data[c_addr] = expected;
      end
    end
  endfunction

  task program_cta_csrs(int unsigned i);
    csr_one_shot_seq sub;
    int unsigned k;
    for (k = 0; k < 8; k++) begin
      sub = csr_one_shot_seq::type_id::create("sub");
      sub.addr = REG_CSRX0 + 16'(k * 2);
      case (k)
        0: sub.data = r_csr0[i];
        1: sub.data = r_csr1[i];
        2: sub.data = r_csr2[i];
        3: sub.data = 16'd4;
        4: sub.data = 16'd0;
        5: sub.data = 16'd1;
        6: sub.data = 16'd2;
        7: sub.data = 16'd3;
      endcase
      sub.start(env.csr_agnt.seqr);
    end
    sub = csr_one_shot_seq::type_id::create("sub_pc");
    sub.addr = REG_STARTPC;     sub.data = 16'h1000;
    sub.start(env.csr_agnt.seqr);
    sub = csr_one_shot_seq::type_id::create("sub_tc");
    sub.addr = REG_THREAD_COUNT; sub.data = 16'(r_tcount[i]);
    sub.start(env.csr_agnt.seqr);
    sub = csr_one_shot_seq::type_id::create("sub_start");
    sub.addr = REG_CTRL;        sub.data = CTRL_START;
    sub.start(env.csr_agnt.seqr);
  endtask

  function void compare_results(int unsigned expected_total);
    int unsigned n_match = 0, miss = 0, mismatch = 0;
    logic [15:0] addr;
    foreach (expected_data[addr]) begin
      if (!env.mem_resp.local_writes.exists(addr)) begin
        miss++;
      end else if (env.mem_resp.local_writes[addr] !== expected_data[addr]) begin
        mismatch++;
        `uvm_error("SEQ_CTA_RAND",
          $sformatf("MISMATCH addr=0x%04x got=0x%04x exp=0x%04x",
                    addr, env.mem_resp.local_writes[addr], expected_data[addr]))
      end else begin
        n_match++;
      end
    end
    if (n_match == expected_total && miss == 0 && mismatch == 0)
      `uvm_info("SEQ_CTA_RAND",
        $sformatf("PASS: %0d/%0d stores across 2 CTAs match; cov=%.1f%%",
                  n_match, expected_total, cg_seq_cta.get_coverage()),
        UVM_NONE)
    else
      `uvm_error("SEQ_CTA_RAND",
        $sformatf("FAIL: match=%0d miss=%0d mismatch=%0d (expected %0d)",
                  n_match, miss, mismatch, expected_total))
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    int unsigned cta0_target;
    int unsigned total_target;
    phase.raise_objection(this);

    if (!this.randomize()) `uvm_fatal("SEQ_CTA_RAND", "randomize() failed");
    cg_seq_cta.sample();

    test_vector_name = "full_mul_array_test_vector";
    load_collateral();

    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA0: tcount=%0d csr0=%04x → %0d stores | CTA1: tcount=%0d csr0=%04x → %0d stores",
                r_tcount[0], r_csr0[0], r_tcount[0]*4,
                r_tcount[1], r_csr0[1], r_tcount[1]*4),
      UVM_LOW)

    // Dispatch CTA 0.
    install_cta(0);
    cta0_target = r_tcount[0] * 4;
    program_cta_csrs(0);

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= cta0_target) break;
    end
    repeat (300) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA 0 drained (writes=%0d/%0d)",
                env.mem_resp.writes_observed, cta0_target), UVM_LOW)

    // Dispatch CTA 1.
    install_cta(1);
    total_target = cta0_target + r_tcount[1] * 4;
    program_cta_csrs(1);

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= total_target) break;
    end
    repeat (300) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA 1 drained (writes=%0d/%0d)",
                env.mem_resp.writes_observed, total_target), UVM_LOW)

    compare_results(total_target);
    #100;
    phase.drop_objection(this);
  endtask
endclass
