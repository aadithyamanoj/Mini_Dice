// AXI-Lite error-response test on the 32-thread cgra-nopred design.
//
// Reuses the full_mul_array_test harness (all 5 eblocks, 32 threads, 128
// stores, identity lane convention). Adds one SLVERR injection on a single
// load address (A[tid=0, lane=0] at 0x0001) to verify:
//
//   - DUT does NOT deadlock on a non-OKAY rresp (mem_req_fifo today does
//     not gate on rresp, so the load completes and the pipeline continues).
//   - All 128 stores still match — mem[0x0001]=1 is delivered alongside
//     rresp=SLVERR, and the multiplier consumes the correct data anyway.
//   - The scoreboard tolerates the deliberately-injected error via
//     expect_axil_error().
class dice_core_axil_error_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_axil_error_test)

  // One read address gets SLVERR. Default = A[tid=0, lane=0] which lives at
  // csrX0 + 0*csrX3 + csrX4 = 1 + 0 + 0 = 0x0001.
  logic [15:0] err_addr = 16'h0001;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    // Canonical 32-thread / 128-store setup (read_mem[i]=i, all 5 bitstreams,
    // CSRs, 128 expected stores).
    super.setup_thread_inputs_and_expectations();

    // Inject SLVERR on the chosen address. The mem value is still returned;
    // only rresp changes to 2'b10. expect_axil_error() tells the scoreboard
    // to count-but-not-fail on the non-OKAY response.
    env.axil_agnt.drv.read_resp_err[err_addr] = 2'b10;
    env.sb.expect_axil_error(err_addr);

    `uvm_info("AXIL_ERR",
      $sformatf("Injecting SLVERR (rresp=2'b10) on read addr 0x%04x", err_addr),
      UVM_LOW)
  endfunction

endclass
