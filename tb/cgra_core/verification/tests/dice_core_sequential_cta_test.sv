// dice_core_sequential_cta_test
// -----------------------------
// Dispatches a SECOND CTA after the first one drains. Per the architecture
// (slide 12 of the project deck: "Single CTA design, the same CTA is always
// scheduled"), the FE has one CTA slot — this test verifies that slot can be
// reused: state must reset between dispatches, the new CSRs must take effect,
// and the BE must produce correct output for the second run.
//
// What this validates that the single-CTA tests don't:
//   - Active CTA slot accepts a new dispatch after the prior CTA's retire
//   - Cross-dispatch state isolation: GPRs / dispatcher / mem_req_fifo all
//     clear; no leakage of CTA 0's results into CTA 1
//   - End-to-end flow under a non-(0,0,0) cta_id (CTA 1 uses {1,0,0})
//   - 10 bitstream re-programmings (cm0/cm1 hold CTA 0's last 2 kernels when
//     CTA 1 starts → every kernel re-fetches from bsfetch)
//
// Memory map (disjoint regions so CTA 1's loads don't see CTA 0's stores):
//   CTA 0:  A=0x0001..0x0040  B=0x0080..0x00BF  C=0x0100..0x013F  (canonical)
//   CTA 1:  A=0x0180..0x01BF  B=0x0200..0x023F  C=0x0280..0x02BF
//
// cta_complete_valid only pulses once (the FE asserts it on CTA 0's retire
// and the level stays held). We use scoreboard.stores_seen as the completion
// signal for CTA 1 — see the polling loop in run_body. This is correct
// behavior for a single-CTA scheduler, not a workaround for a bug.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_sequential_cta_test +UVM_VERBOSITY=UVM_LOW

class cta_second_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_second_seq)
  cta_seq_item item;
  int unsigned tcount = 16;
  dice_cta_id_t cta_id_v = '{x: 1, y: 0, z: 0};
  function new(string name = "cta_second_seq"); super.new(name); endfunction
  task body();
    item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = 16'h1000;
    item.thread_count = tcount;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = cta_id_v;
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_sequential_cta_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_sequential_cta_test)

  // CTA 1 needs its own timeout window after CTA 0 completes.
  localparam int CTA1_TIMEOUT_CYCLES = 50_000_000;

  // CTA 1 memory layout (must not overlap CTA 0's 0x0001..0x017F region).
  localparam logic [15:0] CTA1_CSR0 = 16'h0180;  // A_base
  localparam logic [15:0] CTA1_CSR1 = 16'h0200;  // B_base
  localparam logic [15:0] CTA1_CSR2 = 16'h0280;  // C_base

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Register CTA 1's expected stores ON TOP of CTA 0's existing expectations.
  // The scoreboard's expected_data is an associative array keyed by addr,
  // so non-overlapping addresses don't collide.
  function void register_cta1_expectations();
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;

    // Extend read_mem with the mem[i]=i convention for CTA 1's address range
    // (canonical svh only populates 0x0000..0x01FF).
    for (int unsigned i = 16'h0180; i <= 16'h02FF; i++) begin
      env.axil_agnt.drv.read_mem[16'(i)] = 16'(i);
    end

    // Expected stores for CTA 1: data = A * B (mod 2^16) per (tid, lane).
    for (int t = 0; t < 16; t++) begin
      for (int k = 0; k < 4; k++) begin
        a_addr   = CTA1_CSR0 + 16'(4*t + k);
        b_addr   = CTA1_CSR1 + 16'(4*t + k);
        c_addr   = CTA1_CSR2 + 16'(4*t + k);
        a_val    = a_addr;        // mem[i] = i convention
        b_val    = b_addr;
        expected = a_val * b_val;
        env.sb.expect_store(c_addr, expected);
      end
    end
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_second_seq seq2;
    longint t1_start, t1_end;

    // --- CTA 0: identical to full_mul_array_test ---
    super.run_body(phase);
    `uvm_info("SEQ_CTA", "CTA 0 complete; setting up CTA 1", UVM_NONE)

    // --- CTA 1: shifted CSRs, new expected stores ---
    register_cta1_expectations();

    env.cta_agnt.drv.vif.csrX[0] = CTA1_CSR0;
    env.cta_agnt.drv.vif.csrX[1] = CTA1_CSR1;
    env.cta_agnt.drv.vif.csrX[2] = CTA1_CSR2;
    // csrX[3..7] keep parent's values (stride=4, lane_offsets={0,1,2,3})

    seq2 = cta_second_seq::type_id::create("seq2");
    seq2.tcount   = 16;
    seq2.cta_id_v = '{x: 1, y: 0, z: 0};
    t1_start = $time;
    seq2.start(env.cta_agnt.seqr);
    `uvm_info("SEQ_CTA",
      $sformatf("CTA 1 dispatched (cta_id={1,0,0}, csrX0=0x%04x)", CTA1_CSR0),
      UVM_NONE)

    // Single-CTA scheduler: cta_complete_valid asserts once for CTA 0 and
    // stays held. Use scoreboard.stores_seen to detect CTA 1 completion.
    fork
      begin : w_done
        // Total expected = 64 (CTA 0, already done) + 64 (CTA 1)
        while (env.sb.stores_seen < 128) @(posedge env.cta_agnt.mon.vif.clk);
        repeat (50) @(posedge env.cta_agnt.mon.vif.clk);   // tail drain
        t1_end = $time;
        `uvm_info("SEQ_CTA",
          $sformatf("CTA 1 stores complete (128 total); elapsed=%0t ns",
                    (t1_end - t1_start)/1000),
          UVM_NONE)
        disable w_timo;
      end
      begin : w_timo
        repeat (CTA1_TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("SEQ_CTA",
          $sformatf("CTA 1 timeout after %0d cycles (saw %0d/128 stores)",
                    CTA1_TIMEOUT_CYCLES, env.sb.stores_seen))
        disable w_done;
      end
    join_any

    #100;
  endtask

endclass
