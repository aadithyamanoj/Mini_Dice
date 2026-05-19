// dice_core_sequential_cta_random_test
// ------------------------------------
// Random version of dice_core_sequential_cta_test. Per the single-CTA
// architecture (slide 12), this dispatches two CTAs sequentially through
// the FE's single CTA slot, with INDEPENDENTLY randomized per-CTA:
//   - thread_count
//   - kernel op (MUL or ADD)
//   - CSR layout (A_base, B_base, C_base) — disjoint between CTAs
//   - A and B random data values per (tid, lane)
//
// Uses scoreboard.stores_seen for CTA 1 completion detection (the FE's
// cta_complete_valid pulses once for the first CTA and holds, per design).
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_sequential_cta_random_test \
//           +UVM_VERBOSITY=UVM_LOW +ntb_random_seed=<N>

class cta_rand_multi_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_rand_multi_seq)
  cta_seq_item item;
  int unsigned tcount = 32;
  dice_cta_id_t cta_id_v = '{x: 0, y: 0, z: 0};
  function new(string name = "cta_rand_multi_seq"); super.new(name); endfunction
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


class dice_core_sequential_cta_random_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_sequential_cta_random_test)

  typedef enum bit { OP_MUL = 1'b0, OP_ADD = 1'b1 } op_e;

  // Per-CTA randomized knobs (indexed [0] = CTA 0, [1] = CTA 1)
  rand op_e         r_kernel [2];
  rand int unsigned r_tcount [2];
  rand logic [15:0] r_csr0   [2];   // A_base
  rand logic [15:0] r_csr1   [2];   // B_base
  rand logic [15:0] r_csr2   [2];   // C_base
  rand logic [15:0] r_A      [2][128];
  rand logic [15:0] r_B      [2][128];

  // Each CTA's memory region (A | B | C) occupies 384 bytes (128 each for
  // A, B, C). Place them in disjoint windows of the 0..0x3FF address space:
  //   CTA 0: A_base in [0x0000:0x0040], B = A+128, C = B+128
  //   CTA 1: A_base in [0x0200:0x0240], B = A+128, C = B+128
  constraint c_per_cta {
    foreach (r_kernel[i]) r_kernel[i] inside {OP_MUL, OP_ADD};
    foreach (r_tcount[i]) r_tcount[i] inside {[1:32]};
    r_csr0[0] inside {[16'h0000 : 16'h0040]};
    r_csr1[0] == r_csr0[0] + 16'd128;
    r_csr2[0] == r_csr1[0] + 16'd128;
    r_csr0[1] inside {[16'h0200 : 16'h0240]};
    r_csr1[1] == r_csr0[1] + 16'd128;
    r_csr2[1] == r_csr1[1] + 16'd128;
  }

  // Functional coverage tracking what (kernel, tcount) pairs run per CTA.
  covergroup cg_seq_cta;
    cp_cta0_kernel: coverpoint r_kernel[0] { bins b_mul = {OP_MUL}; bins b_add = {OP_ADD}; }
    cp_cta1_kernel: coverpoint r_kernel[1] { bins b_mul = {OP_MUL}; bins b_add = {OP_ADD}; }
    cp_cta0_tcount: coverpoint r_tcount[0] {
      bins b_lo  = {[1:8]};
      bins b_mid = {[9:24]};
      bins b_hi  = {[25:32]};
    }
    cp_cta1_tcount: coverpoint r_tcount[1] {
      bins b_lo  = {[1:8]};
      bins b_mid = {[9:24]};
      bins b_hi  = {[25:32]};
    }
    cross_kernel_pair: cross cp_cta0_kernel, cp_cta1_kernel;
    cross_tcount_pair: cross cp_cta0_tcount, cp_cta1_tcount;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_seq_cta = new();
  endfunction

  // Hardcoded mul_array.bin words (canonical eblock-2 bitstream).
  function automatic void get_mul_bitstream(ref logic [15:0] bs [68]);
    bs[ 0]=16'h0000; bs[ 1]=16'h0000; bs[ 2]=16'h0000; bs[ 3]=16'h0000;
    bs[ 4]=16'h0000; bs[ 5]=16'h1900; bs[ 6]=16'h9C6E; bs[ 7]=16'h0251;
    bs[ 8]=16'h4600; bs[ 9]=16'h1010; bs[10]=16'h0000; bs[11]=16'h0011;
    bs[12]=16'h0280; bs[13]=16'h4000; bs[14]=16'h0000; bs[15]=16'h0000;
    bs[16]=16'h0000; bs[17]=16'h0000; bs[18]=16'h0000; bs[19]=16'h0000;
    bs[20]=16'h1B08; bs[21]=16'h0000; bs[22]=16'h0010; bs[23]=16'h1100;
    bs[24]=16'h8000; bs[25]=16'h1002; bs[26]=16'h0040; bs[27]=16'h0000;
    bs[28]=16'h0001; bs[29]=16'h0100; bs[30]=16'h0000; bs[31]=16'h0000;
    bs[32]=16'h0800; bs[33]=16'h001B; bs[34]=16'h1000; bs[35]=16'h0000;
    bs[36]=16'h0011; bs[37]=16'h0280; bs[38]=16'h4010; bs[39]=16'h0000;
    bs[40]=16'h0100; bs[41]=16'h0000; bs[42]=16'h0001; bs[43]=16'h0000;
    bs[44]=16'h0000; bs[45]=16'h1B08; bs[46]=16'h0000; bs[47]=16'h0010;
    bs[48]=16'h1100; bs[49]=16'h8000; bs[50]=16'h1002; bs[51]=16'h0040;
    bs[52]=16'h0000; bs[53]=16'h0001; bs[54]=16'h0100; bs[55]=16'h0000;
    bs[56]=16'h0000; bs[57]=16'h0800; bs[58]=16'h001B; bs[59]=16'h0000;
    bs[60]=16'h0000; bs[61]=16'h0000; bs[62]=16'h0000; bs[63]=16'h0010;
    bs[64]=16'h0000; bs[65]=16'h0100; bs[66]=16'h0000; bs[67]=16'h0001;
  endfunction

  // The hardcoded add_array.bin words.
  function automatic void get_add_bitstream(ref logic [15:0] bs [68]);
    bs[ 0]=16'h0000; bs[ 1]=16'h0000; bs[ 2]=16'h0000; bs[ 3]=16'h0000;
    bs[ 4]=16'h0000; bs[ 5]=16'h1900; bs[ 6]=16'h9C6E; bs[ 7]=16'h0251;
    bs[ 8]=16'h4600; bs[ 9]=16'h1010; bs[10]=16'h0000; bs[11]=16'h0011;
    bs[12]=16'h0280; bs[13]=16'h4000; bs[14]=16'h0000; bs[15]=16'h0000;
    bs[16]=16'h0000; bs[17]=16'h0000; bs[18]=16'h0000; bs[19]=16'h0000;
    bs[20]=16'h0B08; bs[21]=16'h0000; bs[22]=16'h0010; bs[23]=16'h1100;
    bs[24]=16'h8000; bs[25]=16'h1002; bs[26]=16'h0040; bs[27]=16'h0000;
    bs[28]=16'h0001; bs[29]=16'h0100; bs[30]=16'h0000; bs[31]=16'h0000;
    bs[32]=16'h0800; bs[33]=16'h000B; bs[34]=16'h1000; bs[35]=16'h0000;
    bs[36]=16'h0011; bs[37]=16'h0280; bs[38]=16'h4010; bs[39]=16'h0000;
    bs[40]=16'h0100; bs[41]=16'h0000; bs[42]=16'h0001; bs[43]=16'h0000;
    bs[44]=16'h0000; bs[45]=16'h0B08; bs[46]=16'h0000; bs[47]=16'h0010;
    bs[48]=16'h1100; bs[49]=16'h8000; bs[50]=16'h1002; bs[51]=16'h0040;
    bs[52]=16'h0000; bs[53]=16'h0001; bs[54]=16'h0100; bs[55]=16'h0000;
    bs[56]=16'h0000; bs[57]=16'h0800; bs[58]=16'h000B; bs[59]=16'h0000;
    bs[60]=16'h0000; bs[61]=16'h0000; bs[62]=16'h0000; bs[63]=16'h0010;
    bs[64]=16'h0000; bs[65]=16'h0100; bs[66]=16'h0000; bs[67]=16'h0001;
  endfunction

  // Apply CTA i's kernel-choice bitstream patch + CSR override + read_mem
  // + expected_stores registration.
  function void apply_cta_config(int i);
    logic [15:0] bs [68];
    logic        bits [];
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;

    // ALWAYS load the bitstream for this CTA's chosen op, since the previous
    // CTA may have left a different one in bsfetch[0x0400].
    if (r_kernel[i] == OP_ADD) get_add_bitstream(bs);
    else                        get_mul_bitstream(bs);
    env.bsfetch_agnt.load_mem(16'h0400, bs);
    // expected_bitstreams[] is the scoreboard's queue of golden bitstream
    // content. It's populated once (during super.setup, 5 entries) and
    // popped per CGRA programming epoch. By the time CTA 1 starts it's
    // empty — only patch entry [2] if it still exists (i.e., before CTA 0).
    if (env.sb.expected_bitstreams.size() > 2) begin
      bits = new[DICE_BITSTREAM_SIZE];
      for (int b = 0; b < DICE_BITSTREAM_SIZE; b++) bits[b] = bs[b/16][b%16];
      env.sb.expected_bitstreams[2] = bits;
    end

    env.cta_agnt.drv.vif.csrX[0] = r_csr0[i];
    env.cta_agnt.drv.vif.csrX[1] = r_csr1[i];
    env.cta_agnt.drv.vif.csrX[2] = r_csr2[i];
    // csrX[3..7] keep canonical (stride=4, lane offsets 0..3)

    for (int t = 0; t < int'(r_tcount[i]); t++) begin
      for (int k = 0; k < 4; k++) begin
        a_addr = r_csr0[i] + 16'(4*t + k);
        b_addr = r_csr1[i] + 16'(4*t + k);
        c_addr = r_csr2[i] + 16'(4*t + k);
        env.axil_agnt.drv.read_mem[a_addr] = r_A[i][t*4 + k];
        env.axil_agnt.drv.read_mem[b_addr] = r_B[i][t*4 + k];
        a_val  = r_A[i][t*4 + k];
        b_val  = r_B[i][t*4 + k];
        expected = (r_kernel[i] == OP_MUL) ? (a_val * b_val) : (a_val + b_val);
        env.sb.expect_store(c_addr, expected);
      end
    end
  endfunction

  virtual function void setup_thread_inputs_and_expectations();
    super.setup_thread_inputs_and_expectations();   // canonical mfetch/bsfetch + 128 mul expects
    env.sb.expected_data.delete();                    // wipe canonical store expects
    env.sb.stores_expected = 0;

    // Register CTA 0's random expectations (CTA 1's get added before its dispatch)
    apply_cta_config(0);

    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA 0: op=%s tcount=%0d csr0=0x%04x → %0d stores",
                (r_kernel[0]==OP_MUL)?"MUL":"ADD", r_tcount[0], r_csr0[0],
                r_tcount[0]*4),
      UVM_LOW)
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_rand_multi_seq seq0, seq1;
    int unsigned stores_after_cta0;

    if (!this.randomize()) `uvm_fatal("SEQ_CTA_RAND", "randomize() failed");
    cg_seq_cta.sample();

    setup_thread_inputs_and_expectations();

    // -- Dispatch CTA 0 --
    seq0 = cta_rand_multi_seq::type_id::create("seq0");
    seq0.tcount   = r_tcount[0];
    seq0.cta_id_v = '{x: 0, y: 0, z: 0};
    seq0.start(env.cta_agnt.seqr);
    `uvm_info("SEQ_CTA_RAND", "CTA 0 dispatched", UVM_NONE)

    // Wait for CTA 0's stores to land (use cta_complete since it works the
    // first time; the workaround is only needed for CTA 1).
    fork
      begin : w0_done
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        disable w0_timo;
      end
      begin : w0_timo
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("SEQ_CTA_RAND", "CTA 0 timeout")
        disable w0_done;
      end
    join_any
    stores_after_cta0 = env.sb.stores_seen;
    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA 0 complete (saw %0d stores)", stores_after_cta0),
      UVM_NONE)

    // -- Configure + dispatch CTA 1 --
    apply_cta_config(1);
    `uvm_info("SEQ_CTA_RAND",
      $sformatf("CTA 1: op=%s tcount=%0d csr0=0x%04x → %0d stores",
                (r_kernel[1]==OP_MUL)?"MUL":"ADD", r_tcount[1], r_csr0[1],
                r_tcount[1]*4),
      UVM_LOW)

    seq1 = cta_rand_multi_seq::type_id::create("seq1");
    seq1.tcount   = r_tcount[1];
    seq1.cta_id_v = '{x: 1, y: 0, z: 0};
    seq1.start(env.cta_agnt.seqr);
    `uvm_info("SEQ_CTA_RAND", "CTA 1 dispatched", UVM_NONE)

    // Poll for CTA 1's stores (cta_complete_valid stays high, see workaround
    // explanation in dice_core_sequential_cta_test).
    fork
      begin : w1_done
        int unsigned expected_after_cta1 = stores_after_cta0 + r_tcount[1] * 4;
        while (env.sb.stores_seen < expected_after_cta1) @(posedge env.cta_agnt.mon.vif.clk);
        repeat (50) @(posedge env.cta_agnt.mon.vif.clk);  // tail drain
        `uvm_info("SEQ_CTA_RAND",
          $sformatf("CTA 1 stores complete (%0d total)", env.sb.stores_seen),
          UVM_NONE)
        disable w1_timo;
      end
      begin : w1_timo
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("SEQ_CTA_RAND",
          $sformatf("CTA 1 timeout (saw %0d/%0d stores)",
                    env.sb.stores_seen, stores_after_cta0 + r_tcount[1] * 4))
        disable w1_done;
      end
    join_any

    #100;
  endtask

endclass
