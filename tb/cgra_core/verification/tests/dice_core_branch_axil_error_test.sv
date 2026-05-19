// dice_core_branch_axil_error_test
// --------------------------------
// simple_branching_test + SLVERR injection on the divergent thread's load.
// Verifies the DUT doesn't deadlock when an AXI error arrives mid-divergence.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_branch_axil_error_test +UVM_VERBOSITY=UVM_LOW

class dice_core_branch_axil_error_test extends dice_core_simple_branching_test;
  `uvm_component_utils(dice_core_branch_axil_error_test)

  // Address to inject SLVERR on. Default: A[tid=0, lane=0] — the same load
  // address that the divergent thread (tid=0) actually issues.
  logic [15:0] err_addr = 16'h0001;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    super.setup_thread_inputs_and_expectations();  // simple_branching canonical
    env.axil_agnt.drv.read_resp_err[err_addr] = 2'b10;
    env.sb.expect_axil_error(err_addr);
    `uvm_info("BR_ERR",
      $sformatf("Injecting SLVERR on read addr 0x%04x (= A[tid=0, lane=0], divergent thread's input)",
                err_addr), UVM_LOW)
  endfunction

endclass
