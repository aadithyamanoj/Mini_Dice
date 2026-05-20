// mini_dice_chip_base_test
// -------------------------
// Base class for all chip-level UVM tests. Owns the chip_env and provides
// load_collateral / program_and_launch / wait_for_complete. Subclasses set
// test_vector_name and optionally override expected_write_count / run_phase.

class mini_dice_chip_base_test extends uvm_test;
  `uvm_component_utils(mini_dice_chip_base_test)

  chip_env env;
  string   test_vector_name = "full_mul_array_test_vector";
  string   test_vector_dir  = "tb/test_vectors";

  // Settling window (cycles) before final DPI check
  int unsigned SETTLE_CYCLES = 500_000;

  // Test vector state populated by load_collateral()
  logic [15:0] csr_values [8];
  logic [15:0] start_pc;
  logic [15:0] thread_count;

  function new(string name = "mini_dice_chip_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = chip_env::type_id::create("env", this);
    // Allow command-line override of the test vector
    void'($value$plusargs("TEST_VECTOR=%s", test_vector_name));
    void'($value$plusargs("TEST_VECTOR_DIR=%s", test_vector_dir));
  endfunction

  task load_collateral();
    string stem, cta_mem, meta_mem, bs_mem, runtime_json;
    int unsigned word, i;
    stem         = {test_vector_dir, "/", test_vector_name};
    cta_mem      = {stem, "_cta_desc.mem"};
    meta_mem     = {stem, "_meta.mem"};
    bs_mem       = {stem, "_bitstream.mem"};
    runtime_json = {stem, "_runtime.json"};

    dice_core_tb_init(cta_mem, meta_mem, bs_mem, runtime_json);
    if (dice_core_tb_has_init_error())
      `uvm_fatal("BASE", $sformatf("DPI init failed: %s", dice_core_tb_get_init_error()))

    // CSR values
    for (i = 0; i < 8; i++) csr_values[i] = 16'(dice_core_tb_get_csr(i));

    // start_pc lives in the low 16 bits of cta_desc word 0.
    word = dice_core_tb_get_cta_desc_word(0);
    start_pc = 16'(word & 16'hFFFF);
    thread_count = 16'd16;
    `uvm_info("BASE", $sformatf("Loaded %s: csr={%04x %04x %04x %04x %04x %04x %04x %04x} start_pc=0x%04x tcount=%0d",
              test_vector_name,
              csr_values[0], csr_values[1], csr_values[2], csr_values[3],
              csr_values[4], csr_values[5], csr_values[6], csr_values[7],
              start_pc, thread_count), UVM_LOW)
  endtask

  task program_and_launch();
    csr_launch_seq seq;
    seq = csr_launch_seq::type_id::create("launch_seq");
    seq.csr_values = csr_values;
    seq.start_pc   = start_pc;
    seq.thread_count = thread_count;
    seq.start(env.csr_agnt.seqr);
    `uvm_info("BASE", "CSR launch sequence complete; chip should now be running", UVM_LOW)
  endtask

  task wait_for_complete();
    int unsigned cyc;
    int unsigned target;
    void'($value$plusargs("SETTLE=%d", SETTLE_CYCLES));
    target = expected_write_count();
    `uvm_info("BASE", $sformatf("Waiting for %0d AXI writes (timeout %0d cycles)", target, SETTLE_CYCLES), UVM_LOW)

    // Poll writes_observed rather than DPI check_done — check_done
    // accumulates missing-write errors on every call.
    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= target) break;
    end

    // Drain tail so late writes land before the verdict.
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    env.sb.final_writes_seen = env.mem_resp.writes_observed;
    env.sb.check_done();
  endtask

  virtual function int unsigned expected_write_count();
    return 64;  // 16 threads * 4 mem ports
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    load_collateral();
    program_and_launch();
    wait_for_complete();
    #100;
    phase.drop_objection(this);
  endtask

endclass
