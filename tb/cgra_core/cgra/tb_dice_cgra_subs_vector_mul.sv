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

module tb_dice_cgra_subs_vector_mul;
  import dice_pkg::*;
  import cgra_test_pkg::*;

  localparam time CLK_PERIOD = 20000;

  localparam int RESET_CYCLES      = 10;
  localparam int POST_RESET_CYCLES = 10;
  localparam int FUNCTIONAL_SETTLE = 15;
  localparam int PROGRAM_SETTLE    = 16;
  localparam int NUM_RANDOM_CASES  = 50;
  localparam int unsigned RANDOM_SEED = 'hD1CE;
  localparam int TIMEOUT_CYCLES    = 30000;
  localparam int CHUNK_COUNT       = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                     / DICE_MEM_DATA_WIDTH;
  localparam int WORDS_PER_CHUNK   = DICE_MEM_DATA_WIDTH / 32;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/homes/jami3jun/ee477/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

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

  logic [15:0] ext_data_i [0:15];
  logic [15:0] ext_data_o [0:15];
  logic        ext_pred_i [0:1];
  logic        ext_pred_o [0:1];
  logic [15:0] mem_data_o_0;
  logic [15:0] mem_addr_o_0;
  logic [15:0] mem_data_o_1;
  logic [15:0] mem_addr_o_1;
  logic [15:0] mem_data_o_2;
  logic [15:0] mem_addr_o_2;
  logic [15:0] mem_data_o_3;
  logic [15:0] mem_addr_o_3;

  integer cycle_count;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_cgra_subs_vector_mul, "+struct", "+mda");
  end

  dice_cgra_subs dut (
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
      .ext_data_i_0(ext_data_i[0]),
      .ext_data_i_1(ext_data_i[1]),
      .ext_data_i_2(ext_data_i[2]),
      .ext_data_i_3(ext_data_i[3]),
      .ext_data_i_4(ext_data_i[4]),
      .ext_data_i_5(ext_data_i[5]),
      .ext_data_i_6(ext_data_i[6]),
      .ext_data_i_7(ext_data_i[7]),
      .ext_data_i_8(ext_data_i[8]),
      .ext_data_i_9(ext_data_i[9]),
      .ext_data_i_10(ext_data_i[10]),
      .ext_data_i_11(ext_data_i[11]),
      .ext_data_i_12(ext_data_i[12]),
      .ext_data_i_13(ext_data_i[13]),
      .ext_data_i_14(ext_data_i[14]),
      .ext_data_i_15(ext_data_i[15]),
      .ext_data_o_0(ext_data_o[0]),
      .ext_data_o_1(ext_data_o[1]),
      .ext_data_o_2(ext_data_o[2]),
      .ext_data_o_3(ext_data_o[3]),
      .ext_data_o_4(ext_data_o[4]),
      .ext_data_o_5(ext_data_o[5]),
      .ext_data_o_6(ext_data_o[6]),
      .ext_data_o_7(ext_data_o[7]),
      .ext_data_o_8(ext_data_o[8]),
      .ext_data_o_9(ext_data_o[9]),
      .ext_data_o_10(ext_data_o[10]),
      .ext_data_o_11(ext_data_o[11]),
      .ext_data_o_12(ext_data_o[12]),
      .ext_data_o_13(ext_data_o[13]),
      .ext_data_o_14(ext_data_o[14]),
      .ext_data_o_15(ext_data_o[15]),
      .ext_pred_i_0(ext_pred_i[0]),
      .ext_pred_i_1(ext_pred_i[1]),
      .ext_pred_o_0(ext_pred_o[0]),
      .ext_pred_o_1(ext_pred_o[1]),
      .mem_data_o_0(mem_data_o_0),
      .mem_addr_o_0(mem_addr_o_0),
      .mem_data_o_1(mem_data_o_1),
      .mem_addr_o_1(mem_addr_o_1),
      .mem_data_o_2(mem_data_o_2),
      .mem_addr_o_2(mem_addr_o_2),
      .mem_data_o_3(mem_data_o_3),
      .mem_addr_o_3(mem_addr_o_3)
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

  task automatic clear_chunk_stream_inputs();
    begin
      cm0_data_i     = '0;
      cm0_chunk_en_i = '0;
      cm1_data_i     = '0;
      cm1_chunk_en_i = '0;
      v_i            = 1'b0;
      bank_i         = 1'b0;
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
    logic [CHUNK_COUNT-1:0] chunk_mask;
    int unsigned chunk_idx;
    begin
      $display("[TB] Streaming bitstream into bank %0d", target_bank);
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
        clear_chunk_stream_inputs();
      end

      repeat (2) @(posedge clk_i);
      if (bank_valid_o[target_bank] !== 1'b1) begin
        $fatal(1, "Bank %0d did not become valid after chunk streaming", target_bank);
      end
    end
  endtask

  task automatic program_bank(input logic target_bank);
    begin
      $display("[TB] Programming CGRA from resident bank %0d", target_bank);
      $display("[TB] program_bank(%0d) at time %0t", target_bank, $time);
      bank_i = target_bank;
      wait (ready_o === 1'b1);

      @(negedge clk_i);
      v_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      v_i = 1'b0;

      wait (busy_o === 1'b1);
      wait (busy_o === 1'b0);
      repeat (PROGRAM_SETTLE) @(posedge clk_i);
    end
  endtask

  task automatic reset_dut();
    begin
      reset_i = 1'b1;
      en_i    = 1'b1;
      clear_chunk_stream_inputs();
      drive_boundary_to_zero(ext_data_i, ext_pred_i);

      repeat (RESET_CYCLES) @(posedge clk_i);
      @(negedge clk_i);
      reset_i = 1'b0;
      repeat (POST_RESET_CYCLES) @(posedge clk_i);
    end
  endtask

  task automatic test_mul_array_directed_functionality();
    logic [15:0] a_values [0:3];
    logic [15:0] b_values [0:3];
    logic [15:0] expected_values [0:3];
    begin
      $display("[TB] Running directed vector-multiply test");
      load_directed_case(a_values, b_values, expected_values);
      apply_mul_array_inputs(ext_data_i, ext_pred_i, a_values, b_values);
      repeat (FUNCTIONAL_SETTLE) @(posedge clk_i);
      check_mul_outputs("directed", ext_data_o, a_values, b_values, expected_values);
      $display("[TB] Directed test passed");
    end
  endtask

  task automatic test_mul_array_randomized();
    logic [15:0] a_values [0:3];
    logic [15:0] b_values [0:3];
    logic [15:0] expected_values [0:3];
    int case_idx;
    begin
      $display("[TB] Running randomized vector-multiply test");
      dice_vector_mul_golden_init(RANDOM_SEED);

      for (case_idx = 0; case_idx < NUM_RANDOM_CASES; case_idx++) begin
        load_random_case(a_values, b_values, expected_values);
        apply_mul_array_inputs(ext_data_i, ext_pred_i, a_values, b_values);
        repeat (FUNCTIONAL_SETTLE) @(posedge clk_i);
        check_mul_outputs($sformatf("randomized case %0d", case_idx),
                          ext_data_o, a_values, b_values, expected_values);
      end

      $display("[TB] Randomized test passed (%0d cases)", NUM_RANDOM_CASES);
    end
  endtask

  initial begin
    string bitstream_file;

    bitstream_file = DEFAULT_BITSTREAM_FILE;
    void'($value$plusargs("bitstream_bin=%s", bitstream_file));

    reset_dut();
    dice_vector_mul_bitstream_init(bitstream_file);

    stream_bitstream_to_bank(1'b0);
    stream_bitstream_to_bank(1'b1);

    if (bank_valid_o !== 2'b11) begin
      $fatal(1, "Expected both banks valid after load, got %b", bank_valid_o);
    end

    drive_boundary_to_zero(ext_data_i, ext_pred_i);
    en_i = 1'b1;

    program_bank(1'b0);
    repeat (FUNCTIONAL_SETTLE) @(posedge clk_i);
    test_mul_array_directed_functionality();

    drive_boundary_to_zero(ext_data_i, ext_pred_i);
    program_bank(1'b1);
    repeat (FUNCTIONAL_SETTLE) @(posedge clk_i);
    test_mul_array_randomized();

    $display("[TB] PASS: dice_cgra_subs vector-multiply test completed");
    $finish;
  end

endmodule
