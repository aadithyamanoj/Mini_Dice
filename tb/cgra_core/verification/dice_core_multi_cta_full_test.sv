// Multi-CTA full-pipeline test.
// Reuses full_mul_array_test for the 5-eblock kernel (load_a → load_b → mul →
// compute_store_addrs → store) and dispatches a SECOND CTA after the first
// completes, with non-overlapping memory regions and different input data.
//
// What this validates that single-CTA full_mul_array_test does NOT:
//   - active_cta_table accepts a second CTA after the first drains.
//   - CTAs with cta_id={1,0,0} flow through the FE/BE end-to-end.
//   - Cross-CTA state isolation: GPRs, dispatcher, mem_req_fifo all clear.
//   - Same-kernel cache behavior in practice (shared scan-chain programming).
//
// Memory map:
//   CTA 0: A=[2,3,4,5]@0x0100..0x0103, B=[3,4,5,6]@0x0200..0x0203, C@0x0300
//          (inherited from parent test, default CSRs)
//   CTA 1: A=[10,20,30,40]@0x0400..0x0403, B=[1,2,3,4]@0x0500..0x0503, C@0x0600
//
// Stores expected (16 stores total = 4 per CTA × 2 CTAs... actually 4+4=8,
// because 4 lanes × 1 thread × 2 CTAs):
//   CTA 0: (0x0300,30),(0x0301,20),(0x0302,12),(0x0303,6)         [parent]
//   CTA 1: (0x0600,160),(0x0601,90),(0x0602,40),(0x0603,10)       [this test]
//
// Bitstream programmings observed:
//   10 — five per CTA, no caching across CTAs. The FE has only 2 bitstream
//   banks (cm0, cm1), so by the time CTA 1 fetches kernel 0, both banks hold
//   CTA 0's most recent kernels (3 and 4). Every CTA-boundary kernel fetch is
//   a cache miss, so every kernel re-programs. (Contrast with the original
//   single-bitstream multi_cta_test, where both CTAs use the same one kernel
//   and share programming.) Parent registers 5 expected bitstreams; CTA 1's
//   five extras are logged as "no expectation registered" (still verified to
//   be exactly 1700 bits each).
class cta_id_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_id_seq)

  logic [15:0]             pc       = 16'h0000;
  dice_cta_id_t            cta_id_v = '{x: 1, y: 0, z: 0};
  logic [DICE_TID_WIDTH:0] tcount   = 1;

  function new(string name = "cta_id_seq"); super.new(name); endfunction

  task body();
    cta_seq_item item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = pc;
    item.thread_count = tcount;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = cta_id_v;
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_multi_cta_full_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_multi_cta_full_test)

  localparam int CTA1_TIMEOUT_CYCLES = 12_000_000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_id_seq seq2;
    longint t1_start, t1_end;

    // -----------------------------------------------------------------------
    // Run parent: loads all 5 kernels into mfetch/bsfetch, registers parent's
    // expected bitstreams + CTA-0 expected stores + CTA-0 input data + CSRs,
    // dispatches CTA 0, waits for completion.
    // -----------------------------------------------------------------------
    super.run_body(phase);
    `uvm_info("MULTI_FULL", "CTA 0 complete; setting up CTA 1", UVM_NONE)

    // -----------------------------------------------------------------------
    // CTA 1: distinct input data and output region.
    // -----------------------------------------------------------------------
    env.axil_agnt.drv.read_mem[16'h0400] = 16'd10;
    env.axil_agnt.drv.read_mem[16'h0401] = 16'd20;
    env.axil_agnt.drv.read_mem[16'h0402] = 16'd30;
    env.axil_agnt.drv.read_mem[16'h0403] = 16'd40;
    env.axil_agnt.drv.read_mem[16'h0500] = 16'd1;
    env.axil_agnt.drv.read_mem[16'h0501] = 16'd2;
    env.axil_agnt.drv.read_mem[16'h0502] = 16'd3;
    env.axil_agnt.drv.read_mem[16'h0503] = 16'd4;

    // Expected: C[k] = A[3-k] * B[3-k]  (lane reversal is in the bitstream).
    env.sb.expect_store(16'h0600, 16'd160);  // 40 * 4
    env.sb.expect_store(16'h0601, 16'd90);   // 30 * 3
    env.sb.expect_store(16'h0602, 16'd40);   // 20 * 2
    env.sb.expect_store(16'h0603, 16'd10);   // 10 * 1

    // CSRs: redirect base addresses; keep stride and lane offsets.
    env.cta_agnt.drv.vif.csrX[0] = 16'h0400;  // A_base
    env.cta_agnt.drv.vif.csrX[1] = 16'h0500;  // B_base
    env.cta_agnt.drv.vif.csrX[2] = 16'h0600;  // C_base
    // csrX[3..7] left at parent's values (8, 0, 1, 2, 3).

    seq2 = cta_id_seq::type_id::create("seq2");
    seq2.cta_id_v = '{x: 1, y: 0, z: 0};
    t1_start = $time;
    seq2.start(env.cta_agnt.seqr);
    `uvm_info("MULTI_FULL", "CTA 1 dispatched (cta_id={1,0,0})", UVM_NONE)

    fork
      begin : w_done
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        t1_end = $time;
        `uvm_info("MULTI_FULL",
          $sformatf("CTA 1 complete; elapsed=%0t", t1_end - t1_start), UVM_NONE)
        disable w_timo;
      end
      begin : w_timo
        repeat (CTA1_TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("MULTI_FULL",
          $sformatf("CTA 1 timeout after %0d cycles", CTA1_TIMEOUT_CYCLES))
        disable w_done;
      end
    join_any

    #100;
  endtask

endclass
