// AXI-Lite error-response handling test.
// Reuses the full mul_array harness, but configures the AXI-Lite slave to
// return SLVERR (rresp=2'b10) for one of the load addresses (A[2] = 0x0102,
// which feeds GPR-bank lane 1 / store address 0x0301 in the kernel's
// reversed-lane mapping).
//
// What this checks:
//   - The DUT does NOT deadlock on a non-OKAY read response. (mem_req_fifo
//     today does not gate on rresp, so it should accept the data and continue.)
//   - The OTHER three lanes still produce correct stores (no cross-lane
//     contamination from one error response).
//   - The scoreboard tolerates the deliberately-injected error rather than
//     failing the test on it.
//
// The store at 0x0301 is intentionally NOT registered — its data is undefined
// because A[2] read returned an error, so the multiplier consumed garbage.
class dice_core_axil_error_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_axil_error_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    // Same canonical inputs as parent...
    env.axil_agnt.drv.read_mem[16'h0100] = 16'd2;  // A[0]
    env.axil_agnt.drv.read_mem[16'h0101] = 16'd3;  // A[1]
    env.axil_agnt.drv.read_mem[16'h0102] = 16'd4;  // A[2] (will return SLVERR)
    env.axil_agnt.drv.read_mem[16'h0103] = 16'd5;  // A[3]
    env.axil_agnt.drv.read_mem[16'h0200] = 16'd3;  // B[0]
    env.axil_agnt.drv.read_mem[16'h0201] = 16'd4;  // B[1]
    env.axil_agnt.drv.read_mem[16'h0202] = 16'd5;  // B[2]
    env.axil_agnt.drv.read_mem[16'h0203] = 16'd6;  // B[3]

    // Inject SLVERR (2'b10) on A[2]. Slave still returns mem_model[0x0102]
    // as rdata, but rresp = 2'b10. The DUT's FSM doesn't check rresp so it
    // proceeds with the data; this verifies non-deadlock under errors.
    env.axil_agnt.drv.read_resp_err[16'h0102] = 2'b10;
    env.sb.expect_axil_error(16'h0102);

    // Three stores still expected (lanes that don't depend on A[2]).
    env.sb.expect_store(16'h0300, 16'd30);  // A[3]*B[3]
    // Skip 0x0301 — depends on A[2] which got an error response
    env.sb.expect_store(16'h0302, 16'd12);  // A[1]*B[1]
    env.sb.expect_store(16'h0303, 16'd6);   // A[0]*B[0]

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
