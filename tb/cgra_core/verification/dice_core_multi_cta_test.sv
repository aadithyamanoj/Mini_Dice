// Multi-CTA test: dispatches two sequential CTAs using the same mul_array
// kernel at start_pc=0x0000.  The second CTA hits the bitstream cache
// (cm0_hit in bitstream_fetch_load) and therefore skips the bsfetch AXI
// burst entirely, completing noticeably faster.
//
// Sequence of events:
//   1. Load mfetch / bsfetch memory models (same as smoke test).
//   2. Dispatch CTA 0 (cta_id={0,0,0}) → wait for cta_complete_valid.
//   3. Dispatch CTA 1 (cta_id={1,0,0}) → wait for cta_complete_valid.
//   4. Log elapsed times; both must complete before timeout.

// ---------------------------------------------------------------------------
// Parametric dispatch sequence (one CTA per sequence invocation)
// ---------------------------------------------------------------------------
class cta_one_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_one_seq)

  logic [15:0]             pc       = 16'h0000;
  dice_cta_id_t            cta_id_v = '{x: 0, y: 0, z: 0};
  logic [DICE_TID_WIDTH:0] tcount   = 1;

  function new(string name = "cta_one_seq"); super.new(name); endfunction

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


// ---------------------------------------------------------------------------
// Test body
// ---------------------------------------------------------------------------
class dice_core_multi_cta_test extends dice_core_base_test;
  `uvm_component_utils(dice_core_multi_cta_test)

  localparam int TIMEOUT_CYCLES = 15_000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Wait for one cta_complete_valid pulse; fatal if it doesn't arrive
  // within TIMEOUT_CYCLES clocks.
  task wait_one_complete(string label);
    fork
      begin : w_done
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("MULTI_CTA",
          $sformatf("%s: cta_complete_valid asserted at t=%0t", label, $time), UVM_NONE)
        disable w_timo;
      end
      begin : w_timo
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("MULTI_CTA",
          $sformatf("%s: timeout — cta_complete_valid never fired after %0d cycles",
                    label, TIMEOUT_CYCLES))
        disable w_done;
      end
    join_any
  endtask

  virtual task run_body(uvm_phase phase);
    longint t0, t1, t2, t3;
    cta_one_seq seq;

    // ------------------------------------------------------------------
    // 1. Load pgraph_meta_t into mfetch (same encoding as smoke test).
    //    256-bit frame: struct in LSBs, remaining bits zero.
    // ------------------------------------------------------------------
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h1000;
      mfetch_words[ 1] = 16'hFFF0;
      mfetch_words[ 2] = 16'h00FF;
      mfetch_words[ 3] = 16'h0000;
      mfetch_words[ 4] = 16'h7000;
      mfetch_words[ 5] = 16'h1AC0;
      mfetch_words[ 6] = 16'h0000;
      mfetch_words[ 7] = 16'h0000;
      mfetch_words[ 8] = 16'h0000;
      mfetch_words[ 9] = 16'h0000;
      mfetch_words[10] = 16'h0000;
      mfetch_words[11] = 16'h0000;
      mfetch_words[12] = 16'h0000;
      mfetch_words[13] = 16'h0000;
      mfetch_words[14] = 16'h0000;
      mfetch_words[15] = 16'h0000;
      env.mfetch_agnt.load_mem(16'h0000, mfetch_words);
    end

    // ------------------------------------------------------------------
    // 2. Load compiled bitstream into bsfetch (same as smoke test).
    // ------------------------------------------------------------------
    begin
      logic [15:0] bs_words [107];
      bs_words[  0]=16'h0000; bs_words[  1]=16'h0000; bs_words[  2]=16'h0000;
      bs_words[  3]=16'h0000; bs_words[  4]=16'h0000; bs_words[  5]=16'h0000;
      bs_words[  6]=16'hB864; bs_words[  7]=16'h4671; bs_words[  8]=16'h0009;
      bs_words[  9]=16'h4118; bs_words[ 10]=16'h0040; bs_words[ 11]=16'h0400;
      bs_words[ 12]=16'h0000; bs_words[ 13]=16'h0040; bs_words[ 14]=16'h0A00;
      bs_words[ 15]=16'h0000; bs_words[ 16]=16'h0000; bs_words[ 17]=16'h0100;
      bs_words[ 18]=16'h0000; bs_words[ 19]=16'h0000; bs_words[ 20]=16'h0000;
      bs_words[ 21]=16'h0000; bs_words[ 22]=16'h0000; bs_words[ 23]=16'h0000;
      bs_words[ 24]=16'h0000; bs_words[ 25]=16'h0000; bs_words[ 26]=16'h0000;
      bs_words[ 27]=16'h0000; bs_words[ 28]=16'h6100; bs_words[ 29]=16'h0003;
      bs_words[ 30]=16'h0400; bs_words[ 31]=16'h4000; bs_words[ 32]=16'h0000;
      bs_words[ 33]=16'h0400; bs_words[ 34]=16'hA000; bs_words[ 35]=16'h0000;
      bs_words[ 36]=16'h0000; bs_words[ 37]=16'h1004; bs_words[ 38]=16'h0000;
      bs_words[ 39]=16'h0000; bs_words[ 40]=16'h4000; bs_words[ 41]=16'h0000;
      bs_words[ 42]=16'h0000; bs_words[ 43]=16'h4000; bs_words[ 44]=16'h0000;
      bs_words[ 45]=16'h0000; bs_words[ 46]=16'h0000; bs_words[ 47]=16'h0000;
      bs_words[ 48]=16'h1000; bs_words[ 49]=16'h0036; bs_words[ 50]=16'h4000;
      bs_words[ 51]=16'h0000; bs_words[ 52]=16'h0004; bs_words[ 53]=16'h4000;
      bs_words[ 54]=16'h0000; bs_words[ 55]=16'h000A; bs_words[ 56]=16'h0000;
      bs_words[ 57]=16'h0040; bs_words[ 58]=16'h0001; bs_words[ 59]=16'h0000;
      bs_words[ 60]=16'h0000; bs_words[ 61]=16'h0004; bs_words[ 62]=16'h0000;
      bs_words[ 63]=16'h0000; bs_words[ 64]=16'h0004; bs_words[ 65]=16'h0000;
      bs_words[ 66]=16'h0000; bs_words[ 67]=16'h0000; bs_words[ 68]=16'h0000;
      bs_words[ 69]=16'h0361; bs_words[ 70]=16'h0000; bs_words[ 71]=16'h0004;
      bs_words[ 72]=16'h0040; bs_words[ 73]=16'h0000; bs_words[ 74]=16'h0004;
      bs_words[ 75]=16'h00A0; bs_words[ 76]=16'h0000; bs_words[ 77]=16'h0400;
      bs_words[ 78]=16'h0010; bs_words[ 79]=16'h0000; bs_words[ 80]=16'h0000;
      bs_words[ 81]=16'h0040; bs_words[ 82]=16'h0000; bs_words[ 83]=16'h0000;
      bs_words[ 84]=16'h0040; bs_words[ 85]=16'h0000; bs_words[ 86]=16'h0000;
      bs_words[ 87]=16'h0000; bs_words[ 88]=16'h0000; bs_words[ 89]=16'h3610;
      bs_words[ 90]=16'h0000; bs_words[ 91]=16'h0000; bs_words[ 92]=16'h0000;
      bs_words[ 93]=16'h0000; bs_words[ 94]=16'h0000; bs_words[ 95]=16'h0000;
      bs_words[ 96]=16'h0000; bs_words[ 97]=16'h4000; bs_words[ 98]=16'h0000;
      bs_words[ 99]=16'h0000; bs_words[100]=16'h0000; bs_words[101]=16'h0400;
      bs_words[102]=16'h0000; bs_words[103]=16'h0000; bs_words[104]=16'h0400;
      bs_words[105]=16'h0000; bs_words[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h0000, bs_words);
      // Both CTAs use the same bitstream. CTA 1 hits the FE bsfetch cache
      // (cm0_hit), and the BE sees bank_valid_r[0] still high from CTA 0, so
      // it does NOT re-program the CGRA either. Expect exactly 1 programming
      // shared by both CTAs.
      env.sb.expect_bitstream(bs_words);
    end

    // ------------------------------------------------------------------
    // 3. CSR values (same as smoke test).
    // ------------------------------------------------------------------
    env.cta_agnt.drv.vif.csrX[0] = 16'd256;
    env.cta_agnt.drv.vif.csrX[1] = 16'd512;
    env.cta_agnt.drv.vif.csrX[2] = 16'd768;
    env.cta_agnt.drv.vif.csrX[3] = 16'd8;
    env.cta_agnt.drv.vif.csrX[4] = 16'd0;
    env.cta_agnt.drv.vif.csrX[5] = 16'd1;
    env.cta_agnt.drv.vif.csrX[6] = 16'd2;
    env.cta_agnt.drv.vif.csrX[7] = 16'd3;

    // ------------------------------------------------------------------
    // 4. CTA 0 — fresh bitstream fetch; cm0 will be populated.
    // ------------------------------------------------------------------
    seq           = cta_one_seq::type_id::create("seq0");
    seq.cta_id_v  = '{x: 0, y: 0, z: 0};
    t0 = $time;
    seq.start(env.cta_agnt.seqr);
    `uvm_info("MULTI_CTA", "CTA 0 dispatched", UVM_NONE)
    wait_one_complete("CTA_0");
    t1 = $time;
    `uvm_info("MULTI_CTA",
      $sformatf("CTA 0 elapsed: %0t (includes mfetch + bsfetch AXI + CGRA program + exec)",
                t1 - t0), UVM_NONE)

    // ------------------------------------------------------------------
    // 5. CTA 1 — same kernel address → cm0_hit=1, bsfetch skipped.
    // ------------------------------------------------------------------
    seq           = cta_one_seq::type_id::create("seq1");
    seq.cta_id_v  = '{x: 1, y: 0, z: 0};
    t2 = $time;
    seq.start(env.cta_agnt.seqr);
    `uvm_info("MULTI_CTA", "CTA 1 dispatched (expect bitstream cache hit)", UVM_NONE)
    wait_one_complete("CTA_1");
    t3 = $time;
    `uvm_info("MULTI_CTA",
      $sformatf("CTA 1 elapsed: %0t (bsfetch should be skipped)", t3 - t2), UVM_NONE)

    `uvm_info("MULTI_CTA",
      $sformatf("Speedup: CTA_0=%0t  CTA_1=%0t  delta=%0t",
                t1 - t0, t3 - t2, (t1 - t0) - (t3 - t2)), UVM_NONE)
    `uvm_info("MULTI_CTA", "Both CTAs completed — PASS", UVM_NONE)

    #100;
  endtask

endclass
