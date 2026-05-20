// mini_dice_chip_csr_readback_test
// ---------------------------------
// Writes a distinct pattern into each of the 8 CSRs, then issues READ
// flits and checks the readback values. Exercises the FPGA->chip READ
// flit path and the chip->FPGA READ_RESP flit path end-to-end.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_csr_readback_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_csr_readback_test

class mini_dice_chip_csr_readback_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_csr_readback_test)

  function new(string name = "mini_dice_chip_csr_readback_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 50_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 0;  // no CTA launched
  endfunction

  task run_phase(uvm_phase phase);
    csr_one_shot_seq    sub;
    logic [15:0]        rdata;
    int unsigned        n_pass = 0, n_fail = 0;
    logic [15:0]        addrs [8];
    logic [15:0]        vals  [8];
    int unsigned        i;
    phase.raise_objection(this);

    @(negedge env.csr_agnt.drv.vif.rst_i);
    repeat (20) @(posedge env.csr_agnt.drv.vif.clk_i);

    // CSRs are word-addressed at 2-byte stride; values pick a recognizable
    // pattern (0xA000 + index) to spot any cross-talk.
    for (i = 0; i < 8; i++) begin
      addrs[i] = REG_CSRX0 + 16'(i * 2);
      vals[i]  = 16'hA000 + 16'(i);
    end

    // Phase 1: write each CSR.
    foreach (addrs[i]) begin
      sub = csr_one_shot_seq::type_id::create("sub");
      sub.addr = addrs[i]; sub.data = vals[i];
      sub.start(env.csr_agnt.seqr);
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("CSR_RD", "Phase 1 complete: 8 CSR writes done", UVM_LOW)

    // Phase 2: read each CSR back via the link and compare.
    foreach (addrs[i]) begin
      csr_read_via_link(env.csr_agnt.drv.vif, addrs[i], rdata);
      if (rdata === vals[i]) begin
        n_pass++;
        `uvm_info("CSR_RD",
          $sformatf("OK   addr=0x%04x read 0x%04x (expected 0x%04x)",
                    addrs[i], rdata, vals[i]), UVM_LOW)
      end else begin
        n_fail++;
        `uvm_error("CSR_RD",
          $sformatf("FAIL addr=0x%04x read 0x%04x expected 0x%04x",
                    addrs[i], rdata, vals[i]))
      end
    end

    if (n_fail == 0)
      `uvm_info("CSR_RD",
        $sformatf("PASS: %0d/8 CSRs read-back correctly via IO link", n_pass),
        UVM_NONE)
    else
      `uvm_error("CSR_RD",
        $sformatf("FAIL: %0d/8 mismatches in readback", n_fail))

    #100;
    phase.drop_objection(this);
  endtask
endclass
