// Random-data multiply test on the 32-thread cgra-nopred design.
//
// Same 5-eblock pipeline as full_mul_array_test, but A and B values are
// randomized per (tid, lane). Expected stores are computed from the
// 16-bit multiply (mod 2^16) of those random pairs.
//
// Run with +ntb_random_seed=<N> for reproducibility.
//
// Coverage rationale: the directed tests hit specific patterns. Random pulls
// in mid-range bit patterns that neither covers — sign-bit flips, partial
// products that cancel, etc. Booth radix-4 has data-dependent code paths in
// the partial-product encoder; random inputs exercise the trip-bit case
// statement across all 32 threads × 4 lanes.
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
    //    read_mem[i]=i, and 128 canonical expect_store() calls.
    super.setup_thread_inputs_and_expectations();

    // 2) Wipe the canonical expectations — we're replacing them with random.
    env.sb.expected_data.delete();
    env.sb.stores_expected = 0;

    // 3) Override csrX0 to 0 to avoid address overlap between the A and B
    //    ranges. Canonical csrX0=1 makes A span 0x01..0x80 and B span
    //    0x80..0xFF — they share addr 0x80 (A[31,3] AND B[0,0]). The
    //    canonical full_mul_array sails through that overlap by coincidence
    //    (mem[0x80]=128 happens to be valid for both reads), but with
    //    random data each address must hold one value, not two.
    env.cta_agnt.drv.vif.csrX[0] = 16'd0;

    // 4) Override A/B load values and compute the new expected stores.
    //    Address layout (with csrX0=0, csrX1=128, csrX2=256, csrX3=4,
    //    csrX4..7=0..3):
    //      A: addr = 0   + 4*tid + lane   →  range 0x0000..0x007F  (128 addrs)
    //      B: addr = 128 + 4*tid + lane   →  range 0x0080..0x00FF  (128 addrs)
    //      C: addr = 256 + 4*tid + lane   →  range 0x0100..0x017F  (128 addrs)
    for (int t = 0; t < 32; t++) begin
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
      $sformatf("Registered 128 random A*B expectations (32 threads x 4 lanes)"),
      UVM_LOW)
  endfunction

endclass
