// Random-data multiply test.
// Same 5-eblock pipeline as full_mul_array_test, with random A and B values.
// Expected stores are computed from the actual signed multiply (mod 2^16).
//
// Seed selection: +ntb_random_seed=<N> on the simv command line. Default seed
// is whatever VCS picks; logs print it so failures are reproducible.
//
// Coverage rationale: directed tests hit specific values (canonical 2..6,
// edge 0/1/-1/0x8000). Random pulls in mid-range bit patterns that neither
// covers — sign bits flipping in middle of computation, partial products that
// happen to cancel, etc. Booth radix-4 has data-dependent code paths in the
// partial-product encoder; random inputs exercise the trip-bit case statement.
class dice_core_mul_random_data_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_mul_random_data_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    logic [15:0] a [4];
    logic [15:0] b [4];
    logic [15:0] expected;

    // Generate random 16-bit values.
    foreach (a[i]) a[i] = $urandom() & 16'hFFFF;
    foreach (b[i]) b[i] = $urandom() & 16'hFFFF;

    `uvm_info("RAND",
      $sformatf("A=[%04x %04x %04x %04x] B=[%04x %04x %04x %04x]",
                a[0], a[1], a[2], a[3], b[0], b[1], b[2], b[3]), UVM_NONE)

    env.axil_agnt.drv.read_mem[16'h0100] = a[0];
    env.axil_agnt.drv.read_mem[16'h0101] = a[1];
    env.axil_agnt.drv.read_mem[16'h0102] = a[2];
    env.axil_agnt.drv.read_mem[16'h0103] = a[3];
    env.axil_agnt.drv.read_mem[16'h0200] = b[0];
    env.axil_agnt.drv.read_mem[16'h0201] = b[1];
    env.axil_agnt.drv.read_mem[16'h0202] = b[2];
    env.axil_agnt.drv.read_mem[16'h0203] = b[3];

    // Lane reversal: C[k] = A[3-k] * B[3-k]
    // Multiply is signed Booth, lower 16 bits taken (mod 2^16).
    // SystemVerilog * on `logic [15:0]` is unsigned, but mod 2^16 the result
    // is identical to signed * truncated; only the high bits differ.
    for (int k = 0; k < 4; k++) begin
      expected = a[3-k] * b[3-k];  // truncates to 16 bits naturally
      env.sb.expect_store(16'h0300 + 16'(k), expected);
      `uvm_info("RAND", $sformatf("expect C[%0d] @ 0x%04x = 0x%04x (= 0x%04x * 0x%04x)",
                k, 16'h0300+16'(k), expected, a[3-k], b[3-k]), UVM_NONE)
    end

    env.cta_agnt.drv.vif.csrX[0] = 16'd256;
    env.cta_agnt.drv.vif.csrX[1] = 16'd512;
    env.cta_agnt.drv.vif.csrX[2] = 16'd768;
    env.cta_agnt.drv.vif.csrX[3] = 16'd8;
    env.cta_agnt.drv.vif.csrX[4] = 16'd0;
    env.cta_agnt.drv.vif.csrX[5] = 16'd1;
    env.cta_agnt.drv.vif.csrX[6] = 16'd2;
    env.cta_agnt.drv.vif.csrX[7] = 16'd3;
  endfunction

endclass
