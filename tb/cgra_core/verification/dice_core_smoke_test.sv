// Smoke test: dispatches a single CTA for the mul_array kernel.
// Loads real pgraph_meta_t (encoded from compile report) into mfetch and
// the actual compiled bitstream into bsfetch, then waits for cta_complete_valid.
class cta_single_seq extends uvm_sequence #(cta_seq_item);
  `uvm_object_utils(cta_single_seq)
  cta_seq_item item;
  function new(string name = "cta_single_seq"); super.new(name); endfunction
  task body();
    item = cta_seq_item::type_id::create("item");
    start_item(item);
    item.start_pc     = 16'h0000;
    item.thread_count = 1;
    item.grid_size    = '{x: 1, y: 1, z: 1};
    item.cta_id       = '{x: 0, y: 0, z: 0};
    item.hold_cycles  = 1;
    finish_item(item);
  endtask
endclass


class dice_core_smoke_test extends dice_core_base_test;
  `uvm_component_utils(dice_core_smoke_test)

  // Allow plenty of time for bitstream programming (1700 serial bits) + CGRA execution
  localparam int TIMEOUT_CYCLES = 10_000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_single_seq seq;

    // -----------------------------------------------------------------------
    // 1. Load pgraph_meta_t into mfetch at address 0x0000.
    //    Encoding: DICE_METADATA_WIDTH=256 bits, struct in LSBs, 16 beats.
    //    Fields: bitstream_addr=0x0000, bitstream_length=107, lat=7,
    //            in/out_regs=0, num_stores=0, no branch, no barrier.
    //    Beat i maps to meta_flat[i*16 +: 16].
    // -----------------------------------------------------------------------
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h1000;  // branch_reconv, branch_jump, is_return=1 (bit12), branch_neg_pred,
      mfetch_words[ 1] = 16'hFFF0;  // branch_pred_reg=0, branch_uni=0, branch_ena=0, num_stores=0,
                                    //   ld_dest_regs[0]=31, ld_dest_regs[1]=31, ld_dest_regs[2][1:0]=11
      mfetch_words[ 2] = 16'h00FF;  // ld_dest_regs[2][4:2]=111, ld_dest_regs[3]=31, out_regs_bitmap[7:0]=0
      mfetch_words[ 3] = 16'h0000;  // out_regs_bitmap[17:8]=0, in_regs_bitmap[5:0]=0
      mfetch_words[ 4] = 16'h7000;  // in_regs_bitmap[3:0]=0, lat[3:0]=7
      mfetch_words[ 5] = 16'h1AC0;  // lat[7:4]=0, unrolling=0, bitstream_length=107(0x6B), bitstream_addr[1:0]=0
      mfetch_words[ 6] = 16'h0000;  // bitstream_addr[15:2]=0 → addr=0x0000
      mfetch_words[ 7] = 16'h0000;  // (padding — upper 146 bits of 256-bit frame are 0)
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

    // -----------------------------------------------------------------------
    // 2. Load compiled bitstream into bsfetch at address 0x0000.
    //    107 words × 16-bit, little-endian from mini_dice_mul_array.bin.
    //    DUT always fetches exactly 107 beats (DICE_BITSTREAM_SIZE=1700 bits).
    // -----------------------------------------------------------------------
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
    end

    // -----------------------------------------------------------------------
    // 3. Set CSR values (default_csr_values from compile report).
    //    csrX0=A_base, csrX1=B_base, csrX2=C_base, csrX3=stride, csrX4-7=lane offsets.
    // -----------------------------------------------------------------------
    env.cta_agnt.drv.vif.csrX[0] = 16'd256;  // A_base
    env.cta_agnt.drv.vif.csrX[1] = 16'd512;  // B_base
    env.cta_agnt.drv.vif.csrX[2] = 16'd768;  // C_base
    env.cta_agnt.drv.vif.csrX[3] = 16'd8;    // thread_stride
    env.cta_agnt.drv.vif.csrX[4] = 16'd0;
    env.cta_agnt.drv.vif.csrX[5] = 16'd1;
    env.cta_agnt.drv.vif.csrX[6] = 16'd2;
    env.cta_agnt.drv.vif.csrX[7] = 16'd3;

    // -----------------------------------------------------------------------
    // 4. Dispatch CTA through sequencer (driver waits for reset deassert).
    // -----------------------------------------------------------------------
    seq = cta_single_seq::type_id::create("seq");
    seq.start(env.cta_agnt.seqr);
    `uvm_info("SMOKE", $sformatf("CTA dispatched: %s", seq.item.convert2string()), UVM_NONE)

    // -----------------------------------------------------------------------
    // 5. Wait for cta_complete_valid or timeout.
    //    Timeline: ~30c mfetch, ~245c bsfetch, ~1800c CGRA programming,
    //              ~7c execution = ~2100 cycles total. 10k gives 5× margin.
    // -----------------------------------------------------------------------
    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("SMOKE", "cta_complete_valid asserted — PASS", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("SMOKE", $sformatf("Timeout: cta_complete_valid never fired after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    #100;
  endtask

endclass
