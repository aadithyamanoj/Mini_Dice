// mini_dice_chip_base_test
// -------------------------
// Base class for all chip-level UVM tests. Owns the chip_env and provides
// load_collateral / program_and_launch / wait_for_complete / run_grid.
//
// The chip has a single CTA slot. The default run_phase picks single-shot
// or sequential per-CTA dispatch based on the kernel's grid_size (parsed
// from runtime.json's per_cta_csr_overrides as num_ctas):
//   - num_ctas == 1  → legacy program_and_launch + writes-observed wait
//   - num_ctas >  1  → run_grid: loops over the kernel's CTAs and pushes
//                       each one through the single slot in sequence
//                       (program per-CTA CSRs → pulse CTRL.START →
//                       poll REG_STATUS[0] for sticky-complete → next),
//                       then a final DPI check_done verification.

class mini_dice_chip_base_test extends uvm_test;
  `uvm_component_utils(mini_dice_chip_base_test)

  chip_env env;
  string   test_vector_name = "full_mul_array_test_vector";
  string   test_vector_dir  = "tb/test_vectors";

  // Settling window (cycles) before final DPI check
  int unsigned SETTLE_CYCLES = 500_000;

  // Per-CTA REG_STATUS polling cadence + timeout for run_grid path.
  int unsigned POLL_INTERVAL_CYC = 256;
  int unsigned PER_CTA_TIMEOUT   = 200_000;

  // Test vector state populated by load_collateral()
  logic [15:0]    csr_values [8];
  logic [15:0]    start_pc;
  logic [15:0]    thread_count;
  int unsigned    num_ctas;
  dice_cta_desc_t launch_desc;

  function new(string name = "mini_dice_chip_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = chip_env::type_id::create("env", this);
    void'($value$plusargs("TEST_VECTOR=%s", test_vector_name));
    void'($value$plusargs("TEST_VECTOR_DIR=%s", test_vector_dir));
  endfunction

  task load_collateral();
    localparam int CTA_DESC_BITS  = $bits(dice_cta_desc_t);
    localparam int CTA_DESC_WORDS = (CTA_DESC_BITS + 31) / 32;
    string stem, cta_mem, meta_mem, bs_mem, runtime_json;
    int unsigned i;
    logic [CTA_DESC_WORDS*32-1:0] packed_desc;
    stem         = {test_vector_dir, "/", test_vector_name};
    cta_mem      = {stem, "_cta_desc.mem"};
    meta_mem     = {stem, "_meta.mem"};
    bs_mem       = {stem, "_bitstream.mem"};
    runtime_json = {stem, "_runtime.json"};

    dice_core_tb_init(cta_mem, meta_mem, bs_mem, runtime_json);
    if (dice_core_tb_has_init_error())
      `uvm_fatal("BASE", $sformatf("DPI init failed: %s", dice_core_tb_get_init_error()))

    for (i = 0; i < 8; i++) csr_values[i] = 16'(dice_core_tb_get_csr(i));

    // Reconstruct the packed cta_desc and use struct-typed access for
    // start_pc / thread_count (start_pc is at bits [63:48], not word[0]).
    packed_desc = '0;
    for (int w = 0; w < CTA_DESC_WORDS; w++)
      packed_desc[w*32 +: 32] = dice_core_tb_get_cta_desc_word(w);
    launch_desc  = dice_cta_desc_t'(packed_desc[CTA_DESC_BITS-1:0]);
    start_pc     = 16'(launch_desc.kernel_desc.start_pc);
    thread_count = 16'(launch_desc.kernel_desc.thread_count);

    // DPI returns 0 for single-CTA runtime.json (no per_cta_csr_overrides);
    // coerce to 1 so the dispatch path runs once.
    num_ctas = dice_core_tb_num_ctas();
    if (num_ctas == 0) num_ctas = 1;

    `uvm_info("BASE", $sformatf("Loaded %s: csr={%04x %04x %04x %04x %04x %04x %04x %04x} start_pc=0x%04x tcount=%0d num_ctas=%0d",
              test_vector_name,
              csr_values[0], csr_values[1], csr_values[2], csr_values[3],
              csr_values[4], csr_values[5], csr_values[6], csr_values[7],
              start_pc, thread_count, num_ctas), UVM_LOW)
  endtask

  // Legacy single-shot launch: writes csrX0..7 + start_pc + thread_count
  // + CTRL.START in one csr_launch_seq.
  task program_and_launch();
    csr_launch_seq seq;
    seq = csr_launch_seq::type_id::create("launch_seq");
    seq.csr_values   = csr_values;
    seq.start_pc     = start_pc;
    seq.thread_count = thread_count;
    seq.start(env.csr_agnt.seqr);
    `uvm_info("BASE", "CSR launch sequence complete; chip should now be running", UVM_LOW)
  endtask

  // Per-CTA CSR programming using DPI override table. Falls back to base
  // csr_values when override entry is missing (DPI does the fallback for
  // each (cta, csr) pair internally — see parse_per_cta_overrides).
  task automatic program_csrs_for_cta(int unsigned cta_idx);
    csr_one_shot_seq sub;
    for (int i = 0; i < 8; i++) begin
      sub = csr_one_shot_seq::type_id::create("sub_csr");
      sub.addr = REG_CSRX0 + 16'(i * 2);
      sub.data = 16'(dice_core_tb_get_per_cta_csr(cta_idx, i));
      sub.start(env.csr_agnt.seqr);
    end
  endtask

  task automatic pulse_start();
    csr_one_shot_seq sub;
    sub = csr_one_shot_seq::type_id::create("sub_start");
    sub.addr = REG_CTRL; sub.data = CTRL_START;
    sub.start(env.csr_agnt.seqr);
  endtask

  // Poll REG_STATUS[0] every POLL_INTERVAL_CYC cycles until sticky-complete
  // goes high. The chip clears bit [0] on the next CTRL.START, so every
  // CTA's wait sees a fresh edge — matches the post-tapeout host driver.
  task automatic wait_for_cta_done(int unsigned cta_idx);
    int unsigned cyc = 0;
    logic [15:0] status;
    forever begin
      repeat (POLL_INTERVAL_CYC) @(posedge env.csr_agnt.drv.vif.clk_i);
      cyc += POLL_INTERVAL_CYC;
      csr_read_via_link(env.csr_agnt.drv.vif, REG_STATUS, status);
      if (status[0]) begin
        `uvm_info("BASE",
          $sformatf("CTA %0d complete (STATUS=0x%04x) after ~%0d cycles",
                    cta_idx, status, cyc), UVM_LOW)
        return;
      end
      if (cyc >= PER_CTA_TIMEOUT) begin
        `uvm_error("BASE",
          $sformatf("CTA %0d timed out after %0d cycles (last STATUS=0x%04x writes=%0d)",
                    cta_idx, cyc, status, env.mem_resp.writes_observed))
        return;
      end
    end
  endtask

  // Multi-CTA dispatch: write kernel-wide CSRs once, then loop over CTAs
  // applying per-CTA csrX0..7 overrides, pulsing CTRL.START, and polling
  // REG_STATUS[0] for sticky-complete between dispatches.
  task automatic run_grid();
    csr_one_shot_seq sub;
    sub = csr_one_shot_seq::type_id::create("sub_pc");
    sub.addr = REG_STARTPC; sub.data = start_pc;
    sub.start(env.csr_agnt.seqr);
    sub = csr_one_shot_seq::type_id::create("sub_tc");
    sub.addr = REG_THREAD_COUNT; sub.data = thread_count;
    sub.start(env.csr_agnt.seqr);
    `uvm_info("BASE",
      $sformatf("Kernel CSRs programmed: start_pc=0x%04x tcount=%0d num_ctas=%0d",
                start_pc, thread_count, num_ctas), UVM_LOW)

    for (int unsigned c = 0; c < num_ctas; c++) begin
      `uvm_info("BASE", $sformatf("Dispatching CTA %0d/%0d", c, num_ctas), UVM_LOW)
      program_csrs_for_cta(c);
      pulse_start();
      wait_for_cta_done(c);
    end
  endtask

  // Legacy wait: count writes_observed until target reached, then call
  // scoreboard check_done. Used by single-shot tests.
  task wait_for_complete();
    int unsigned cyc;
    int unsigned target;
    void'($value$plusargs("SETTLE=%d", SETTLE_CYCLES));
    target = expected_write_count();
    `uvm_info("BASE", $sformatf("Waiting for %0d AXI writes (timeout %0d cycles)", target, SETTLE_CYCLES), UVM_LOW)

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= target) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    env.sb.final_writes_seen = env.mem_resp.writes_observed;
    env.sb.check_done();
  endtask

  // End-of-grid verification for the run_grid path: drain residual
  // traffic, check store count, then call DPI check_done to compare
  // every (addr,data,strb) against expected_writes. check_done returns
  // NON-ZERO on diff-clean and 0 on mismatch (inverted convention).
  task automatic finalize_grid_check();
    int unsigned diff_status;
    repeat (500) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("BASE",
      $sformatf("All %0d CTAs done. writes_observed=%0d unique_addrs=%0d",
                num_ctas, env.mem_resp.writes_observed,
                env.mem_resp.local_writes.size()), UVM_NONE)

    if (env.mem_resp.writes_observed < expected_write_count()) begin
      `uvm_error("BASE",
        $sformatf("FAIL: only %0d stores (expected >=%0d) across %0d CTAs",
                  env.mem_resp.writes_observed, expected_write_count(), num_ctas))
      return;
    end

    diff_status = dice_core_tb_check_done();
    if (diff_status != 0)
      `uvm_info("BASE",
        $sformatf("PASS: %0d stores match DPI expected_writes (DPI diff clean)",
                  env.mem_resp.writes_observed), UVM_NONE)
    else
      `uvm_error("BASE",
        $sformatf("FAIL: count OK (%0d stores) but DPI reports data mismatch",
                  env.mem_resp.writes_observed))
  endtask

  virtual function int unsigned expected_write_count();
    return 64;  // 16 threads * 4 mem ports (single-CTA default)
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    if (num_ctas == 1) begin
      program_and_launch();
      wait_for_complete();
    end else begin
      run_grid();
      finalize_grid_check();
    end
    #100;
    phase.drop_objection(this);
  endtask

endclass
