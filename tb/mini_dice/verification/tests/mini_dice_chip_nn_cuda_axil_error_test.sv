// mini_dice_chip_nn_cuda_axil_error_test
// ---------------------------------------
// Runs the 5-eblock 4-CTA nn_cuda kernel with SLVERR (rresp=2'b10)
// injected on one of CTA 0's load addresses. mem_responder returns
// the same data regardless of rresp; chip doesn't gate on rresp, so
// this is a protocol-level error injection (no data corruption).
// Verifies chip flow control survives a non-OKAY rresp on the
// shallower nn_cuda kernel shape (no deadlock, all 4 CTAs produce
// stores). Pass criterion: write count >= 64. DPI diff is not invoked.
//
// Kernel: nn_cuda (multi-CTA, 5 eblocks, 4 CTAs, MUL + squared-distance)
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_nn_cuda_axil_error_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_nn_cuda_axil_error_test

class mini_dice_chip_nn_cuda_axil_error_test extends mini_dice_chip_nn_cuda_smoke_test;
  `uvm_component_utils(mini_dice_chip_nn_cuda_axil_error_test)

  // CTA 0's csrX0=1 (A_base). First real load address tid 0 issues sits
  // in the 0x05..0x10 range (confirmed empirically).
  logic [15:0] err_addr = 16'h0005;

  function new(string name = "mini_dice_chip_nn_cuda_axil_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    load_collateral();
    env.mem_resp.read_resp_err[err_addr] = 2'b10;
    `uvm_info("NN_CUDA_ERR",
      $sformatf("Injecting SLVERR on load addr=0x%04x (CTA 0)", err_addr),
      UVM_LOW)

    run_grid();
    repeat (500) @(posedge env.csr_agnt.drv.vif.clk_i);

    `uvm_info("NN_CUDA_ERR",
      $sformatf("Done: writes_observed=%0d unique_addrs=%0d (DPI diff intentionally expected to flag CTA0 lane)",
                env.mem_resp.writes_observed,
                env.mem_resp.local_writes.size()), UVM_NONE)

    if (env.mem_resp.writes_observed >= 64)
      `uvm_info("NN_CUDA_ERR",
        "PASS: chip did not deadlock under SLVERR; all 4 CTAs produced stores", UVM_NONE)
    else
      `uvm_error("NN_CUDA_ERR",
        $sformatf("FAIL: only %0d stores (chip may have deadlocked)",
                  env.mem_resp.writes_observed))

    #100;
    phase.drop_objection(this);
  endtask
endclass
