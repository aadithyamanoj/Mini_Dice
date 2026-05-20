// mini_dice_chip_oor_empirical_test
// ----------------------------------
// Empirical probe of the out-of-range CSR write behavior. Requires the
// simv_stress binary built with +define+SKIP_AXI_DEMUX_ASSERTS so the
// crossbar cnt_underflow assertion does not $fatal. Sequence:
//   1. Baseline writes + readbacks on csrX0 / csrX1.
//   2. Three writes to unmapped addresses (0x0FFF, 0xEEEE, 0xFFFF).
//   3. Read csrX0 / csrX1 back; check they are untouched.
//   4. Write csrX2 and read it back.
//   5. Walk all 8 csrX with distinct patterns, read each back.
//   6. Final sweep re-reads all 8 csrX.
//
// (fails UVM_ERROR by design; diagnostic harness, not a regression test)
//
// this fails cause the design assumes FPGA will never write to an unmapped address (not a bug)
//
// Run (fast): cd tb/mini_dice/verification && ../simv_stress +UVM_TESTNAME=mini_dice_chip_oor_empirical_test
// Run (chip): cd tb/mini_dice/verification && ../simv_chip_stress +UVM_TESTNAME=mini_dice_chip_oor_empirical_test

class mini_dice_chip_oor_empirical_test extends mini_dice_chip_base_test;
  `uvm_component_utils(mini_dice_chip_oor_empirical_test)

  function new(string name = "mini_dice_chip_oor_empirical_test", uvm_component parent = null);
    super.new(name, parent);
    SETTLE_CYCLES = 100_000;
  endfunction

  virtual function int unsigned expected_write_count();
    return 0;
  endfunction

  // Write `data` to `addr`, then read it back through the link and compare.
  task automatic write_read_check(
      input  string       label,
      input  logic [15:0] addr,
      input  logic [15:0] data,
      output bit          ok
  );
    csr_one_shot_seq sub;
    logic [15:0]     got;
    sub = csr_one_shot_seq::type_id::create("sub");
    sub.addr = addr; sub.data = data;
    sub.start(env.csr_agnt.seqr);
    repeat (50) @(posedge env.csr_agnt.drv.vif.clk_i);
    csr_read_via_link(env.csr_agnt.drv.vif, addr, got);
    ok = (got === data);
    `uvm_info("OOR_EMP",
      $sformatf("[%s] addr=0x%04x wrote=0x%04x read=0x%04x rresp=%b %s",
                label, addr, data, got, env.csr_agnt.drv.vif.ep_rx_rresp,
                ok ? "OK" : "***MISMATCH***"),
      UVM_NONE)
  endtask

  task automatic read_only_check(
      input  string       label,
      input  logic [15:0] addr,
      input  logic [15:0] expected,
      output bit          ok
  );
    logic [15:0] got;
    csr_read_via_link(env.csr_agnt.drv.vif, addr, got);
    ok = (got === expected);
    `uvm_info("OOR_EMP",
      $sformatf("[%s] readback addr=0x%04x expected=0x%04x got=0x%04x rresp=%b %s",
                label, addr, expected, got, env.csr_agnt.drv.vif.ep_rx_rresp,
                ok ? "OK" : "***CORRUPTED***"),
      UVM_NONE)
  endtask

  // Write to an unmapped address; no readback (reading an unmapped addr
  // would itself trip the error slave).
  task automatic oor_write(input string label, input logic [15:0] addr,
                            input logic [15:0] data);
    csr_one_shot_seq sub;
    sub = csr_one_shot_seq::type_id::create("sub_oor");
    sub.addr = addr; sub.data = data;
    sub.start(env.csr_agnt.seqr);
    `uvm_info("OOR_EMP",
      $sformatf("[%s] OOR write addr=0x%04x data=0x%04x", label, addr, data),
      UVM_NONE)
    repeat (50) @(posedge env.csr_agnt.drv.vif.clk_i);
  endtask

  task run_phase(uvm_phase phase);
    bit          ok;
    int unsigned good = 0, bad = 0;
    int unsigned i;
    logic [15:0] csr_addrs [8];
    logic [15:0] csr_vals  [8];
    phase.raise_objection(this);

    @(negedge env.csr_agnt.drv.vif.rst_i);
    repeat (20) @(posedge env.csr_agnt.drv.vif.clk_i);
    `uvm_info("OOR_EMP", "=== Phase 0: baseline ===", UVM_NONE)

    // Phase 0: baseline writes
    write_read_check("base0", REG_CSRX0, 16'hBEEF, ok); if (ok) good++; else bad++;
    write_read_check("base1", REG_CSRX0 + 16'h2, 16'hDEAD, ok); if (ok) good++; else bad++;

    `uvm_info("OOR_EMP", "=== Phase 1: OOR writes ===", UVM_NONE)
    oor_write("oor_a", 16'h0FFF, 16'hAAAA);
    oor_write("oor_b", 16'hEEEE, 16'hBBBB);
    oor_write("oor_c", 16'hFFFF, 16'hCCCC);

    `uvm_info("OOR_EMP", "=== Phase 2: readback prior baselines ===", UVM_NONE)
    read_only_check("post_oor_0", REG_CSRX0,        16'hBEEF, ok); if (ok) good++; else bad++;
    read_only_check("post_oor_1", REG_CSRX0+16'h2,  16'hDEAD, ok); if (ok) good++; else bad++;

    `uvm_info("OOR_EMP", "=== Phase 3: NEW write after OOR (does chip still respond?) ===", UVM_NONE)
    write_read_check("post_oor_w", REG_CSRX0+16'h4, 16'hCAFE, ok); if (ok) good++; else bad++;

    `uvm_info("OOR_EMP", "=== Phase 4: walk all 8 csrX with patterns ===", UVM_NONE)
    for (i = 0; i < 8; i++) begin
      csr_addrs[i] = REG_CSRX0 + 16'(i * 2);
      csr_vals[i]  = 16'(16'h1000 + (i * 16'h0111));
      write_read_check($sformatf("walk%0d", i), csr_addrs[i], csr_vals[i], ok);
      if (ok) good++; else bad++;
    end

    `uvm_info("OOR_EMP", "=== Phase 5: final re-read sweep ===", UVM_NONE)
    foreach (csr_addrs[i]) begin
      read_only_check($sformatf("final%0d", i), csr_addrs[i], csr_vals[i], ok);
      if (ok) good++; else bad++;
    end

    `uvm_info("OOR_EMP",
      $sformatf("=== SUMMARY: good=%0d bad=%0d ===", good, bad), UVM_NONE)
    if (bad == 0)
      `uvm_info("OOR_EMP", "PASS: no corruption observed despite 3 OOR writes", UVM_NONE)
    else
      `uvm_error("OOR_EMP",
        $sformatf("FAIL: %0d corruption events — OOR writes affected legit CSRs", bad))

    #100;
    phase.drop_objection(this);
  endtask
endclass
