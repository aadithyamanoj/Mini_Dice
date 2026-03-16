`timescale 1ns/1ps

module tb_dice_top_vector_mul;
  import cgra_test_pkg::*;

  localparam int CLK_PERIOD_NS          = 10000;
  localparam int PROG_CLK_PERIOD_NS     = 12;
  localparam int RESET_CYCLES           = 10;
  localparam int POST_RESET_CYCLES      = 10;
  localparam int FUNCTIONAL_SETTLE      = 10;
  localparam int PROG_DONE_SETTLE_PROG  = 16;
  localparam int PROG_DONE_SETTLE_FUNC  = 8;
  localparam int SCANCHAIN_DELIM_DEPTH  = 84;
  localparam int NUM_RANDOM_CASES       = 50;
  localparam int unsigned RANDOM_SEED   = 'hD1CE;
  localparam int TIMEOUT_CYCLES         = 20000;
  localparam int BITSTREAM_BYTES        = 209;
  localparam int BITSTREAM_SIZE_BITS    = 1666;

  localparam string DEFAULT_BITSTREAM_FILE =
      "/homes/amanoj3/ee477/Mini_Dice/dora/examples/devices/dice-isca/mini_dice/build/mini_dice_mul_array.bin";

  logic clk_i;
  logic reset_i;
  logic en_i;

  logic [7:0] ext_data_i [0:15];
  logic [7:0] ext_data_o [0:15];
  logic       ext_pred_i [0:1];
  logic       ext_pred_o [0:1];
  logic [7:0] mem_data_o;
  logic [7:0] mem_addr_o;

  logic prog_clk_i;
  logic prog_rst_i;
  logic prog_done_i;
  logic prog_we_i;
  logic prog_din_i;
  logic prog_dout_o;
  logic prog_we_o;

  integer cycle_count;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_top_vector_mul, "+struct", "+mda");
  end

  dice_top dut (
      .clk_i       (clk_i),
      .reset_i     (reset_i),
      .en_i        (en_i),
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
      .mem_data_o  (mem_data_o),
      .mem_addr_o  (mem_addr_o),
      .prog_clk_i  (prog_clk_i),
      .prog_rst_i  (prog_rst_i),
      .prog_done_i (prog_done_i),
      .prog_we_i   (prog_we_i),
      .prog_din_i  (prog_din_i),
      .prog_dout_o (prog_dout_o),
      .prog_we_o   (prog_we_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD_NS / 2) clk_i = ~clk_i;
  end

  // initial begin
  //   prog_clk_i = 1'b0;
  //   forever #(PROG_CLK_PERIOD_NS / 2) prog_clk_i = ~prog_clk_i;
  // end
  assign prog_clk_i = clk_i;

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

  task automatic shift_prog_bit(input logic bit_value);
    begin
      prog_din_i = bit_value;
      @(posedge prog_clk_i);
    end
  endtask

  task automatic reset_dut();
    begin
      reset_i     = 1'b1;
      prog_rst_i  = 1'b1;
      en_i        = 1'b1;
      prog_we_i   = 1'b0;
      prog_done_i = 1'b0;
      prog_din_i  = 1'b0;
      drive_boundary_to_zero(ext_data_i, ext_pred_i);

      repeat (RESET_CYCLES) @(posedge clk_i);
      repeat (RESET_CYCLES) @(posedge prog_clk_i);

      // Deassert resets away from active clock edges to avoid
      // recovery/removal violations in gate-level timing sim.
      @(negedge clk_i);
      reset_i = 1'b0;
      @(negedge prog_clk_i);
      prog_rst_i = 1'b0;

      repeat (POST_RESET_CYCLES) @(posedge clk_i);
      repeat (POST_RESET_CYCLES) @(posedge prog_clk_i);
    end
  endtask

  task automatic load_bin_bitstream();
    logic [7:0] bitstream_bytes [0:BITSTREAM_BYTES-1];
    string bitstream_file;
    int fd;
    int bytes_read;
    int byte_idx;
    int bit_idx;
    int bits_shifted;
    begin
      bitstream_file = DEFAULT_BITSTREAM_FILE;
      void'($value$plusargs("bitstream_bin=%s", bitstream_file));

      fd = $fopen(bitstream_file, "rb");
      if (fd == 0) begin
        $fatal(1, "Could not open bitstream file: %s", bitstream_file);
      end

      bytes_read = $fread(bitstream_bytes, fd);
      $fclose(fd);

      if (bytes_read < BITSTREAM_BYTES) begin
        $fatal(1,
               "Bitstream file too short: expected at least %0d bytes, got %0d",
               BITSTREAM_BYTES, bytes_read);
      end

      $display("[TB] Programming bitstream from %s (%0d bytes, %0d bits)",
               bitstream_file, bytes_read, BITSTREAM_SIZE_BITS);

      prog_done_i = 1'b0;
      prog_we_i   = 1'b1;
      bits_shifted = 0;

      for (byte_idx = 0; byte_idx < BITSTREAM_BYTES; byte_idx++) begin
        for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
          if (bits_shifted < BITSTREAM_SIZE_BITS) begin
            shift_prog_bit(bitstream_bytes[byte_idx][bit_idx]);
            bits_shifted++;
          end
        end
      end

      prog_we_i = 1'b0;
      repeat (SCANCHAIN_DELIM_DEPTH) @(posedge prog_clk_i);
      prog_din_i  = 1'b0;
      prog_done_i = 1'b1;

      repeat (PROG_DONE_SETTLE_PROG) @(posedge prog_clk_i);
      repeat (PROG_DONE_SETTLE_FUNC) @(posedge clk_i);
    end
  endtask

  task automatic test_mul_array_directed_functionality();
    logic [7:0] a_values [0:3];
    logic [7:0] b_values [0:3];
    logic [7:0] expected_values [0:3];
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
    logic [7:0] a_values [0:3];
    logic [7:0] b_values [0:3];
    logic [7:0] expected_values [0:3];
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
    reset_dut();
    load_bin_bitstream();

    drive_boundary_to_zero(ext_data_i, ext_pred_i);
    en_i = 1'b1;
    repeat (FUNCTIONAL_SETTLE) @(posedge clk_i);

    test_mul_array_directed_functionality();
    test_mul_array_randomized();

    $display("[TB] PASS: vector-multiply top-level test completed");
    $finish;
  end

endmodule
