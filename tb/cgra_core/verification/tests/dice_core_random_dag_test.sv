// dice_core_random_dag_test
// -------------------------
// Phase-4 random regression. Randomizes the *shape* of execution, not just
// dispatch parameters:
//   - compute_kernel  (MUL or ADD at eblock 2)
//   - csrX0..csrX7    (A_base, B_base, C_base, stride, lane_offsets)
//   - read_mem[A..B]  (random 16-bit values, not the canonical mem[i]=i)
//   - thread_count    (1..32)
//   - inject_err / err_addr / fetch_latency
//
// Expected stores are recomputed at runtime from (kernel, CSRs, A/B data,
// tcount). This is the "real UVM" test that touches code paths the directed
// tests can't reach: different ALU op + different memory layout + different
// data + different active mask, all combined per run.
//
// How to run:
//   ../simv +UVM_TESTNAME=dice_core_random_dag_test \
//           +UVM_VERBOSITY=UVM_LOW +ntb_random_seed=<N>

// Local dispatch sequence: drives one CTA with the configured tcount.
class cta_dag_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_dag_seq)
  cta_seq_item item;
  int unsigned tcount = 32;
  function new(string name = "cta_dag_seq"); super.new(name); endfunction
  task body();
    item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = 16'h1000;
    item.thread_count = tcount;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = '{x: 0, y: 0, z: 0};
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_random_dag_test extends dice_core_full_mul_array_test;
  `uvm_component_utils(dice_core_random_dag_test)

  // 0 = MUL (canonical), 1 = ADD
  typedef enum bit { OP_MUL = 1'b0, OP_ADD = 1'b1 } op_e;

  rand op_e         r_kernel;
  rand int unsigned r_tcount;
  rand logic [15:0] r_csrX0;        // A_base
  rand logic [15:0] r_csrX1;        // B_base
  rand logic [15:0] r_csrX2;        // C_base
  rand logic [15:0] r_csrX3;        // stride (words per tid)
  rand logic [15:0] r_csrX4_7 [4];  // lane offsets
  rand bit          r_inject_err;
  rand logic [15:0] r_err_addr;
  rand int unsigned r_fetch_latency;

  // Random A/B values per (tid, lane). Sized for max 32 threads * 4 lanes.
  rand logic [15:0] r_A [128];
  rand logic [15:0] r_B [128];

  // ----------------------------------------------------------------------
  // Constraints
  // ----------------------------------------------------------------------
  constraint c_kernel  { r_kernel inside {OP_MUL, OP_ADD}; }
  constraint c_tcount  { r_tcount inside {[1:32]}; }

  // CSR ranges chosen so the three regions {A, B, C} don't overlap and
  // stay in the 0x0000..0x01FF window the slave's read_mem covers.
  //   stride is 4 words → max addr touched = base + 31*4 + 3 = base + 127
  //   so we need (base_X + 128) <= base_Y for the next region.
  constraint c_csrs    {
    r_csrX3 == 16'd4;
    r_csrX4_7[0] == 16'd0;
    r_csrX4_7[1] == 16'd1;
    r_csrX4_7[2] == 16'd2;
    r_csrX4_7[3] == 16'd3;
    // A_base in [0, 64], B_base = A_base + 128, C_base = B_base + 128 (= 0x100 region)
    r_csrX0 inside {[16'd0 : 16'd64]};
    r_csrX1 == r_csrX0 + 16'd128;
    r_csrX2 == r_csrX1 + 16'd128;
    // Keep C_base in the 0x0100..0x01FF area so the AXI-Lite slave map fits
    r_csrX2 + 16'd127 <= 16'h01FF;
  }

  // 50/50 SLVERR injection; if injecting, pick a real load address.
  constraint c_err {
    r_inject_err dist {0 := 1, 1 := 1};
    if (r_inject_err) r_err_addr inside {[16'h0000:16'h00FF]};
    else              r_err_addr == 16'h0000;
  }

  constraint c_latency { r_fetch_latency inside {0, 1, 2, 4, 8, 16}; }

  // ----------------------------------------------------------------------
  // Covergroup
  // ----------------------------------------------------------------------
  covergroup cg_dag;
    cp_kernel: coverpoint r_kernel {
      bins b_mul = {OP_MUL};
      bins b_add = {OP_ADD};
    }
    cp_tcount: coverpoint r_tcount {
      bins b_1     = {1};
      bins b_2_8   = {[2:8]};
      bins b_9_16  = {[9:16]};
      bins b_17_24 = {[17:24]};
      bins b_25_31 = {[25:31]};
      bins b_32    = {32};
    }
    cp_csr0: coverpoint r_csrX0 {
      bins b_low  = {[0:15]};
      bins b_mid  = {[16:32]};
      bins b_high = {[33:64]};
    }
    cp_err: coverpoint r_inject_err {
      bins b_no   = {0};
      bins b_yes  = {1};
    }
    cp_lat: coverpoint r_fetch_latency {
      bins b_0    = {0};
      bins b_1    = {1};
      bins b_lo   = {[2:4]};
      bins b_mid  = {[5:8]};
      bins b_hi   = {[9:16]};
    }
    cross_kernel_tcount: cross cp_kernel, cp_tcount;
    cross_kernel_err:    cross cp_kernel, cp_err;
    cross_csr0_kernel:   cross cp_csr0,   cp_kernel;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_dag = new();
  endfunction

  // ----------------------------------------------------------------------
  // The hardcoded add_array.bin bitstream as a 68-word array. Extracted
  // from tests/test_data_add_array.svh — same bytes, same order. Used to
  // overwrite bsfetch[0x0400] when the random run selects the ADD path.
  // ----------------------------------------------------------------------
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

  // ----------------------------------------------------------------------
  // setup_thread_inputs_and_expectations:
  //   1) Pull canonical MUL setup (bitstreams, mfetch, bsfetch, CSRs, expects)
  //   2) If ADD chosen: swap bsfetch[0x0400] + replace expected_bitstreams[2]
  //   3) Override CSRs in vif
  //   4) Override read_mem with random A/B
  //   5) Wipe expected_data, register new expectations per chosen kernel
  // ----------------------------------------------------------------------
  virtual function void setup_thread_inputs_and_expectations();
    logic [15:0] a_addr, b_addr, c_addr, a_val, b_val, expected;
    logic [15:0] add_bs [68];
    logic        add_bits [];
    int          bit_idx;

    super.setup_thread_inputs_and_expectations();

    // ---- 2) Swap eblock-2 bitstream if ADD ----
    if (r_kernel == OP_ADD) begin
      get_add_bitstream(add_bs);
      env.bsfetch_agnt.load_mem(16'h0400, add_bs);
      // Rebuild the bit-array for scoreboard's expect_bitstream entry [2]
      add_bits = new[DICE_BITSTREAM_SIZE];
      for (int i = 0; i < DICE_BITSTREAM_SIZE; i++) begin
        add_bits[i] = add_bs[i / 16][i % 16];
      end
      env.sb.expected_bitstreams[2] = add_bits;
    end

    // ---- 3) Override CSRs in vif ----
    env.cta_agnt.drv.vif.csrX[0] = r_csrX0;
    env.cta_agnt.drv.vif.csrX[1] = r_csrX1;
    env.cta_agnt.drv.vif.csrX[2] = r_csrX2;
    env.cta_agnt.drv.vif.csrX[3] = r_csrX3;
    env.cta_agnt.drv.vif.csrX[4] = r_csrX4_7[0];
    env.cta_agnt.drv.vif.csrX[5] = r_csrX4_7[1];
    env.cta_agnt.drv.vif.csrX[6] = r_csrX4_7[2];
    env.cta_agnt.drv.vif.csrX[7] = r_csrX4_7[3];

    // ---- 4) Override read_mem at A and B addresses with random data ----
    for (int t = 0; t < int'(r_tcount); t++) begin
      for (int k = 0; k < 4; k++) begin
        a_addr = r_csrX0 + 16'(r_csrX3 * t) + r_csrX4_7[k];
        b_addr = r_csrX1 + 16'(r_csrX3 * t) + r_csrX4_7[k];
        env.axil_agnt.drv.read_mem[a_addr] = r_A[t*4 + k];
        env.axil_agnt.drv.read_mem[b_addr] = r_B[t*4 + k];
      end
    end

    // ---- 5) Wipe canonical expects + register new ones ----
    env.sb.expected_data.delete();
    env.sb.stores_expected = 0;
    for (int t = 0; t < int'(r_tcount); t++) begin
      for (int k = 0; k < 4; k++) begin
        c_addr = r_csrX2 + 16'(r_csrX3 * t) + r_csrX4_7[k];
        a_val  = r_A[t*4 + k];
        b_val  = r_B[t*4 + k];
        case (r_kernel)
          OP_MUL : expected = a_val * b_val;
          OP_ADD : expected = a_val + b_val;
        endcase
        env.sb.expect_store(c_addr, expected);
      end
    end

    // ---- Inject SLVERR ----
    if (r_inject_err) begin
      env.axil_agnt.drv.read_resp_err[r_err_addr] = 2'b10;
      env.sb.expect_axil_error(r_err_addr);
    end

    `uvm_info("RAND_DAG",
      $sformatf("op=%s tcount=%0d csrX0..7={%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d} err=%0b lat=%0d → %0d expects",
                (r_kernel==OP_MUL)?"MUL":"ADD", r_tcount,
                r_csrX0, r_csrX1, r_csrX2, r_csrX3,
                r_csrX4_7[0], r_csrX4_7[1], r_csrX4_7[2], r_csrX4_7[3],
                r_inject_err, r_fetch_latency, r_tcount*4),
      UVM_LOW)
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_dag_seq seq;

    if (!this.randomize()) `uvm_fatal("RAND_DAG", "test-level randomize() failed");
    cg_dag.sample();

    // Apply fetch latency BEFORE setup_thread_inputs_and_expectations so it's
    // in effect when the FE begins fetching.
    env.mfetch_agnt.drv.resp_latency  = r_fetch_latency;
    env.bsfetch_agnt.drv.resp_latency = r_fetch_latency;

    setup_thread_inputs_and_expectations();

    seq = cta_dag_seq::type_id::create("seq");
    seq.tcount = r_tcount;
    seq.start(env.cta_agnt.seqr);
    `uvm_info("RAND_DAG", $sformatf("CTA dispatched: %s", seq.item.convert2string()), UVM_NONE)

    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("RAND_DAG", "cta_complete_valid asserted", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("RAND_DAG", $sformatf("Timeout after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    `uvm_info("RAND_DAG",
      $sformatf("Single-seed coverage: cg_dag=%.1f%%", cg_dag.get_coverage()),
      UVM_NONE)

    #100;
  endtask

endclass
