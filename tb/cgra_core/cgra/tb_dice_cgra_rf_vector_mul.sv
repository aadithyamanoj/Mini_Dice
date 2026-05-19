`define DICE_RF_DEBUG
`timescale 1ns/1ps
import "DPI-C" context function void dice_vector_mul_bitstream_init(
    input string bitstream_file
);
import "DPI-C" context function void dice_vector_mul_bitstream_get_chunk(
    input int unsigned chunk_idx,
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

module tb_dice_cgra_rf_vector_mul;
  import dice_pkg::*;
  import DE_pkg::*;
  import cgra_test_pkg::*;

  localparam time CLK_PERIOD = 20000;
  localparam int RESET_CYCLES      = 10;
  localparam int POST_RESET_CYCLES = 10;
  localparam int TIMEOUT_CYCLES    = 30000;
  localparam int CHUNK_COUNT       = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                     / DICE_MEM_DATA_WIDTH;
  localparam int WORDS_PER_CHUNK   = DICE_MEM_DATA_WIDTH / 32;
  localparam int RF_WRITE_SETTLE   = 3;
  localparam int CGRA_LATENCY      = 7;
  localparam int WRITEBACK_SETTLE  = 3;
  localparam int NUM_TEST_THREADS  = DICE_NUM_MAX_THREADS_PER_CORE;
  localparam int NUM_SRC_BANKS     = 8;
  localparam int NUM_DST_BANKS     = 4;
  localparam bit ENABLE_WB_TRACE   = 1'b0;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/homes/enorman/ee477/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

  logic clk_i;
  logic reset_i;
  logic en_i;

  logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i;
  logic [CHUNK_COUNT-1:0]         cm0_chunk_en_i;
  logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i;
  logic [CHUNK_COUNT-1:0]         cm1_chunk_en_i;
  logic                           v_i;
  logic                           bank_i;
  logic                           ready_o;
  logic                           busy_o;
  logic [1:0]                     bank_valid_o;
  logic                           prog_dout_o;
  logic                           prog_we_o;
  logic [7:0]                     latency_i;

  logic                           rd_tid_valid_i;
  logic                           rd_tid_ready_o;
  // logic                           rd_en_i;
  logic [DICE_TID_WIDTH-1:0]      rd_tid_i;
  logic [DICE_TOTAL_REGS-1:0]     rd_bitmap_i;
  logic [DICE_TOTAL_REGS-1:0]     wr_bitmap_i;
  logic                           rf_rd_valid_o;

  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i;
  logic                           ldst_valid_i;
  logic                           ldst_ready_o;

  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_data_o_0;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_addr_o_0;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_data_o_1;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_addr_o_1;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_data_o_2;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_addr_o_2;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_data_o_3;
  logic [DICE_REG_DATA_WIDTH-1:0]                                      mem_addr_o_3;
  logic                                                                mem_valid_o;

`ifdef DICE_RF_DEBUG
  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0]      dbg_rf_rd_data;
  logic [DICE_NUM_PRED-1:0]                                            dbg_pred;
  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0]      dbg_rf_launch_data;
  logic [DICE_NUM_PRED-1:0]                                            dbg_pred_launch;
  logic [((DICE_NUM_BANKS+DICE_NUM_PRED+1)*DICE_REG_DATA_WIDTH)-1:0]   dbg_cgra_data;
  logic [DICE_TOTAL_REGS-1:0]                                          dbg_cgra_wr_bitmap;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                    dbg_cgra_tid;
  logic                                                                dbg_cgra_valid;
  logic                                                                dbg_rf_rd_valid;
`endif

  integer cycle_count;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_cgra_rf_vector_mul, "+struct", "+mda");
  end

  dice_cgra_rf dut (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .en_i(en_i),
      .cm0_data_i(cm0_data_i),
      .cm0_chunk_en_i(cm0_chunk_en_i),
      .cm1_data_i(cm1_data_i),
      .cm1_chunk_en_i(cm1_chunk_en_i),
      .v_i(v_i),
      .bank_i(bank_i),
      .ready_o(ready_o),
      .busy_o(busy_o),
      .bank_valid_o(bank_valid_o),
      .prog_dout_o(prog_dout_o),
      .prog_we_o(prog_we_o),
      .latency_i(latency_i),
      .rd_tid_valid_i(rd_tid_valid_i),
      .rd_tid_ready_o(rd_tid_ready_o),
      // .rd_en_i(rd_en_i),
      .rd_tid_i(rd_tid_i),
      .rd_bitmap_i(rd_bitmap_i),
      .wr_bitmap_i(wr_bitmap_i),
      .rf_rd_valid_o(rf_rd_valid_o),
      .ldst_wr_i(ldst_wr_i),
      .ldst_valid_i(ldst_valid_i),
      .ldst_ready_o(ldst_ready_o),
      .mem_data_o_0(mem_data_o_0),
      .mem_addr_o_0(mem_addr_o_0),
      .mem_data_o_1(mem_data_o_1),
      .mem_addr_o_1(mem_addr_o_1),
      .mem_data_o_2(mem_data_o_2),
      .mem_addr_o_2(mem_addr_o_2),
      .mem_data_o_3(mem_data_o_3),
      .mem_addr_o_3(mem_addr_o_3),
      .mem_valid_o(mem_valid_o)
`ifdef DICE_RF_DEBUG
      , .dbg_rf_rd_data_o(dbg_rf_rd_data)
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
      $display("[WB] cyc=%0d wb_tid=%0d wr_bitmap=%b d0=%0d d1=%0d d2=%0d d3=%0d",
               cycle_count,
               dbg_cgra_tid,
               dbg_cgra_wr_bitmap[NUM_DST_BANKS-1:0],
               dbg_cgra_data[0*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[1*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[2*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH],
               dbg_cgra_data[3*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
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
      rd_tid_valid_i = 1'b0;
      // rd_en_i        = 1'b0;
      rd_tid_i       = '0;
      rd_bitmap_i    = '0;
      wr_bitmap_i    = '0;
      ldst_wr_i      = '0;
      ldst_valid_i   = 1'b0;
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

  task automatic get_bitstream_chunk(
      input int unsigned chunk_idx,
      output logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data
  );
    int unsigned w [0:WORDS_PER_CHUNK-1];
    int word_idx;
    begin
      dice_vector_mul_bitstream_get_chunk(
          chunk_idx,
          w[0],  w[1],  w[2],  w[3],
          w[4],  w[5],  w[6],  w[7],
          w[8],  w[9],  w[10], w[11],
          w[12], w[13], w[14], w[15]
      );

      chunk_data = '0;
      for (word_idx = 0; word_idx < WORDS_PER_CHUNK; word_idx++) begin
        chunk_data[word_idx*32 +: 32] = w[word_idx];
      end
    end
  endtask

  task automatic stream_bitstream_to_bank(input logic target_bank);
    logic [DICE_MEM_DATA_WIDTH-1:0] chunk_data;
    logic [CHUNK_COUNT-1:0]         chunk_mask;
    int unsigned chunk_idx;
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

  function automatic logic [$bits(cache_wr_cmd)-1:0] build_ldst_write(
      input logic [DICE_TID_WIDTH-1:0]  tid,
      input int                         reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0] data
  );
    cache_wr_cmd cmd;
    begin
      cmd = '0;
      cmd.tid = tid;
      cmd.data = data;
      cmd.wr_bitmap[reg_idx] = 1'b1;
      return cmd;
    end
  endfunction

  task automatic send_ldst_write(
      input logic [DICE_TID_WIDTH-1:0]  tid,
      input int                         reg_idx,
      input logic [DICE_REG_DATA_WIDTH-1:0] data
  );
    begin
      wait (ldst_ready_o === 1'b1);
      @(negedge clk_i);
      ldst_wr_i = build_ldst_write(tid, reg_idx, data);
      ldst_valid_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      ldst_valid_i = 1'b0;
      ldst_wr_i = '0;
    end
  endtask

  task automatic issue_rf_read(
      input logic [DICE_TID_WIDTH-1:0]  tid,
      input logic [DICE_TOTAL_REGS-1:0] rd_bitmap,
      input logic [DICE_TOTAL_REGS-1:0] wr_bitmap
  );
    begin
      @(negedge clk_i);
      rd_tid_i       = tid;
      rd_bitmap_i    = rd_bitmap;
      wr_bitmap_i    = wr_bitmap;
      rd_tid_valid_i = 1'b1;
      // rd_en_i        = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      rd_tid_valid_i = 1'b0;
      // rd_en_i        = 1'b0;
    end
  endtask

  task automatic check_rf_read_data(
      input string test_name,
      input logic [7:0] expected[],
      input int count
  );
    logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] sampled_rd_data;
    begin
`ifdef DICE_RF_DEBUG
      @(posedge clk_i iff (dbg_rf_rd_valid === 1'b1));
      sampled_rd_data = dbg_rf_rd_data;
`else
      @(posedge clk_i iff (rf_rd_valid_o === 1'b1));
      sampled_rd_data = dut.rf_rd_data_lo;
`endif
      for (int i = 0; i < count; i++) begin
        if (sampled_rd_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] !== expected[i]) begin
          $fatal(1, "%s: RF read bank %0d expected %0d got %0d",
                 test_name, i, expected[i],
                 sampled_rd_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
        end
        $display("%s: RF read bank %0d matched expected %0d",
                 test_name, i,
                 sampled_rd_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]);
      end
    end
  endtask

  task automatic build_thread_case(
      input logic [DICE_TID_WIDTH-1:0] tid,
      output logic [7:0] rf_values [0:NUM_SRC_BANKS-1],
      output logic [7:0] expected_values [0:NUM_DST_BANKS-1]
  );
    begin
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        rf_values[i] = tid + i + 1;
        rf_values[i + NUM_DST_BANKS] = i + 2;
        expected_values[i] = rf_values[i] * rf_values[i + NUM_DST_BANKS];
      end
    end
  endtask

  task automatic preload_thread_registers(
      input logic [DICE_TID_WIDTH-1:0] tid,
      input logic [7:0] rf_values [0:NUM_SRC_BANKS-1]
  );
    begin
      for (int bank = 0; bank < NUM_SRC_BANKS; bank++) begin
        send_ldst_write(tid, bank, rf_values[bank]);
      end
    end
  endtask

  task automatic issue_thread_source_read(
      input logic [DICE_TID_WIDTH-1:0] tid
  );
    logic [DICE_TOTAL_REGS-1:0] src_bitmap;
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    begin
      src_bitmap = '0;
      dst_bitmap = '0;
      for (int i = 0; i < NUM_SRC_BANKS; i++) begin
        src_bitmap[i] = 1'b1;
      end
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        dst_bitmap[i] = 1'b1;
      end
      issue_rf_read(tid, src_bitmap, dst_bitmap);
    end
  endtask

  task automatic issue_source_read_burst();
    logic [DICE_TOTAL_REGS-1:0] src_bitmap;
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    begin
      src_bitmap = '0;
      dst_bitmap = '0;
      for (int i = 0; i < NUM_SRC_BANKS; i++) begin
        src_bitmap[i] = 1'b1;
      end
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        dst_bitmap[i] = 1'b1;
      end

      @(negedge clk_i);
      rd_bitmap_i    = src_bitmap;
      wr_bitmap_i    = dst_bitmap;
      rd_tid_valid_i = 1'b1;
      // rd_en_i        = 1'b1;

      for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
        rd_tid_i = tid[DICE_TID_WIDTH-1:0];
        @(posedge clk_i);
        @(negedge clk_i);
      end
      wr_bitmap_i    = '0;
      // @(posedge clk_i);
      // @(posedge clk_i);
      // @(posedge clk_i);

      rd_tid_valid_i = 1'b0;
      // rd_en_i        = 1'b0;
      rd_tid_i       = '0;
      rd_bitmap_i    = '0;
      
    end
  endtask

  task automatic issue_thread_writeback_read(
      input logic [DICE_TID_WIDTH-1:0] tid
  );
    logic [DICE_TOTAL_REGS-1:0] dst_bitmap;
    logic [DICE_TOTAL_REGS-1:0] wb_disable_bitmap;
    begin
      dst_bitmap = '0;
      wb_disable_bitmap = '0;
      for (int i = 0; i < NUM_DST_BANKS; i++) begin
        dst_bitmap[i] = 1'b1;
      end
      issue_rf_read(tid, dst_bitmap, wb_disable_bitmap);
    end
  endtask

  task automatic check_cgra_outputs(
      input logic [7:0] expected [0:3]
  );
    logic [DICE_REG_DATA_WIDTH-1:0] got;
    begin
`ifdef DICE_RF_DEBUG
      wait (dbg_cgra_valid === 1'b1);
      for (int i = 0; i < 4; i++) begin
        got = dbg_cgra_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH];
        if (^got === 1'bX) begin
          $fatal(1, "CGRA output %0d contains X/Z (%b)", i, got);
        end
        if (got !== expected[i]) begin
          $fatal(1, "CGRA output %0d expected %0d got %0d",
                 i, expected[i], got);
        end
      end
`else
      wait (dut.cgra_valid_lo === 1'b1);
      for (int i = 0; i < 4; i++) begin
        if (^dut.cgra_ext_data_o[i] === 1'bX) begin
          $fatal(1, "CGRA output %0d contains X/Z (%b)", i, dut.cgra_ext_data_o[i]);
        end
        if (dut.cgra_ext_data_o[i] !== expected[i]) begin
          $fatal(1, "CGRA output %0d expected %0d got %0d",
                 i, expected[i], dut.cgra_ext_data_o[i]);
        end
      end
`endif
    end
  endtask

  task automatic reset_dut();
    begin
      reset_i = 1'b1;
      en_i    = 1'b1;
      latency_i = CGRA_LATENCY[7:0];
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
    logic [7:0] thread_rf_input_values [0:NUM_TEST_THREADS-1][0:NUM_SRC_BANKS-1];
    logic [7:0] thread_expected_values [0:NUM_TEST_THREADS-1][0:NUM_DST_BANKS-1];

    bitstream_file = DEFAULT_BITSTREAM_FILE;
    void'($value$plusargs("bitstream_bin=%s", bitstream_file));

    dump_params();
    reset_dut();
    dice_vector_mul_bitstream_init(bitstream_file);

    stream_bitstream_to_bank(1'b0);
    stream_bitstream_to_bank(1'b1);
    program_bank(1'b0);

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      build_thread_case(
          tid[DICE_TID_WIDTH-1:0],
          thread_rf_input_values[tid],
          thread_expected_values[tid]
      );
    end

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      preload_thread_registers(tid[DICE_TID_WIDTH-1:0], thread_rf_input_values[tid]);
    end
    repeat (RF_WRITE_SETTLE) @(posedge clk_i);

    issue_source_read_burst();

    repeat (CGRA_LATENCY + WRITEBACK_SETTLE + NUM_TEST_THREADS) @(posedge clk_i);

    for (int tid = 0; tid < NUM_TEST_THREADS; tid++) begin
      issue_thread_writeback_read(tid[DICE_TID_WIDTH-1:0]);
      check_rf_read_data($sformatf("writeback read tid %0d", tid), thread_expected_values[tid], NUM_DST_BANKS);
    end

    $display("[TB] PASS: dice_cgra_rf pipelined multi-thread vector-multiply RF roundtrip test completed");
    $finish;
  end

endmodule
