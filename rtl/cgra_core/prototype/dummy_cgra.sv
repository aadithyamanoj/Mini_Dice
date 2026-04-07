// amanoj3 & Claude (AI-generated)
//
// Dummy CGRA model for simulation/testing.
// Models a CGRA that performs SIMD add-5 on a bus of 32-bit operands.
// Configurable pipeline latency to model real CGRA execution delay.
//
// The 1024-bit data bus is treated as 32 independent 32-bit SIMD lanes.
// Each lane computes: out[lane] = in[lane] + 5
//
// Fixed-latency pipeline: ready_o is always asserted (no backpressure).
// If latency_p == 0, the module is purely combinational.

module dummy_cgra
  import dice_pkg::*;
  import DE_pkg::*;
#(parameter int num_lanes_p   = DICE_NUM_BANKS
 ,parameter int data_width_p  = DICE_REG_DATA_WIDTH
 ,parameter int tid_width_p   = DICE_TID_WIDTH
 ,parameter int latency_p     = 4
 // derived
 ,parameter int bus_width_lp  = num_lanes_p * data_width_p
)
(
  input  logic                    clk_i
 ,input  logic                    rst_i

 // Input interface (valid/ready)
 ,input  logic                    v_i
 ,output logic                    ready_o
 ,input  logic [bus_width_lp-1:0] data_i
 ,input  logic [tid_width_p-1:0]  tid_i

 // Output interface
 ,output logic                    v_o
 ,output logic [bus_width_lp-1:0] data_o
 ,output logic [tid_width_p-1:0]  tid_o
);

  // ============================================================
  // SIMD Add-5 Computation
  // Each 32-bit lane: result = operand + 5
  // ============================================================
  logic [bus_width_lp-1:0] computed_data;

  genvar lane;
  generate
    for (lane = 0; lane < num_lanes_p; lane++) begin : gen_simd_add
      assign computed_data[lane*data_width_p +: data_width_p]
        = data_i[lane*data_width_p +: data_width_p] + data_width_p'(5);
    end
  endgenerate

  // ============================================================
  // Pipeline Registers
  // Model CGRA execution latency with a shift-register pipeline.
  // Uses unpacked arrays for pipeline stages (consistent with
  // latency_pipe.sv in this codebase).
  // ============================================================
  generate
    if (latency_p == 0) begin : gen_comb
      // Combinational pass-through
      assign data_o = computed_data;
      assign tid_o  = tid_i;
      assign v_o    = v_i;

    end else begin : gen_pipe
      logic [bus_width_lp-1:0] data_pipe_r [0:latency_p-1];
      logic [tid_width_p-1:0]  tid_pipe_r  [0:latency_p-1];
      logic                    v_pipe_r    [0:latency_p-1];

      always_ff @(posedge clk_i) begin
        if (rst_i) begin
          for (int i = 0; i < latency_p; i++) begin
            data_pipe_r[i] <= '0;
            tid_pipe_r[i]  <= '0;
            v_pipe_r[i]    <= 1'b0;
          end
        end else begin
          // Stage 0: latch the SIMD-computed result
          data_pipe_r[0] <= computed_data;
          tid_pipe_r[0]  <= tid_i;
          v_pipe_r[0]    <= v_i;

          // Stages 1..latency_p-1: shift through pipeline
          for (int i = 1; i < latency_p; i++) begin
            data_pipe_r[i] <= data_pipe_r[i-1];
            tid_pipe_r[i]  <= tid_pipe_r[i-1];
            v_pipe_r[i]    <= v_pipe_r[i-1];
          end
        end
      end

      assign data_o = data_pipe_r[latency_p-1];
      assign tid_o  = tid_pipe_r[latency_p-1];
      assign v_o    = v_pipe_r[latency_p-1];
    end
  endgenerate

  // ============================================================
  // Ready: fixed-latency pipeline, always ready to accept data
  // (no stall/backpressure mechanism in this dummy model)
  // ============================================================
  assign ready_o = 1'b1;

  // ============================================================
  // Parameter validation
  // ============================================================
  // synopsys translate_off
  initial begin
    assert (num_lanes_p > 0)
      else $fatal(1, "dummy_cgra: num_lanes_p must be > 0");
    assert (data_width_p > 0)
      else $fatal(1, "dummy_cgra: data_width_p must be > 0");
    assert (latency_p >= 0)
      else $fatal(1, "dummy_cgra: latency_p must be >= 0");
  end
  // synopsys translate_on

endmodule
