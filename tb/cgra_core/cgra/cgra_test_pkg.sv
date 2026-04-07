package cgra_test_pkg;

  import "DPI-C" context function void dice_vector_mul_golden_init(
      input int unsigned seed
  );
  import "DPI-C" context function void dice_vector_mul_golden_directed_case(
      output int unsigned a0,
      output int unsigned a1,
      output int unsigned a2,
      output int unsigned a3,
      output int unsigned b0,
      output int unsigned b1,
      output int unsigned b2,
      output int unsigned b3,
      output int unsigned y0,
      output int unsigned y1,
      output int unsigned y2,
      output int unsigned y3
  );
  import "DPI-C" context function void dice_vector_mul_golden_random_case(
      output int unsigned a0,
      output int unsigned a1,
      output int unsigned a2,
      output int unsigned a3,
      output int unsigned b0,
      output int unsigned b1,
      output int unsigned b2,
      output int unsigned b3,
      output int unsigned y0,
      output int unsigned y1,
      output int unsigned y2,
      output int unsigned y3
  );

  task automatic drive_boundary_to_zero(
      output logic [15:0] ext_data_i [0:15],
      output logic       ext_pred_i [0:1]
  );
    int i;
    begin
      for (i = 0; i < 16; i++) begin
        ext_data_i[i] = '0;
      end
      for (i = 0; i < 2; i++) begin
        ext_pred_i[i] = 1'b0;
      end
    end
  endtask

  task automatic apply_mul_array_inputs(
      output logic [15:0] ext_data_i [0:15],
      output logic       ext_pred_i [0:1],
      input  logic [15:0] a_values [0:3],
      input  logic [15:0] b_values [0:3]
  );
    int i;
    begin
      drive_boundary_to_zero(ext_data_i, ext_pred_i);
      for (i = 0; i < 4; i++) begin
        ext_data_i[i]   = a_values[i];
        ext_data_i[i+4] = b_values[i];
      end
    end
  endtask

  task automatic load_directed_case(
      output logic [15:0] a_values [0:3],
      output logic [15:0] b_values [0:3],
      output logic [15:0] expected_values [0:3]
  );
    int unsigned a0, a1, a2, a3;
    int unsigned b0, b1, b2, b3;
    int unsigned y0, y1, y2, y3;
    begin
      dice_vector_mul_golden_directed_case(
          a0, a1, a2, a3,
          b0, b1, b2, b3,
          y0, y1, y2, y3
      );
      a_values[0] = a0[15:0];
      a_values[1] = a1[15:0];
      a_values[2] = a2[15:0];
      a_values[3] = a3[15:0];
      b_values[0] = b0[15:0];
      b_values[1] = b1[15:0];
      b_values[2] = b2[15:0];
      b_values[3] = b3[15:0];
      expected_values[0] = y0[15:0];
      expected_values[1] = y1[15:0];
      expected_values[2] = y2[15:0];
      expected_values[3] = y3[15:0];
    end
  endtask

  task automatic load_random_case(
      output logic [15:0] a_values [0:3],
      output logic [15:0] b_values [0:3],
      output logic [15:0] expected_values [0:3]
  );
    int unsigned a0, a1, a2, a3;
    int unsigned b0, b1, b2, b3;
    int unsigned y0, y1, y2, y3;
    begin
      dice_vector_mul_golden_random_case(
          a0, a1, a2, a3,
          b0, b1, b2, b3,
          y0, y1, y2, y3
      );
      a_values[0] = a0[15:0];
      a_values[1] = a1[15:0];
      a_values[2] = a2[15:0];
      a_values[3] = a3[15:0];
      b_values[0] = b0[15:0];
      b_values[1] = b1[15:0];
      b_values[2] = b2[15:0];
      b_values[3] = b3[15:0];
      expected_values[0] = y0[15:0];
      expected_values[1] = y1[15:0];
      expected_values[2] = y2[15:0];
      expected_values[3] = y3[15:0];
    end
  endtask

  task automatic check_mul_outputs(
      input string test_name,
      input logic [15:0] ext_data_o [0:15],
      input logic [15:0] a_values [0:3],
      input logic [15:0] b_values [0:3],
      input logic [15:0] expected_values [0:3]
  );
    int i;
    begin
      for (i = 0; i < 4; i++) begin
        if (^ext_data_o[i] === 1'bX) begin
          $fatal(1, "%s: ext_data_o_%0d contains X/Z (%b)",
                 test_name, i, ext_data_o[i]);
        end
        if (ext_data_o[i] !== expected_values[i]) begin
          $fatal(1,
                 "%s: ext_data_o_%0d expected %0d (A=%0d, B=%0d), got %0d",
                 test_name, i, expected_values[i], a_values[i], b_values[i],
                 ext_data_o[i]);
        end
      end
    end
  endtask

endpackage
