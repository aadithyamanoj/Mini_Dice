`include "bsg_defines.v"

module cgra_bitstream_buf_serial
  import dice_pkg::*;
(
    input logic clk_i
    , input logic reset_i

    , input logic v_i
    , input logic [DICE_BITSTREAM_SIZE-1:0] data_i
    , output logic ready_o

    , output logic v_o
    , input logic yumi_i
    , output logic busy_o

    , output logic prog_clk_o
    , output logic prog_rst_o
    , output logic prog_done_o
    , output logic prog_we_o
    , output logic prog_din_o
  );

  typedef enum logic [1:0] {
    e_idle
    , e_prog_reset
    , e_prog_shift
  } state_e;

  localparam int bit_ctr_width_lp = $clog2(DICE_BITSTREAM_SIZE);

  logic fifo_v_lo;
  logic fifo_yumi_li;
  logic [DICE_BITSTREAM_SIZE-1:0] fifo_data_lo;

  logic serializer_ready_lo;
  logic serializer_v_lo;
  logic serializer_yumi_li;
  logic serializer_data_lo;
  logic [DICE_BITSTREAM_SIZE-1:0][0:0] serializer_data_li;

  state_e state_r, state_n;
  logic [bit_ctr_width_lp-1:0] bit_ctr_r;

  logic start_program_li;
  logic load_serializer_li;
  logic last_bit_li;

  assign serializer_data_li = fifo_data_lo;

  bsg_two_fifo
    #(.width_p(DICE_BITSTREAM_SIZE))
    bitstream_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.ready_o(ready_o)
     ,.data_i(data_i)
     ,.v_i(v_i)
     ,.v_o(fifo_v_lo)
     ,.data_o(fifo_data_lo)
     ,.yumi_i(fifo_yumi_li)
     );

  bsg_parallel_in_serial_out
    #(.width_p(1)
      ,.els_p(DICE_BITSTREAM_SIZE)
      ,.hi_to_lo_p(0)
      )
    bitstream_serializer
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.valid_i(load_serializer_li)
     ,.data_i(serializer_data_li)
     ,.ready_and_o(serializer_ready_lo)
     ,.valid_o(serializer_v_lo)
     ,.data_o(serializer_data_lo)
     ,.yumi_i(serializer_yumi_li)
     );

  assign start_program_li = (state_r == e_idle) & fifo_v_lo & yumi_i;
  assign load_serializer_li = (state_r == e_prog_reset);
  assign fifo_yumi_li = load_serializer_li & serializer_ready_lo;
  assign serializer_yumi_li = (state_r == e_prog_shift) & serializer_v_lo;
  assign last_bit_li = (bit_ctr_r == bit_ctr_width_lp'(DICE_BITSTREAM_SIZE-1));

  assign prog_clk_o = clk_i;
  assign prog_din_o = serializer_data_lo;
  assign prog_we_o = serializer_yumi_li;
  assign prog_rst_o = (state_r == e_prog_reset);
  assign prog_done_o = (state_r == e_idle);

  assign busy_o = (state_r != e_idle);
  assign v_o = (state_r == e_idle) & fifo_v_lo;

  always_comb begin
    state_n = state_r;

    unique case (state_r)
      e_idle: begin
        if (start_program_li) begin
          state_n = e_prog_reset;
        end
      end

      e_prog_reset: begin
        if (serializer_ready_lo) begin
          state_n = e_prog_shift;
        end
      end

      e_prog_shift: begin
        if (serializer_yumi_li & last_bit_li) begin
          state_n = e_idle;
        end
      end

      default: begin
        state_n = e_idle;
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      state_r <= e_idle;
      bit_ctr_r <= '0;
    end
    else begin
      state_r <= state_n;

      if (load_serializer_li) begin
        bit_ctr_r <= '0;
      end
      else if (serializer_yumi_li) begin
        bit_ctr_r <= bit_ctr_r + 1'b1;
      end
    end
  end

endmodule
