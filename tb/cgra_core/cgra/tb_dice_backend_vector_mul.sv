`define DICE_RF_DEBUG
`timescale 1ns / 1ps
import "DPI-C" context function void dice_vector_mul_bitstream_init(input string bitstream_file);
import "DPI-C" context function void dice_vector_mul_bitstream_get_chunk(
  input  int unsigned chunk_idx,
  output int unsigned w0,
  output int unsigned w1,
  output int unsigned w2,
  output int unsigned w3,
  output int unsigned w4,
  output int unsigned w5,
  output int unsigned w6,
  output int unsigned w7,
  output int unsigned w8,
  output int unsigned w9,
  output int unsigned w10,
  output int unsigned w11,
  output int unsigned w12,
  output int unsigned w13,
  output int unsigned w14,
  output int unsigned w15
);

module tb_dice_backend_vector_mul;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import cgra_test_pkg::*;

  localparam time CLK_PERIOD = 20000;
  localparam int RESET_CYCLES = 10;
  localparam int POST_RESET_CYCLES = 10;
  localparam int TIMEOUT_CYCLES = 30000;
  localparam int CHUNK_COUNT       = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                     / DICE_MEM_DATA_WIDTH;
  localparam int WORDS_PER_CHUNK = DICE_MEM_DATA_WIDTH / 32;
  localparam int RF_WRITE_SETTLE = 3;
  localparam int CGRA_LATENCY = 7;
  localparam int WRITEBACK_SETTLE = 3;
  localparam int NUM_TEST_THREADS = DICE_NUM_MAX_THREADS_PER_CORE;
  localparam int NUM_SRC_BANKS = 8;
  localparam int NUM_DST_BANKS = 4;
  localparam bit ENABLE_WB_TRACE = 1'b0;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/homes/jami3jun/ee477/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

  logic clk_i;
  logic reset_i;
  logic en_i;
  fdr_if fdr_if_i ();

  logic [                  DICE_MEM_DATA_WIDTH-1:0]                          cm0_data_i;
  logic [                          CHUNK_COUNT-1:0]                          cm0_chunk_en_i;
  logic [                  DICE_MEM_DATA_WIDTH-1:0]                          cm1_data_i;
  logic [                          CHUNK_COUNT-1:0]                          cm1_chunk_en_i;
  logic                                                                      v_i;
  logic                                                                      bank_i;
  logic                                                                      ready_o;
  logic                                                                      busy_o;
  logic [                                      1:0]                          bank_valid_o;
  logic                                                                      prog_dout_o;
  logic                                                                      prog_we_o;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_data_o_0;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_addr_o_0;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_data_o_1;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_addr_o_1;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_data_o_2;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_addr_o_2;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_data_o_3;
  logic [                  DICE_REG_DATA_WIDTH-1:0]                          mem_addr_o_3;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                          mem_rsp_base_tid_i;
  logic [                     TID_BITMAP_WIDTH-1:0]                          mem_rsp_tid_bitmap_i;
  logic [                  DICE_REG_ADDR_WIDTH-1:0]                          mem_rsp_ld_dest_reg_i;
  logic [     NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] mem_rsp_address_map_i;
  logic [                  (CACHE_LINE_SIZE*8)-1:0]                          mem_rsp_data_i;
  logic                                                                      mem_rsp_valid_i;
  logic                                                                      eblock_commit_valid_o;
  logic [                 DICE_EBLOCK_ID_WIDTH-1:0]                          eblock_commit_id_o;
  logic                                                                      eblock_commit_ready_i;
  logic [              2**DICE_HW_CTA_ID_WIDTH-1:0]                          hw_cta_pending_o;

`ifdef DICE_RF_DEBUG
  logic [   (DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_rd_data;
  logic [                                         DICE_NUM_PRED-1:0] dbg_pred;
  logic [   (DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] dbg_rf_launch_data;
  logic [                                         DICE_NUM_PRED-1:0] dbg_pred_launch;
  logic [((DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH)-1:0] dbg_cgra_data;
  logic [                                       DICE_TOTAL_REGS-1:0] dbg_cgra_wr_bitmap;
  logic [                 $clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] dbg_cgra_tid;
  logic                                                              dbg_cgra_valid;
  logic                                                              dbg_rf_rd_valid;
`endif

  integer cycle_count;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_backend_vector_mul, "+struct", "+mda");
  end

  dice_backend dut (
      .clk_i(clk_i),
      .rst_i(reset_i),
      .fdr_valid_i(fdr_if_i.valid),
      .fdr_data_i(fdr_if_i.data),
      .fdr_ready_o(fdr_if_i.ready),
      .mem_rsp_base_tid_i(mem_rsp_base_tid_i),
      // .mem_rsp_tid_bitmap_i(mem_rsp_tid_bitmap_i),
      .mem_rsp_ld_dest_reg_i(mem_rsp_ld_dest_reg_i),
      // .mem_rsp_address_map_i(mem_rsp_address_map_i),
      .mem_rsp_data_i(mem_rsp_data_i),
      .mem_rsp_valid_i(mem_rsp_valid_i),
      .eblock_commit_valid_o(eblock_commit_valid_o),
      .eblock_commit_id_o(eblock_commit_id_o),
      .eblock_commit_ready_i(eblock_commit_ready_i),
      .hw_cta_pending_o(hw_cta_pending_o),
      .cgra_cm0_data_i(cm0_data_i),
      .cgra_cm0_chunk_en_i(cm0_chunk_en_i),
      .cgra_cm1_data_i(cm1_data_i),
      .cgra_cm1_chunk_en_i(cm1_chunk_en_i),
      .en_i(en_i),
      .cgra_v_i(v_i),
      .cgra_bank_i(bank_i),
      .cgra_ready_o(ready_o),
      .cgra_busy_o(busy_o),
      .cgra_bank_valid_o(bank_valid_o),
      .cgra_prog_dout_o(prog_dout_o),
      .cgra_prog_we_o(prog_we_o),
      .cgra_mem_data_o_0(mem_data_o_0),
      .cgra_mem_addr_o_0(mem_addr_o_0),
      .cgra_mem_data_o_1(mem_data_o_1),
      .cgra_mem_addr_o_1(mem_addr_o_1),
      .cgra_mem_data_o_2(mem_data_o_2),
      .cgra_mem_addr_o_2(mem_addr_o_2),
      .cgra_mem_data_o_3(mem_data_o_3),
      .cgra_mem_addr_o_3(mem_addr_o_3)
`ifdef DICE_RF_DEBUG,
      .dbg_rf_rd_data_o(dbg_rf_rd_data)
      , .dbg_pred_o(dbg_pred)
      , .dbg_rf_launch_data_o(dbg_rf_launch_data)
      , .dbg_pred_launch_o(dbg_pred_launch)
      , .dbg_cgra_data_o(dbg_cgra_data)
      , .dbg_cgra_wr_bitmap_o(dbg_cgra_wr_bitmap)
      , .dbg_cgra_tid_o(dbg_cgra_tid)
      , .dbg_cgra_valid_o(dbg_cgra_valid)
      , .dbg_rf_rd_valid_o(dbg_rf_rd_valid)
`endif
  );

  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD / 2) clk_i = ~clk_i;
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count > TIMEOUT_CYCLES) begin
        $fatal(1, "TIMEOUT after %0d cycles", TIMEOUT_CYCLES);
      end
    end
  end

`ifdef DICE_RF_DEBUG
  always_ff @(posedge clk_i) begin
    if (!reset_i && ENABLE_WB_TRACE && dbg_cgra_valid) begin
      $display("[WB] cyc=%0d wb_tid=%0d wr_bitmap=%b d0=%0d d1=%0d d2=%0d d3=%0d", cycle_count,
               dbg_cgra_tid, dbg_cgra_wr_bitmap[NUM_DST_BANKS-1:0],
               dbg_cgra_data[0*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH],
               dbg_cgra_data[1*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH],
               dbg_cgra_data[2*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH],
               dbg_cgra_data[3*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH]);
    end
  end
`endif

  task automatic clear_stream_inputs();
    begin
      cm0_data_i     = '0;
      cm0_chunk_en_i = '0;
      cm1_data_i     = '0;
      cm1_chunk_en_i = '0;
      v_i            = 1'b0;
      bank_i         = 1'b0;
    end
  endtask

  task automatic clear_rf_inputs();
    begin
      mem_rsp_base_tid_i    = '0;
      mem_rsp_tid_bitmap_i  = '0;
      mem_rsp_ld_dest_reg_i = '0;
      mem_rsp_address_map_i = '0;
      mem_rsp_data_i        = '0;
      mem_rsp_valid_i       = 1'b0;
      fdr_if_i.valid        = 1'b0;
      fdr_if_i.data         = '0;
      eblock_commit_ready_i = 1'b0;
    end
  endtask

  task automatic dump_params();
    begin
      $display("[TB] Parameters:");
      $display("[TB]   DICE_NUM_MAX_THREADS_PER_CORE = %0d", DICE_NUM_MAX_THREADS_PER_CORE);
      $display("[TB]   DICE_TID_WIDTH                = %0d", DICE_TID_WIDTH);
      $display("[TB]   DICE_NUM_BANKS                = %0d", DICE_NUM_BANKS);
      $display("[TB]   DICE_NUM_CONST                = %0d", DICE_NUM_CONST);
      $display("[TB]   DICE_NUM_PRED                 = %0d", DICE_NUM_PRED);
      $display("[TB]   DICE_TOTAL_REGS               = %0d", DICE_TOTAL_REGS);
      $display("[TB]   DICE_REG_DATA_WIDTH           = %0d", DICE_REG_DATA_WIDTH);
      $display("[TB]   DICE_MEM_DATA_WIDTH           = %0d", DICE_MEM_DATA_WIDTH);
      $display("[TB]   DICE_BITSTREAM_SIZE           = %0d", DICE_BITSTREAM_SIZE);
      $display("[TB]   CHUNK_COUNT                   = %0d", CHUNK_COUNT);
      $display("[TB]   WORDS_PER_CHUNK               = %0d", WORDS_PER_CHUNK);
      $display("[TB]   RF_WRITE_SETTLE               = %0d", RF_WRITE_SETTLE);
      $display("[TB]   CGRA_LATENCY                  = %0d", CGRA_LATENCY);
      $display("[TB]   WRITEBACK_SETTLE              = %0d", WRITEBACK_SETTLE);
      $display("[TB]   NUM_TEST_THREADS              = %0d", NUM_TEST_THREADS);
      $display("[TB]   NUM_SRC_BANKS                 = %0d", NUM_SRC_BANKS);
      $display("[TB]   NUM_DST_BANKS                 = %0d", NUM_DST_BANKS);
      $display("[TB]   DEFAULT_BITSTREAM_FILE        = %s", DEFAULT_BITSTREAM_FILE);
    end
  endtask

  task automatic get_bitstream_chunk(input int unsigned chunk_idx,
                                     output logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data);
    int unsigned w[0:WORDS_PER_CHUNK-1];
    int word_idx;
    begin
      dice_vector_mul_bitstream_get_chunk(chunk_idx, w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7],
                                          w[8], w[9], w[10], w[11], w[12], w[13], w[14], w[15]);

      chunk_data = '0;
      for (word_idx = 0; word_idx < WORDS_PER_CHUNK; word_idx++) begin
        chunk_data[word_idx*32+:32] = w[word_idx];
      end
    end
  endtask

  task automatic stream_bitstream_to_bank(input logic target_bank);
    logic        [DICE_MEM_DATA_WIDTH-1:0] chunk_data;
    logic        [        CHUNK_COUNT-1:0] chunk_mask;
    int unsigned                           chunk_idx;
    begin
      for (chunk_idx = 0; chunk_idx < CHUNK_COUNT; chunk_idx++) begin
        get_bitstream_chunk(chunk_idx, chunk_data);
        chunk_mask = '0;
        chunk_mask[chunk_idx] = 1'b1;

        @(negedge clk_i);
        if (target_bank == 1'b0) begin
          cm0_data_i     = chunk_data;
          cm0_chunk_en_i = chunk_mask;
          cm1_data_i     = '0;
          cm1_chunk_en_i = '0;
        end else begin
          cm0_data_i     = '0;
          cm0_chunk_en_i = '0;
          cm1_data_i     = chunk_data;
          cm1_chunk_en_i = chunk_mask;
        end

        @(posedge clk_i);
        @(negedge clk_i);
        clear_stream_inputs();
      end

      repeat (2) @(posedge clk_i);
      if (bank_valid_o[target_bank] !== 1'b1) begin
        $fatal(1, "Bank %0d did not become valid after chunk streaming", target_bank);
      end
    end
  endtask

  task automatic program_bank(input logic target_bank);
    begin
      bank_i = target_bank;
      wait (ready_o === 1'b1);

      @(negedge clk_i);
      v_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      v_i = 1'b0;

      wait (busy_o === 1'b1);
      wait (busy_o === 1'b0);
      repeat (CGRA_LATENCY) @(posedge clk_i);
    end
  endtask

  function automatic logic [(CACHE_LINE_SIZE*8)-1:0] build_mem_rsp_data(
      input logic [DICE_TID_WIDTH-1:0] tid, input int reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0] data);
    logic [(CACHE_LINE_SIZE*8)-1:0] rsp_data;
    begin
      rsp_data = '0;
      rsp_data[DICE_REG_DATA_WIDTH-1:0] = data;
      return rsp_data;
    end
  endfunction

  task automatic send_mem_rsp_write(input logic [DICE_TID_WIDTH-1:0] tid, input int reg_idx,
                                    input logic [DICE_REG_DATA_WIDTH-1:0] data);
    begin
      @(negedge clk_i);
      mem_rsp_base_tid_i    = tid;
      mem_rsp_tid_bitmap_i  = '0;
      mem_rsp_ld_dest_reg_i = reg_idx[DICE_REG_ADDR_WIDTH-1:0];
      mem_rsp_data_i        = build_mem_rsp_data(tid, reg_idx, data);
      mem_rsp_valid_i       = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      mem_rsp_valid_i       = 1'b0;
      mem_rsp_base_tid_i    = '0;
      mem_rsp_ld_dest_reg_i = '0;
      mem_rsp_data_i        = '0;
    end
  endtask

  task automatic issue_backend_dispatch(
      input logic [DICE_TOTAL_REGS-1:0] in_bitmap, input logic [DICE_TOTAL_REGS-1:0] out_bitmap,
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask);
    logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs;
    begin
      ld_dest_regs = '0;
      wait (fdr_if_i.ready === 1'b1);
      @(negedge clk_i);
      fdr_if_i.data                          = '0;
      fdr_if_i.data.real_active_mask         = active_mask;
      fdr_if_i.data.metadata.in_regs_bitmap  = in_bitmap;
      fdr_if_i.data.metadata.out_regs_bitmap = out_bitmap;
      fdr_if_i.data.metadata.ld_dest_regs    = ld_dest_regs;
      fdr_if_i.data.metadata.lat             = CGRA_LATENCY[7:0];
      fdr_if_i.valid                         = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      fdr_if_i.valid = 1'b0;
    end
  endtask

  task automatic check_rf_read_data(input string test_name,
                                    input logic [DICE_TID_WIDTH-1:0] expected_tid,
                                    input logic [7:0] expected[], input int count);
    logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] sampled_rd_data;
    logic [DICE_TID_WIDTH-1:0] sampled_tid;
    begin
`ifdef DICE_RF_DEBUG
      @(posedge clk_i iff (dbg_rf_rd_valid === 1'b1));
      sampled_rd_data = dbg_rf_rd_data;
      sampled_tid = dut.u_dice_cgra_rf.rf_ctrl_inst.tid_o;
`else
      @(posedge clk_i iff (dut.u_dice_cgra_rf.rf_rd_valid_o === 1'b1));
      sampled_rd_data = dut.u_dice_cgra_rf.rf_rd_data_lo;
      sampled_tid = dut.u_dice_cgra_rf.rf_ctrl_inst.tid_o;
`endif
      if (sampled_tid !== expected_tid) begin
        $fatal(1, "%s: expected tid %0d got tid %0d", test_name, expected_tid, sampled_tid);
      end
      for (int i = 0; i < count; i++) begin
        if (sampled_rd_data[i*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH] !== expected[i]) begin
          $fatal(1, "%s: RF read bank %0d expected %0d got %0d", test_name, i, expected[i],
                 sampled_rd_data[i*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH]);
        end
        $display("%s: RF read bank %0d matched expected %0d", test_name, i,
                 sampled_rd_data[i*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH]);
      end
    end
  endtask

  task automatic build_thread_case(input logic [DICE_TID_WIDTH-1:0] tid,
                                   output logic [7:0] rf_values[0:NUM_SRC_BANKS-1],
                                   output logic [7:0] expected_values[0:NUM_DST_BANKS-1]);
    begin
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        rf_values[i] = tid + i + 1;
        rf_values[i+NUM_DST_BANKS] = i + 2;
        expected_values[i] = rf_values[i] * rf_values[i+NUM_DST_BANKS];
      end
    end
  endtask

  task automatic preload_thread_registers(input logic [DICE_TID_WIDTH-1:0] tid,
                                          input logic [7:0] rf_values[0:NUM_SRC_BANKS-1]);
    begin
      for (int bank = 0; bank < NUM_SRC_BANKS; bank++) begin
        send_mem_rsp_write(tid, bank, rf_values[bank]);
      end
    end
  endtask

  task automatic issue_source_read_burst();
    logic [DICE_TOTAL_REGS-1:0] src_bitmap;
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;
    begin
      src_bitmap  = '0;
      dst_bitmap  = '0;
      active_mask = '0;
      for (int i = 0; i < NUM_SRC_BANKS; i++) begin
        src_bitmap[i] = 1'b1;
      end
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        dst_bitmap[i] = 1'b1;
      end
      for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
        active_mask[tid] = 1'b1;
      end
      issue_backend_dispatch(src_bitmap, dst_bitmap, active_mask);
    end
  endtask

  task automatic issue_thread_writeback_read(input logic [DICE_TID_WIDTH-1:0] tid);
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask;
    begin
      dst_bitmap  = '0;
      active_mask = '0;
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        dst_bitmap[i] = 1'b1;
      end
      active_mask[tid] = 1'b1;
      issue_backend_dispatch(dst_bitmap, '0, active_mask);
    end
  endtask

  task automatic check_cgra_outputs(input logic [7:0] expected[0:3]);
    logic [DICE_REG_DATA_WIDTH-1:0] got;
    begin
`ifdef DICE_RF_DEBUG
      wait (dbg_cgra_valid === 1'b1);
      for (int i = 0; i < 4; i++) begin
        got = dbg_cgra_data[i*DICE_REG_DATA_WIDTH+:DICE_REG_DATA_WIDTH];
        if (^got === 1'bX) begin
          $fatal(1, "CGRA output %0d contains X/Z (%b)", i, got);
        end
        if (got !== expected[i]) begin
          $fatal(1, "CGRA output %0d expected %0d got %0d", i, expected[i], got);
        end
      end
`else
      wait (dut.cgra_valid_lo === 1'b1);
      for (int i = 0; i < 4; i++) begin
        if (^dut.cgra_ext_data_o[i] === 1'bX) begin
          $fatal(1, "CGRA output %0d contains X/Z (%b)", i, dut.cgra_ext_data_o[i]);
        end
        if (dut.cgra_ext_data_o[i] !== expected[i]) begin
          $fatal(1, "CGRA output %0d expected %0d got %0d", i, expected[i], dut.cgra_ext_data_o[i]);
        end
      end
`endif
    end
  endtask

  task automatic reset_dut();
    begin
      reset_i = 1'b1;
      en_i    = 1'b1;
      clear_stream_inputs();
      clear_rf_inputs();
      repeat (RESET_CYCLES) @(posedge clk_i);
      @(negedge clk_i);
      reset_i = 1'b0;
      repeat (POST_RESET_CYCLES) @(posedge clk_i);
    end
  endtask

  initial begin
    string bitstream_file;
    logic [7:0] thread_rf_input_values[0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [7:0] thread_expected_values[0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];

    bitstream_file = DEFAULT_BITSTREAM_FILE;
    void'($value$plusargs("bitstream_bin=%s", bitstream_file));

    dump_params();
    reset_dut();
    dice_vector_mul_bitstream_init(bitstream_file);

    stream_bitstream_to_bank(1'b0);
    stream_bitstream_to_bank(1'b1);
    program_bank(1'b0);

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      build_thread_case(tid[DICE_TID_WIDTH-1:0], thread_rf_input_values[tid],
                        thread_expected_values[tid]);
    end

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      preload_thread_registers(tid[DICE_TID_WIDTH-1:0], thread_rf_input_values[tid]);
    end
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    issue_source_read_burst();

    repeat (CGRA_LATENCY + WRITEBACK_SETTLE + NUM_TEST_THREADS) @(posedge clk_i);

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      issue_thread_writeback_read(tid[DICE_TID_WIDTH-1:0]);
      check_rf_read_data($sformatf("writeback read tid %0d", tid), tid[DICE_TID_WIDTH-1:0],
                         thread_expected_values[tid], NUM_DST_BANKS);
    end

    $display(
        "[TB] PASS: dice_backend dispatcher-driven vector-multiply RF roundtrip test completed");
    $finish;
  end

endmodule
