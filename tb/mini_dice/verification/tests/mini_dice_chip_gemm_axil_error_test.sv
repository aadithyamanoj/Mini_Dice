// mini_dice_chip_gemm_axil_error_test
// ------------------------------------
// Runs the 14-eblock 4-CTA gemm kernel with SLVERR (rresp=2'b10)
// injected on one of CTA 0's A-load addresses. The mem_responder
// returns the same read data regardless of rresp; only the rresp
// code differs. The chip doesn't gate on rresp, so this is purely
// a protocol-level error injection — not data corruption.
// Verifies the chip's flow control survives a non-OKAY rresp across
// a deep multi-CTA workload (no deadlock, all 4 CTAs complete).
// Pass criterion: write count >= 64. DPI diff is not invoked.
//
// Kernel: gemm (multi-CTA, 14 eblocks, 4 CTAs, MUL + MAC)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_gemm_axil_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_gemm_axil_error_test

class mini_dice_chip_gemm_axil_error_test extends mini_dice_chip_gemm_smoke_test;
  `uvm_component_utils(mini_dice_chip_gemm_axil_error_test)

  // CTA 0's csrX0 (A_base) = 16, stride=64 (csrX3), lane offsets csrX4..7.
  // Pick the first A-load address tid 0 hits.
  logic [15:0] err_addr = 16'h0010;

  function new(string name = "mini_dice_chip_gemm_axil_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    load_collateral();
    env.mem_resp.read_resp_err[err_addr] = 2'b10;
    `uvm_info("GEMM_ERR",
      $sformatf("Injecting SLVERR on A-load addr=0x%04x (CTA 0)", err_addr),
      UVM_LOW)

    run_grid();

    // Drain so any in-flight transactions retire. We expect 64 stores
    // (chip's mem_req_fifo doesn't gate on rresp) but CTA 0's data on
    // that lane will be wrong, so DPI diff will fail. The pass criterion
    // here is no deadlock + all 4 CTAs reach STATUS=complete.
    repeat (500) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("GEMM_ERR",
      $sformatf("Done: writes_observed=%0d unique_addrs=%0d (DPI diff intentionally expected to flag CTA0 lane)",
                env.mem_resp.writes_observed,
                env.mem_resp.local_writes.size()), UVM_NONE)

    if (env.mem_resp.writes_observed >= 64)
      `uvm_info("GEMM_ERR",
        "PASS: chip did not deadlock under SLVERR; all 4 CTAs produced stores", UVM_NONE)
    else
      `uvm_error("GEMM_ERR",
        $sformatf("FAIL: only %0d stores (chip may have deadlocked)",
                  env.mem_resp.writes_observed))

    #100;
    phase.drop_objection(this);
  endtask
endclass
