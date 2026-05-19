// dice_core_mul_random_data_test
// ------------------------------
// full_mul_array_test with random A/B values per (tid, lane) instead of
// mem[i]=i. Hits Booth-multiplier data-dependent paths the directed tests
// don't reach. Overrides csrX0=0 to keep the A/B address ranges from
// overlapping (the canonical csrX0=1 puts both regions at addr 0x80).
//
// Run with +ntb_random_seed=<N> for reproducibility (tested on 1, 42, 1234).
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_mul_random_data_test +UVM_VERBOSITY=UVM_LOW
class dice_core_mul_random_data_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_mul_random_data_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    logic [15:0] a_val;
    logic [15:0] b_val;
    logic [15:0] expected;
    logic [15:0] a_addr, b_addr, c_addr;

    // 1) Pull in the canonical setup: bitstreams (mfetch/bsfetch), CSRs,
    //    read_mem[i]=i, and 64 canonical expect_store() calls.
    super.setup_thread_inputs_and_expectations();

    // 2) Wipe the canonical expectations, we're replacing them with random.
    env.sb.expected_data.delete();
    env.sb.stores_expected = 0;

    // 3) Override csrX0 to 0 to avoid address overlap between the A and B
    //    ranges. With csrX0=0, A spans 0x00..0x3F and B spans 0x80..0xBF —
    //    disjoint. Random data needs each address to hold one value, not two.
    env.cta_agnt.drv.vif.csrX[0] = 16'd0;

    // 4) Override A/B load values and compute the new expected stores.
    //    Address layout (with csrX0=0, csrX1=128, csrX2=256, csrX3=4,
    //    csrX4..7=0..3):
    //      A: addr = 0   + 4*tid + lane   →  range 0x0000..0x003F  (64 addrs)
    //      B: addr = 128 + 4*tid + lane   →  range 0x0080..0x00BF  (64 addrs)
    //      C: addr = 256 + 4*tid + lane   →  range 0x0100..0x013F  (64 addrs)
    for (int t = 0; t < 16; t++) begin
      for (int k = 0; k < 4; k++) begin
        a_val  = $urandom() & 16'hFFFF;
        b_val  = $urandom() & 16'hFFFF;
        a_addr = 16'(0   + 4*t + k);
        b_addr = 16'(128 + 4*t + k);
        c_addr = 16'(256 + 4*t + k);
        env.axil_agnt.drv.read_mem[a_addr] = a_val;
        env.axil_agnt.drv.read_mem[b_addr] = b_val;
        expected = a_val * b_val;  // 16-bit *, truncates mod 2^16
        env.sb.expect_store(c_addr, expected);
      end
    end

    `uvm_info("RAND",
      $sformatf("Registered 64 random A*B expectations (16 threads x 4 lanes)"),
      UVM_LOW)
  endfunction

endclass
