// Full 5-stage mul_array correctness test.
// Exercises the complete load→compute→store pipeline:
//   Stage 1: load_mul_array_a  (A[0..3] → GPR[3..0])
//   Stage 2: load_mul_array_b  (B[0..3] → GPR[7..4])
//   Stage 3: mul_array         (GPR[k]*GPR[k+4] → GPR[k], k=0..3)
//   Stage 4: compute_store_addrs (C base+offsets → GPR[7..4])
//   Stage 5: store_mul_array   (GPR[k] → mem[GPR[k+4]], k=0..3)
//
// CSRs: csrX0=0x0100(A_base), csrX1=0x0200(B_base), csrX2=0x0300(C_base),
//       csrX3=8(stride), csrX4..7=0..3(lane offsets)
// Input:  A=[2,3,4,5] at 0x0100..0x0103, B=[3,4,5,6] at 0x0200..0x0203
// Expected stores: (0x0300,30),(0x0301,20),(0x0302,12),(0x0303,6)
class dice_core_full_mul_array_test extends dice_core_base_test;
  `uvm_component_utils(dice_core_full_mul_array_test)

  // CGRA scan-chain programming takes ~1.7M cycles per stage (serial bit loading).
  // 5 stages × ~1.7M cycles = ~8.5M cycles; use 12M for margin.
  localparam int TIMEOUT_CYCLES = 12_000_000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Inputs at A_base/B_base, expected stores at C_base, and CSR base values.
  // Subclasses can override to swap in different test data without rewriting
  // the kernel/metadata loading. Default = canonical values from compile report.
  virtual function void setup_thread_inputs_and_expectations();
    env.axil_agnt.drv.read_mem[16'h0100] = 16'd2;  // A[0]
    env.axil_agnt.drv.read_mem[16'h0101] = 16'd3;  // A[1]
    env.axil_agnt.drv.read_mem[16'h0102] = 16'd4;  // A[2]
    env.axil_agnt.drv.read_mem[16'h0103] = 16'd5;  // A[3]
    env.axil_agnt.drv.read_mem[16'h0200] = 16'd3;  // B[0]
    env.axil_agnt.drv.read_mem[16'h0201] = 16'd4;  // B[1]
    env.axil_agnt.drv.read_mem[16'h0202] = 16'd5;  // B[2]
    env.axil_agnt.drv.read_mem[16'h0203] = 16'd6;  // B[3]

    env.sb.expect_store(16'h0300, 16'd30);
    env.sb.expect_store(16'h0301, 16'd20);
    env.sb.expect_store(16'h0302, 16'd12);
    env.sb.expect_store(16'h0303, 16'd6);

    env.cta_agnt.drv.vif.csrX[0] = 16'd256;  // A_base  (0x0100)
    env.cta_agnt.drv.vif.csrX[1] = 16'd512;  // B_base  (0x0200)
    env.cta_agnt.drv.vif.csrX[2] = 16'd768;  // C_base  (0x0300)
    env.cta_agnt.drv.vif.csrX[3] = 16'd8;    // thread_stride
    env.cta_agnt.drv.vif.csrX[4] = 16'd0;    // lane_offset[0]
    env.cta_agnt.drv.vif.csrX[5] = 16'd1;    // lane_offset[1]
    env.cta_agnt.drv.vif.csrX[6] = 16'd2;    // lane_offset[2]
    env.cta_agnt.drv.vif.csrX[7] = 16'd3;    // lane_offset[3]
  endfunction

  virtual task run_body(uvm_phase phase);
    cta_single_seq seq;

    // -----------------------------------------------------------------------
    // 1. Load pgraph_meta_t for all 5 stages into mfetch.
    //
    //    pgraph_meta_t bit layout (110 bits, LSB=bit0):
    //      [0]      parameter_load
    //      [1]      barrier
    //      [16:2]   branch_meta {branch_ena,branch_uni,branch_pred_reg[0],
    //                            branch_neg_pred,is_return,
    //                            branch_jump_target_offset[4:0],
    //                            branch_reconv_offset[4:0]}
    //      [19:17]  num_stores[2:0]
    //      [39:20]  ld_dest_regs[3:0][4:0]  (ld_dest_regs[3]=MSBs)
    //      [57:40]  out_regs_bitmap[17:0]
    //      [75:58]  in_regs_bitmap[17:0]
    //      [83:76]  lat[7:0]
    //      [85:84]  unrolling_factor[1:0]
    //      [93:86]  bitstream_length[7:0]
    //      [109:94] bitstream_addr[15:0]
    //    mfetch_words[i] = meta_flat[i*16+15 : i*16].
    // -----------------------------------------------------------------------

    // --- Stage 1: load_mul_array_a ---
    // ld_dest_regs={0,1,2,3}, out_regs=0x000F(GPR[0..3]),
    // in_regs=0, lat=11, bs_addr=0x0000, bs_len=107, is_return=0
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h0000;  // branch_meta all 0 (no branch, is_return=0)
      mfetch_words[ 1] = 16'h8200;  // branch_ena=0, num_stores=0,
                                    //   ld_dest_regs={0,1,2[1:0]=00}
      mfetch_words[ 2] = 16'h0F18;  // ld_dest_regs={2[4:2]=0,3=3}, out_regs[7:0]=0x0F
      mfetch_words[ 3] = 16'h0000;  // out_regs[17:8]=0, in_regs[5:0]=0
      mfetch_words[ 4] = 16'hB000;  // in_regs[17:6]=0, lat[3:0]=0xB(=11)
      mfetch_words[ 5] = 16'h1AC0;  // lat[7:4]=0, unroll=0, bs_len=107, bs_addr[1:0]=0
      mfetch_words[ 6] = 16'h0000;  // bs_addr[15:2]=0x0000
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
      env.sb.expect_mfetch(16'h0000);
    end

    // --- Stage 2: load_mul_array_b ---
    // ld_dest_regs={4,5,6,7}, out_regs=0x00F0(GPR[4..7]),
    // in_regs=0, lat=11, bs_addr=0x006B, bs_len=107, is_return=0
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h0000;
      mfetch_words[ 1] = 16'h8A40;  // ld_dest_regs={4,5,6[1:0]=10}
      mfetch_words[ 2] = 16'hF039;  // ld_dest_regs={6[4:2]=1,7}, out_regs[7:0]=0xF0
      mfetch_words[ 3] = 16'h0000;
      mfetch_words[ 4] = 16'hB000;  // lat=11
      mfetch_words[ 5] = 16'hDAC0;  // bs_len=107, bs_addr[1:0]=3(0x006B mod 4=3)
      mfetch_words[ 6] = 16'h001A;  // bs_addr[15:2]=0x001A (0x006B>>2=26)
      mfetch_words[ 7] = 16'h0000;
      mfetch_words[ 8] = 16'h0000;
      mfetch_words[ 9] = 16'h0000;
      mfetch_words[10] = 16'h0000;
      mfetch_words[11] = 16'h0000;
      mfetch_words[12] = 16'h0000;
      mfetch_words[13] = 16'h0000;
      mfetch_words[14] = 16'h0000;
      mfetch_words[15] = 16'h0000;
      env.mfetch_agnt.load_mem(16'h0100, mfetch_words);
      env.sb.expect_mfetch(16'h0100);
    end

    // --- Stage 3: mul_array ---
    // ld_dest_regs={31,31,31,31}, out_regs=0x000F(GPR[0..3]),
    // in_regs=0x00FF(GPR[0..7]), lat=7, bs_addr=0x00D6, bs_len=107, is_return=0
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h0000;
      mfetch_words[ 1] = 16'hFFF0;  // ld_dest_regs[0..1]=31, [2][1:0]=11
      mfetch_words[ 2] = 16'h0FFF;  // ld_dest_regs[2][4:2]=111,[3]=31, out_regs[7:0]=0x0F
      mfetch_words[ 3] = 16'hFC00;  // out_regs[17:8]=0, in_regs[5:0]=0b111111
      mfetch_words[ 4] = 16'h7003;  // in_regs[7:6]=11, [17:8]=0, lat[3:0]=7
      mfetch_words[ 5] = 16'h9AC0;  // lat[7:4]=0, unroll=0, bs_len=107, bs_addr[1]=1
      mfetch_words[ 6] = 16'h0035;  // bs_addr[15:2]=0x0035 (0x00D6>>2=53)
      mfetch_words[ 7] = 16'h0000;
      mfetch_words[ 8] = 16'h0000;
      mfetch_words[ 9] = 16'h0000;
      mfetch_words[10] = 16'h0000;
      mfetch_words[11] = 16'h0000;
      mfetch_words[12] = 16'h0000;
      mfetch_words[13] = 16'h0000;
      mfetch_words[14] = 16'h0000;
      mfetch_words[15] = 16'h0000;
      env.mfetch_agnt.load_mem(16'h0200, mfetch_words);
      env.sb.expect_mfetch(16'h0200);
    end

    // --- Stage 4: compute_store_addrs ---
    // ld_dest_regs={31,31,31,31}, out_regs=0x00F0(GPR[4..7]),
    // in_regs=0, lat=11, bs_addr=0x0141, bs_len=107, is_return=0
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h0000;
      mfetch_words[ 1] = 16'hFFF0;
      mfetch_words[ 2] = 16'hF0FF;  // ld_dest_regs[2..3]=31, out_regs[7:0]=0xF0
      mfetch_words[ 3] = 16'h0000;
      mfetch_words[ 4] = 16'hB000;  // lat=11
      mfetch_words[ 5] = 16'h5AC0;  // bs_len=107, bs_addr[0]=1(0x0141 bit0=1)
      mfetch_words[ 6] = 16'h0050;  // bs_addr[15:2]=0x0050 (0x0141>>2=80)
      mfetch_words[ 7] = 16'h0000;
      mfetch_words[ 8] = 16'h0000;
      mfetch_words[ 9] = 16'h0000;
      mfetch_words[10] = 16'h0000;
      mfetch_words[11] = 16'h0000;
      mfetch_words[12] = 16'h0000;
      mfetch_words[13] = 16'h0000;
      mfetch_words[14] = 16'h0000;
      mfetch_words[15] = 16'h0000;
      env.mfetch_agnt.load_mem(16'h0300, mfetch_words);
      env.sb.expect_mfetch(16'h0300);
    end

    // --- Stage 5: store_mul_array ---
    // ld_dest_regs={31,31,31,31}, out_regs=0, num_stores=4,
    // in_regs=0x00FF(GPR[0..7]), lat=5, bs_addr=0x01AC, bs_len=107, is_return=1
    begin
      logic [15:0] mfetch_words [16];
      mfetch_words[ 0] = 16'h1000;  // is_return=1 (bit12)
      mfetch_words[ 1] = 16'hFFF8;  // num_stores=4(bit19=1), ld_dest_regs[0..1]=31,[2][1:0]=11
      mfetch_words[ 2] = 16'h00FF;  // ld_dest_regs[2..3]=31, out_regs=0
      mfetch_words[ 3] = 16'hFC00;  // in_regs[5:0]=0b111111
      mfetch_words[ 4] = 16'h5003;  // in_regs[7:6]=11, lat[3:0]=5
      mfetch_words[ 5] = 16'h1AC0;  // lat[7:4]=0, bs_len=107, bs_addr[1:0]=0
      mfetch_words[ 6] = 16'h006B;  // bs_addr[15:2]=0x006B (0x01AC>>2=107)
      mfetch_words[ 7] = 16'h0000;
      mfetch_words[ 8] = 16'h0000;
      mfetch_words[ 9] = 16'h0000;
      mfetch_words[10] = 16'h0000;
      mfetch_words[11] = 16'h0000;
      mfetch_words[12] = 16'h0000;
      mfetch_words[13] = 16'h0000;
      mfetch_words[14] = 16'h0000;
      mfetch_words[15] = 16'h0000;
      env.mfetch_agnt.load_mem(16'h0400, mfetch_words);
      env.sb.expect_mfetch(16'h0400);
    end

    // -----------------------------------------------------------------------
    // 2. Load all 5 bitstreams into bsfetch.
    //    107 words × 16-bit, consecutive starting at their stage address.
    //    Stage offsets: 0x0000, 0x006B, 0x00D6, 0x0141, 0x01AC (each +107).
    // -----------------------------------------------------------------------

    // --- load_mul_array_a bitstream at bsfetch[0x0000] ---
    begin
      logic [15:0] bs [107];
      bs[  0]=16'h0000; bs[  1]=16'h0000; bs[  2]=16'h2298; bs[  3]=16'h0000;
      bs[  4]=16'h0000; bs[  5]=16'h0000; bs[  6]=16'h0000; bs[  7]=16'h3C80;
      bs[  8]=16'hE800; bs[  9]=16'hD42D; bs[ 10]=16'h0002; bs[ 11]=16'h0000;
      bs[ 12]=16'h0000; bs[ 13]=16'h0000; bs[ 14]=16'h0000; bs[ 15]=16'h0000;
      bs[ 16]=16'h0000; bs[ 17]=16'h0000; bs[ 18]=16'h0000; bs[ 19]=16'h0280;
      bs[ 20]=16'h0020; bs[ 21]=16'h0000; bs[ 22]=16'h0000; bs[ 23]=16'h0080;
      bs[ 24]=16'h0000; bs[ 25]=16'h4000; bs[ 26]=16'h0068; bs[ 27]=16'h0000;
      bs[ 28]=16'h0000; bs[ 29]=16'h0000; bs[ 30]=16'h0000; bs[ 31]=16'h0200;
      bs[ 32]=16'h0000; bs[ 33]=16'h0000; bs[ 34]=16'h0000; bs[ 35]=16'h0000;
      bs[ 36]=16'h0900; bs[ 37]=16'h0000; bs[ 38]=16'h0000; bs[ 39]=16'h0000;
      bs[ 40]=16'h0200; bs[ 41]=16'h0000; bs[ 42]=16'h0800; bs[ 43]=16'h0800;
      bs[ 44]=16'h0000; bs[ 45]=16'h0000; bs[ 46]=16'h0681; bs[ 47]=16'h0000;
      bs[ 48]=16'h4400; bs[ 49]=16'h0011; bs[ 50]=16'h0448; bs[ 51]=16'h0010;
      bs[ 52]=16'h0000; bs[ 53]=16'h0000; bs[ 54]=16'h070C; bs[ 55]=16'h0000;
      bs[ 56]=16'h0000; bs[ 57]=16'h0340; bs[ 58]=16'h0000; bs[ 59]=16'h0000;
      bs[ 60]=16'h0000; bs[ 61]=16'h0004; bs[ 62]=16'h0000; bs[ 63]=16'h0000;
      bs[ 64]=16'h0004; bs[ 65]=16'h0000; bs[ 66]=16'h0000; bs[ 67]=16'h0000;
      bs[ 68]=16'h0000; bs[ 69]=16'h0000; bs[ 70]=16'h0000; bs[ 71]=16'h0000;
      bs[ 72]=16'h0000; bs[ 73]=16'h0000; bs[ 74]=16'h0006; bs[ 75]=16'h0000;
      bs[ 76]=16'h0000; bs[ 77]=16'h0006; bs[ 78]=16'h0002; bs[ 79]=16'h0000;
      bs[ 80]=16'h0000; bs[ 81]=16'h000A; bs[ 82]=16'h0000; bs[ 83]=16'h0000;
      bs[ 84]=16'h0040; bs[ 85]=16'h0000; bs[ 86]=16'h9000; bs[ 87]=16'h0004;
      bs[ 88]=16'h00D2; bs[ 89]=16'h0000; bs[ 90]=16'h0000; bs[ 91]=16'h0000;
      bs[ 92]=16'h0000; bs[ 93]=16'h0000; bs[ 94]=16'h0000; bs[ 95]=16'h0000;
      bs[ 96]=16'h0000; bs[ 97]=16'h0000; bs[ 98]=16'h0000; bs[ 99]=16'h0000;
      bs[100]=16'h0000; bs[101]=16'h0003; bs[102]=16'h0000; bs[103]=16'h4000;
      bs[104]=16'h0003; bs[105]=16'h0000; bs[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h0000, bs);
      env.sb.expect_bitstream(bs);
      env.sb.expect_bsfetch(16'h0000);
    end

    // --- load_mul_array_b bitstream at bsfetch[0x006B] ---
    // Identical to load_mul_array_a except word[9]: D42D→D62D (base CSR 0→1)
    begin
      logic [15:0] bs [107];
      bs[  0]=16'h0000; bs[  1]=16'h0000; bs[  2]=16'h2298; bs[  3]=16'h0000;
      bs[  4]=16'h0000; bs[  5]=16'h0000; bs[  6]=16'h0000; bs[  7]=16'h3C80;
      bs[  8]=16'hE800; bs[  9]=16'hD62D; bs[ 10]=16'h0002; bs[ 11]=16'h0000;
      bs[ 12]=16'h0000; bs[ 13]=16'h0000; bs[ 14]=16'h0000; bs[ 15]=16'h0000;
      bs[ 16]=16'h0000; bs[ 17]=16'h0000; bs[ 18]=16'h0000; bs[ 19]=16'h0280;
      bs[ 20]=16'h0020; bs[ 21]=16'h0000; bs[ 22]=16'h0000; bs[ 23]=16'h0080;
      bs[ 24]=16'h0000; bs[ 25]=16'h4000; bs[ 26]=16'h0068; bs[ 27]=16'h0000;
      bs[ 28]=16'h0000; bs[ 29]=16'h0000; bs[ 30]=16'h0000; bs[ 31]=16'h0200;
      bs[ 32]=16'h0000; bs[ 33]=16'h0000; bs[ 34]=16'h0000; bs[ 35]=16'h0000;
      bs[ 36]=16'h0900; bs[ 37]=16'h0000; bs[ 38]=16'h0000; bs[ 39]=16'h0000;
      bs[ 40]=16'h0200; bs[ 41]=16'h0000; bs[ 42]=16'h0800; bs[ 43]=16'h0800;
      bs[ 44]=16'h0000; bs[ 45]=16'h0000; bs[ 46]=16'h0681; bs[ 47]=16'h0000;
      bs[ 48]=16'h4400; bs[ 49]=16'h0011; bs[ 50]=16'h0448; bs[ 51]=16'h0010;
      bs[ 52]=16'h0000; bs[ 53]=16'h0000; bs[ 54]=16'h070C; bs[ 55]=16'h0000;
      bs[ 56]=16'h0000; bs[ 57]=16'h0340; bs[ 58]=16'h0000; bs[ 59]=16'h0000;
      bs[ 60]=16'h0000; bs[ 61]=16'h0004; bs[ 62]=16'h0000; bs[ 63]=16'h0000;
      bs[ 64]=16'h0004; bs[ 65]=16'h0000; bs[ 66]=16'h0000; bs[ 67]=16'h0000;
      bs[ 68]=16'h0000; bs[ 69]=16'h0000; bs[ 70]=16'h0000; bs[ 71]=16'h0000;
      bs[ 72]=16'h0000; bs[ 73]=16'h0000; bs[ 74]=16'h0006; bs[ 75]=16'h0000;
      bs[ 76]=16'h0000; bs[ 77]=16'h0006; bs[ 78]=16'h0002; bs[ 79]=16'h0000;
      bs[ 80]=16'h0000; bs[ 81]=16'h000A; bs[ 82]=16'h0000; bs[ 83]=16'h0000;
      bs[ 84]=16'h0040; bs[ 85]=16'h0000; bs[ 86]=16'h9000; bs[ 87]=16'h0004;
      bs[ 88]=16'h00D2; bs[ 89]=16'h0000; bs[ 90]=16'h0000; bs[ 91]=16'h0000;
      bs[ 92]=16'h0000; bs[ 93]=16'h0000; bs[ 94]=16'h0000; bs[ 95]=16'h0000;
      bs[ 96]=16'h0000; bs[ 97]=16'h0000; bs[ 98]=16'h0000; bs[ 99]=16'h0000;
      bs[100]=16'h0000; bs[101]=16'h0003; bs[102]=16'h0000; bs[103]=16'h4000;
      bs[104]=16'h0003; bs[105]=16'h0000; bs[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h006B, bs);
      env.sb.expect_bitstream(bs);
      env.sb.expect_bsfetch(16'h006B);
    end

    // --- mul_array bitstream at bsfetch[0x00D6] ---
    begin
      logic [15:0] bs [107];
      bs[  0]=16'h0000; bs[  1]=16'h0000; bs[  2]=16'h0000; bs[  3]=16'h0000;
      bs[  4]=16'h0000; bs[  5]=16'h0000; bs[  6]=16'hB864; bs[  7]=16'h4671;
      bs[  8]=16'h0009; bs[  9]=16'h4118; bs[ 10]=16'h0040; bs[ 11]=16'h0400;
      bs[ 12]=16'h0000; bs[ 13]=16'h0040; bs[ 14]=16'h0A00; bs[ 15]=16'h0000;
      bs[ 16]=16'h0000; bs[ 17]=16'h0100; bs[ 18]=16'h0000; bs[ 19]=16'h0000;
      bs[ 20]=16'h0000; bs[ 21]=16'h0000; bs[ 22]=16'h0000; bs[ 23]=16'h0000;
      bs[ 24]=16'h0000; bs[ 25]=16'h0000; bs[ 26]=16'h0000; bs[ 27]=16'h0000;
      bs[ 28]=16'h6100; bs[ 29]=16'h0003; bs[ 30]=16'h0400; bs[ 31]=16'h4000;
      bs[ 32]=16'h0000; bs[ 33]=16'h0400; bs[ 34]=16'hA000; bs[ 35]=16'h0000;
      bs[ 36]=16'h0000; bs[ 37]=16'h1004; bs[ 38]=16'h0000; bs[ 39]=16'h0000;
      bs[ 40]=16'h4000; bs[ 41]=16'h0000; bs[ 42]=16'h0000; bs[ 43]=16'h4000;
      bs[ 44]=16'h0000; bs[ 45]=16'h0000; bs[ 46]=16'h0000; bs[ 47]=16'h0000;
      bs[ 48]=16'h1000; bs[ 49]=16'h0036; bs[ 50]=16'h4000; bs[ 51]=16'h0000;
      bs[ 52]=16'h0004; bs[ 53]=16'h4000; bs[ 54]=16'h0000; bs[ 55]=16'h000A;
      bs[ 56]=16'h0000; bs[ 57]=16'h0040; bs[ 58]=16'h0001; bs[ 59]=16'h0000;
      bs[ 60]=16'h0000; bs[ 61]=16'h0004; bs[ 62]=16'h0000; bs[ 63]=16'h0000;
      bs[ 64]=16'h0004; bs[ 65]=16'h0000; bs[ 66]=16'h0000; bs[ 67]=16'h0000;
      bs[ 68]=16'h0000; bs[ 69]=16'h0361; bs[ 70]=16'h0000; bs[ 71]=16'h0004;
      bs[ 72]=16'h0040; bs[ 73]=16'h0000; bs[ 74]=16'h0004; bs[ 75]=16'h00A0;
      bs[ 76]=16'h0000; bs[ 77]=16'h0400; bs[ 78]=16'h0010; bs[ 79]=16'h0000;
      bs[ 80]=16'h0000; bs[ 81]=16'h0040; bs[ 82]=16'h0000; bs[ 83]=16'h0000;
      bs[ 84]=16'h0040; bs[ 85]=16'h0000; bs[ 86]=16'h0000; bs[ 87]=16'h0000;
      bs[ 88]=16'h0000; bs[ 89]=16'h3610; bs[ 90]=16'h0000; bs[ 91]=16'h0000;
      bs[ 92]=16'h0000; bs[ 93]=16'h0000; bs[ 94]=16'h0000; bs[ 95]=16'h0000;
      bs[ 96]=16'h0000; bs[ 97]=16'h4000; bs[ 98]=16'h0000; bs[ 99]=16'h0000;
      bs[100]=16'h0000; bs[101]=16'h0400; bs[102]=16'h0000; bs[103]=16'h0000;
      bs[104]=16'h0400; bs[105]=16'h0000; bs[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h00D6, bs);
      env.sb.expect_bitstream(bs);
      env.sb.expect_bsfetch(16'h00D6);
    end

    // --- compute_store_addrs bitstream at bsfetch[0x0141] ---
    begin
      logic [15:0] bs [107];
      bs[  0]=16'h0000; bs[  1]=16'h0000; bs[  2]=16'h0000; bs[  3]=16'h0000;
      bs[  4]=16'h0000; bs[  5]=16'h2308; bs[  6]=16'h0000; bs[  7]=16'h3C80;
      bs[  8]=16'hE800; bs[  9]=16'hD52D; bs[ 10]=16'h0002; bs[ 11]=16'h0000;
      bs[ 12]=16'h0000; bs[ 13]=16'h0000; bs[ 14]=16'h0000; bs[ 15]=16'h0000;
      bs[ 16]=16'h0000; bs[ 17]=16'h0000; bs[ 18]=16'h0000; bs[ 19]=16'h0000;
      bs[ 20]=16'h0020; bs[ 21]=16'h0000; bs[ 22]=16'h0010; bs[ 23]=16'h0080;
      bs[ 24]=16'h0000; bs[ 25]=16'h1000; bs[ 26]=16'h0068; bs[ 27]=16'h0000;
      bs[ 28]=16'h0000; bs[ 29]=16'h0000; bs[ 30]=16'h0000; bs[ 31]=16'h0200;
      bs[ 32]=16'h0000; bs[ 33]=16'h0000; bs[ 34]=16'h0000; bs[ 35]=16'h0000;
      bs[ 36]=16'h0800; bs[ 37]=16'h0000; bs[ 38]=16'h0000; bs[ 39]=16'h0000;
      bs[ 40]=16'h0000; bs[ 41]=16'h0000; bs[ 42]=16'h0100; bs[ 43]=16'h0800;
      bs[ 44]=16'h0000; bs[ 45]=16'h0000; bs[ 46]=16'h0681; bs[ 47]=16'h0000;
      bs[ 48]=16'h4400; bs[ 49]=16'h0010; bs[ 50]=16'h0448; bs[ 51]=16'h0010;
      bs[ 52]=16'h0000; bs[ 53]=16'h0000; bs[ 54]=16'h000C; bs[ 55]=16'h0000;
      bs[ 56]=16'h3000; bs[ 57]=16'h0340; bs[ 58]=16'h0000; bs[ 59]=16'h0000;
      bs[ 60]=16'h0002; bs[ 61]=16'h0004; bs[ 62]=16'h0000; bs[ 63]=16'h0000;
      bs[ 64]=16'h0004; bs[ 65]=16'h0000; bs[ 66]=16'h0000; bs[ 67]=16'h0000;
      bs[ 68]=16'h0000; bs[ 69]=16'h0000; bs[ 70]=16'h0000; bs[ 71]=16'h0000;
      bs[ 72]=16'h0000; bs[ 73]=16'h0000; bs[ 74]=16'h0000; bs[ 75]=16'h0000;
      bs[ 76]=16'h0000; bs[ 77]=16'h0006; bs[ 78]=16'h0003; bs[ 79]=16'h0000;
      bs[ 80]=16'h0001; bs[ 81]=16'h000A; bs[ 82]=16'h0000; bs[ 83]=16'h0004;
      bs[ 84]=16'h0040; bs[ 85]=16'h0000; bs[ 86]=16'h9000; bs[ 87]=16'h2004;
      bs[ 88]=16'h00D0; bs[ 89]=16'h0000; bs[ 90]=16'h0000; bs[ 91]=16'h0000;
      bs[ 92]=16'h0000; bs[ 93]=16'h0000; bs[ 94]=16'h0000; bs[ 95]=16'h0000;
      bs[ 96]=16'h0000; bs[ 97]=16'h0000; bs[ 98]=16'h0000; bs[ 99]=16'h0000;
      bs[100]=16'h0000; bs[101]=16'h0000; bs[102]=16'h0000; bs[103]=16'h4030;
      bs[104]=16'h0000; bs[105]=16'h0000; bs[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h0141, bs);
      env.sb.expect_bitstream(bs);
      env.sb.expect_bsfetch(16'h0141);
    end

    // --- store_mul_array bitstream at bsfetch[0x01AC] ---
    begin
      logic [15:0] bs [107];
      bs[  0]=16'h0000; bs[  1]=16'h1308; bs[  2]=16'h479A; bs[  3]=16'h0002;
      bs[  4]=16'h0000; bs[  5]=16'h0000; bs[  6]=16'h0000; bs[  7]=16'hCE00;
      bs[  8]=16'h0128; bs[  9]=16'h4118; bs[ 10]=16'h0000; bs[ 11]=16'h0000;
      bs[ 12]=16'h0000; bs[ 13]=16'h0000; bs[ 14]=16'h0000; bs[ 15]=16'h0000;
      bs[ 16]=16'h0000; bs[ 17]=16'h0000; bs[ 18]=16'h0000; bs[ 19]=16'h0000;
      bs[ 20]=16'h0000; bs[ 21]=16'h0000; bs[ 22]=16'h0000; bs[ 23]=16'h0000;
      bs[ 24]=16'h0000; bs[ 25]=16'h0000; bs[ 26]=16'h0000; bs[ 27]=16'h0000;
      bs[ 28]=16'h0000; bs[ 29]=16'h0000; bs[ 30]=16'h0400; bs[ 31]=16'h0000;
      bs[ 32]=16'h0000; bs[ 33]=16'h0400; bs[ 34]=16'h0000; bs[ 35]=16'h0000;
      bs[ 36]=16'h0400; bs[ 37]=16'h0000; bs[ 38]=16'h0000; bs[ 39]=16'h2000;
      bs[ 40]=16'h0020; bs[ 41]=16'h0000; bs[ 42]=16'h0000; bs[ 43]=16'h4000;
      bs[ 44]=16'h0000; bs[ 45]=16'h0000; bs[ 46]=16'h0000; bs[ 47]=16'h0000;
      bs[ 48]=16'h0000; bs[ 49]=16'h0000; bs[ 50]=16'h4000; bs[ 51]=16'h0000;
      bs[ 52]=16'h0000; bs[ 53]=16'h4000; bs[ 54]=16'h0000; bs[ 55]=16'h0000;
      bs[ 56]=16'h0000; bs[ 57]=16'h0202; bs[ 58]=16'h0000; bs[ 59]=16'h0000;
      bs[ 60]=16'h0600; bs[ 61]=16'h0004; bs[ 62]=16'h0000; bs[ 63]=16'h0000;
      bs[ 64]=16'h0004; bs[ 65]=16'h0000; bs[ 66]=16'h0000; bs[ 67]=16'h0000;
      bs[ 68]=16'h0000; bs[ 69]=16'h0000; bs[ 70]=16'h0000; bs[ 71]=16'h0004;
      bs[ 72]=16'h0000; bs[ 73]=16'h0000; bs[ 74]=16'h2020; bs[ 75]=16'h0000;
      bs[ 76]=16'h0000; bs[ 77]=16'h6000; bs[ 78]=16'h0040; bs[ 79]=16'h0000;
      bs[ 80]=16'h6000; bs[ 81]=16'h0040; bs[ 82]=16'h0000; bs[ 83]=16'h0000;
      bs[ 84]=16'h0040; bs[ 85]=16'h0000; bs[ 86]=16'h0000; bs[ 87]=16'h0000;
      bs[ 88]=16'h0000; bs[ 89]=16'h0000; bs[ 90]=16'h0000; bs[ 91]=16'h0200;
      bs[ 92]=16'h0002; bs[ 93]=16'h0000; bs[ 94]=16'h0000; bs[ 95]=16'h0406;
      bs[ 96]=16'h0000; bs[ 97]=16'h0000; bs[ 98]=16'h0406; bs[ 99]=16'h0000;
      bs[100]=16'h0000; bs[101]=16'h0406; bs[102]=16'h0000; bs[103]=16'h0000;
      bs[104]=16'h0400; bs[105]=16'h0000; bs[106]=16'h0000;
      env.bsfetch_agnt.load_mem(16'h01AC, bs);
      env.sb.expect_bitstream(bs);
      env.sb.expect_bsfetch(16'h01AC);
    end

    // -----------------------------------------------------------------------
    // 3. Pre-populate AXI-Lite read memory with input data.
    //
    //    Due to balanced routing (dst_col = 8 - 2*lane), load responses arrive
    //    in reverse lane order at the CGRA north boundary.  The bitstream
    //    programs ld_dest_regs to absorb this reversal so that:
    //      - AXI port 0 (col 2, lane 3 addr) → GPR[0]
    //      - AXI port 3 (col 8, lane 0 addr) → GPR[3]
    //    Therefore: mem[csrX0+k] = A[k] maps A[k] to GPR[3-k] after the load.
    //
    //    A=[2,3,4,5] at 0x0100..0x0103 → GPR[3,2,1,0] = [2,3,4,5]
    //    B=[3,4,5,6] at 0x0200..0x0203 → GPR[7,6,5,4] = [3,4,5,6]
    //
    //    After mul_array: GPR[k] = GPR[k]*GPR[k+4]:
    //      GPR[0]=5*6=30, GPR[1]=4*5=20, GPR[2]=3*4=12, GPR[3]=2*3=6
    //
    //    compute_store_addrs also reverses: GPR[4]=C[3]=0x0303,GPR[7]=C[0]=0x0300.
    //    store_mul_array stores GPR[k] at GPR[k+4]:
    //      (0x0300,GPR[3]=6)..wait, port3→GPR[0]=30 at GPR[7]=0x0300.
    //    Final: (0x0300,30),(0x0301,20),(0x0302,12),(0x0303,6)
    // -----------------------------------------------------------------------
    setup_thread_inputs_and_expectations();

    // -----------------------------------------------------------------------
    // 6. Dispatch single CTA at pc=0x0000, wait for completion.
    // -----------------------------------------------------------------------
    seq = cta_single_seq::type_id::create("seq");
    seq.start(env.cta_agnt.seqr);
    `uvm_info("FULL_MUL", $sformatf("CTA dispatched: %s", seq.item.convert2string()), UVM_NONE)

    fork
      begin : wait_complete
        @(posedge env.cta_agnt.mon.vif.cta_complete_valid);
        `uvm_info("FULL_MUL", "cta_complete_valid asserted", UVM_NONE)
        disable wait_timeout;
      end
      begin : wait_timeout
        repeat (TIMEOUT_CYCLES) @(posedge env.cta_agnt.mon.vif.clk);
        `uvm_fatal("FULL_MUL", $sformatf("Timeout after %0d cycles", TIMEOUT_CYCLES))
        disable wait_complete;
      end
    join_any

    #100;
  endtask

endclass
