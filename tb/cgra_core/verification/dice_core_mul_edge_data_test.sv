// Multiply edge-data coverage test.
// Reuses full_mul_array_test's kernel/metadata setup and exercises the same
// 5-eblock pipeline, but feeds the multiplier four boundary input pairs
// instead of the small canonical values:
//
//   Lane 0 (C[0] = A[3]*B[3]): 0x0000 * 0x1234 = 0x0000  (zero annihilator)
//   Lane 1 (C[1] = A[2]*B[2]): 0x0001 * 0xABCD = 0xABCD  (identity)
//   Lane 2 (C[2] = A[1]*B[1]): 0xFFFF * 0x0002 = 0xFFFE  (signed -1 * 2 = -2)
//   Lane 3 (C[3] = A[0]*B[0]): 0x8000 * 0x8000 = 0x0000  (signed (-2^15)^2 mod 2^16)
//
// The PE multiplier is signed Booth radix-4, lower 16 bits taken (alu_mul.sv).
// These four values cover: zero leg, identity leg, two's-complement sign
// extension, and overflow truncation — all of which the canonical 2..6 inputs
// in full_mul_array_test never touch.
class dice_core_mul_edge_data_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_mul_edge_data_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    // Inputs are kept at the canonical addresses (0x0100/0x0200) and CSRs
    // are kept at canonical bases — only the data values change.
    env.axil_agnt.drv.read_mem[16'h0100] = 16'h8000;  // A[0]
    env.axil_agnt.drv.read_mem[16'h0101] = 16'hFFFF;  // A[1]
    env.axil_agnt.drv.read_mem[16'h0102] = 16'h0001;  // A[2]
    env.axil_agnt.drv.read_mem[16'h0103] = 16'h0000;  // A[3]
    env.axil_agnt.drv.read_mem[16'h0200] = 16'h8000;  // B[0]
    env.axil_agnt.drv.read_mem[16'h0201] = 16'h0002;  // B[1]
    env.axil_agnt.drv.read_mem[16'h0202] = 16'hABCD;  // B[2]
    env.axil_agnt.drv.read_mem[16'h0203] = 16'h1234;  // B[3]

    // Expected: lane reversal puts A[3-k]*B[3-k] into C[k].
    env.sb.expect_store(16'h0300, 16'h0000);  // A[3]*B[3] = 0      * 0x1234 = 0
    env.sb.expect_store(16'h0301, 16'hABCD);  // A[2]*B[2] = 1      * 0xABCD
    env.sb.expect_store(16'h0302, 16'hFFFE);  // A[1]*B[1] = -1     * 2    = -2 (0xFFFE)
    env.sb.expect_store(16'h0303, 16'h0000);  // A[0]*B[0] = -2^15  * -2^15 = 2^30 mod 2^16

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
