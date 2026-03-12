`include "bsg_defines.v"

module cgra_bitstream_buf_serial
  import dice_pkg::*;
(
    input logic clk_i
    , input logic reset_i

    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i
    , input logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm0_chunk_en_i
    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i
    , input logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm1_chunk_en_i

    , input logic v_i
    , input logic bank_i
    , output logic ready_o
    , output logic busy_o

    , output logic [1:0] bank_valid_o

    , output logic prog_clk_o
    , output logic prog_rst_o
    , output logic prog_done_o
    , output logic prog_we_o
    , output logic prog_din_o
  );

  localparam int num_chunks_lp = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                 / DICE_MEM_DATA_WIDTH;
  localparam int bit_ctr_width_lp = $clog2(DICE_BITSTREAM_SIZE);

  typedef enum logic [1:0] {
    e_idle
    , e_prog_reset
    , e_prog_shift
  } state_e;

  logic [1:0][DICE_BITSTREAM_SIZE-1:0] bank_data_r;
  logic [1:0][num_chunks_lp-1:0] bank_chunk_valid_r;
  logic [1:0] bank_valid_r;

  logic active_bank_r;
  logic [DICE_BITSTREAM_SIZE-1:0][0:0] serializer_data_li;
  logic serializer_ready_lo;
  logic serializer_v_lo;
  logic serializer_yumi_li;
  logic serializer_data_lo;

  state_e state_r, state_n;
  logic [bit_ctr_width_lp-1:0] bit_ctr_r;

  logic request_fire;
  logic load_serializer_li;
  logic last_bit_li;
  logic cm0_load_v_li;
  logic cm1_load_v_li;
  logic cm0_load_start_li;
  logic cm1_load_start_li;
  logic [num_chunks_lp-1:0] next_cm0_mask_li;
  logic [num_chunks_lp-1:0] next_cm1_mask_li;

  // --------------------------------------------------------------------------
  // Stage 1: resident bitstream banks
  // Assemble full bitstreams from fetch-stage chunks into two persistent banks.
  // --------------------------------------------------------------------------
  assign cm0_load_v_li = (cm0_chunk_en_i != '0);
  assign cm1_load_v_li = (cm1_chunk_en_i != '0);
  assign cm0_load_start_li = cm0_chunk_en_i[0];
  assign cm1_load_start_li = cm1_chunk_en_i[0];

  // --------------------------------------------------------------------------
  // Stage 2: CGRA programming
  // Serialize one selected resident bank into the CGRA scan chain.
  // --------------------------------------------------------------------------
  assign serializer_data_li = bank_data_r[active_bank_r];

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

  assign request_fire = v_i & ready_o;
  assign load_serializer_li = (state_r == e_prog_reset);
  assign serializer_yumi_li = (state_r == e_prog_shift) & serializer_v_lo;
  assign last_bit_li = (bit_ctr_r == bit_ctr_width_lp'(DICE_BITSTREAM_SIZE-1));

  assign ready_o = (state_r == e_idle) & bank_valid_r[bank_i];
  assign busy_o = (state_r != e_idle);
  assign bank_valid_o = bank_valid_r;

  assign prog_clk_o = clk_i;
  assign prog_rst_o = (state_r == e_prog_reset);
  assign prog_done_o = (state_r == e_idle);
  assign prog_we_o = serializer_yumi_li;
  assign prog_din_o = serializer_data_lo;

  always_comb begin
    state_n = state_r;

    unique case (state_r)
      e_idle: begin
        if (request_fire) begin
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

  always_ff @(posedge clk_i) begin : state_reg
    integer i;

    if (reset_i) begin
      state_r <= e_idle;
      bit_ctr_r <= '0;
      active_bank_r <= '0;
      bank_data_r <= '0;
      bank_chunk_valid_r <= '0;
      bank_valid_r <= '0;
    end
    else begin
      state_r <= state_n;

      if (request_fire) begin
        active_bank_r <= bank_i;
      end

      if (load_serializer_li) begin
        bit_ctr_r <= '0;
      end
      else if (serializer_yumi_li) begin
        bit_ctr_r <= bit_ctr_r + 1'b1;
      end

      next_cm0_mask_li = cm0_load_start_li ? '0 : bank_chunk_valid_r[0];
      next_cm1_mask_li = cm1_load_start_li ? '0 : bank_chunk_valid_r[1];

      for (i = 0; i < num_chunks_lp; i++) begin
        if (cm0_chunk_en_i[i]) begin
          bank_data_r[0][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH] <= cm0_data_i;
          next_cm0_mask_li[i] = 1'b1;
        end

        if (cm1_chunk_en_i[i]) begin
          bank_data_r[1][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH] <= cm1_data_i;
          next_cm1_mask_li[i] = 1'b1;
        end
      end

      bank_chunk_valid_r[0] <= next_cm0_mask_li;
      bank_chunk_valid_r[1] <= next_cm1_mask_li;

      if (cm0_load_v_li) begin
        bank_valid_r[0] <= &next_cm0_mask_li;
      end

      if (cm1_load_v_li) begin
        bank_valid_r[1] <= &next_cm1_mask_li;
      end
    end
  end

endmodule
