`include "bsg_defines.sv"

module cgra_bitstream_buf_serial
  import dice_pkg::*;
#(
    parameter int PROG_BITSTREAM_BITS_P = 1690,
    parameter int PROG_RESET_CYCLES_P   = 10,
    parameter int PROG_FLUSH_CYCLES_P   = 84
) (
      input logic clk_i
    , input logic reset_i

    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i
    , input logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm0_chunk_en_i
    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i
    , input logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm1_chunk_en_i

    , input  logic v_i
    , input  logic bank_i
    , output logic ready_o
    , output logic busy_o

    , output logic [1:0] bank_valid_o

    , output logic prog_rst_o
    , output logic prog_done_o
    , output logic prog_we_o
    , output logic prog_din_o
);

  localparam int num_chunks_lp = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                 / DICE_MEM_DATA_WIDTH;
  localparam int bit_ctr_width_lp = $clog2(DICE_BITSTREAM_SIZE);
  localparam int reset_ctr_width_lp = (PROG_RESET_CYCLES_P > 1) ? $clog2(PROG_RESET_CYCLES_P) : 1;
  localparam int flush_ctr_width_lp = (PROG_FLUSH_CYCLES_P > 1) ? $clog2(PROG_FLUSH_CYCLES_P) : 1;

  typedef enum logic [2:0] {
      e_idle
    , e_prog_reset
    , e_prog_shift
    , e_prog_flush
    , e_serializer_rearm
  } state_e;

  logic [1:0][DICE_BITSTREAM_SIZE-1:0] bank_data_r;
  logic [1:0][num_chunks_lp-1:0] bank_chunk_valid_r;
  logic [1:0] bank_valid_r;
  logic programmed_r;
  logic serializer_loaded_r;

  logic active_bank_r;
  logic serializer_reset_li;
  logic [DICE_BITSTREAM_SIZE-1:0][0:0] serializer_data_li;
  logic serializer_ready_lo;
  logic serializer_v_lo;
  logic serializer_yumi_li;
  logic serializer_data_lo;

  state_e state_r, state_n;
  logic [bit_ctr_width_lp-1:0] bit_ctr_r;
  logic [reset_ctr_width_lp-1:0] reset_ctr_r;
  logic [flush_ctr_width_lp-1:0] flush_ctr_r;

  logic load_serializer_li;
  logic request_fire;
  logic [num_chunks_lp-1:0] next_cm0_mask_li;
  logic [num_chunks_lp-1:0] next_cm1_mask_li;

  // --------------------------------------------------------------------------
  // Stage 1: resident bitstream banks
  // Assemble full bitstreams from fetch-stage chunks into two persistent banks.
  // --------------------------------------------------------------------------
  assign serializer_data_li = bank_data_r[active_bank_r];

  bsg_parallel_in_serial_out #(
      .width_p(1)
      , .els_p(DICE_BITSTREAM_SIZE)
      , .hi_to_lo_p(0)
  ) bitstream_serializer (
      .clk_i(clk_i)
      , .reset_i(serializer_reset_li)
      , .valid_i(load_serializer_li)
      , .data_i(serializer_data_li)
      , .ready_and_o(serializer_ready_lo)
      , .valid_o(serializer_v_lo)
      , .data_o(serializer_data_lo)
      , .yumi_i(serializer_yumi_li)
  );

  assign request_fire = v_i & ready_o;
  assign load_serializer_li = (state_r == e_prog_reset)
                              & ~serializer_loaded_r
                              & serializer_ready_lo;
  assign serializer_yumi_li = (state_r == e_prog_shift) & serializer_v_lo;

  assign ready_o = (state_r == e_idle) & bank_valid_r[bank_i];
  assign busy_o = (state_r != e_idle);
  assign bank_valid_o = bank_valid_r;
  assign serializer_reset_li = reset_i | (state_r == e_serializer_rearm);

  assign prog_rst_o = reset_i | (state_r == e_prog_reset);
  assign prog_done_o = programmed_r & (state_r == e_idle);
  assign prog_we_o = (state_r == e_prog_shift);
  assign prog_din_o = (state_r == e_prog_shift) ? serializer_data_lo : 1'b0;

  always_comb begin
    state_n = state_r;

    unique case (state_r)
      e_idle: begin
        if (request_fire) begin
          state_n = e_prog_reset;
        end
      end

      e_prog_reset: begin
        if ((reset_ctr_r == reset_ctr_width_lp'(PROG_RESET_CYCLES_P-1))
            && (serializer_loaded_r | load_serializer_li)) begin
          state_n = e_prog_shift;
        end
      end

      e_prog_shift: begin
        if (serializer_yumi_li && (bit_ctr_r == bit_ctr_width_lp'(PROG_BITSTREAM_BITS_P - 1))) begin
          state_n = e_prog_flush;
        end
      end

      e_prog_flush: begin
        if (flush_ctr_r == flush_ctr_width_lp'(PROG_FLUSH_CYCLES_P - 1)) begin
          state_n = e_serializer_rearm;
        end
      end

      e_serializer_rearm: begin
        state_n = e_idle;
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
      reset_ctr_r <= '0;
      flush_ctr_r <= '0;
      active_bank_r <= '0;
      bank_data_r <= '0;
      bank_chunk_valid_r <= '0;
      bank_valid_r <= '0;
      programmed_r <= 1'b0;
      serializer_loaded_r <= 1'b0;
    end else begin
      state_r <= state_n;

      next_cm0_mask_li = cm0_chunk_en_i[0] ? '0 : bank_chunk_valid_r[0];
      next_cm1_mask_li = cm1_chunk_en_i[0] ? '0 : bank_chunk_valid_r[1];

      if (request_fire) begin
        active_bank_r <= bank_i;
        programmed_r <= 1'b0;
        serializer_loaded_r <= 1'b0;
        bit_ctr_r <= '0;
        reset_ctr_r <= '0;
        flush_ctr_r <= '0;
      end else begin
        if (state_r == e_prog_reset) begin
          if (load_serializer_li) begin
            serializer_loaded_r <= 1'b1;
          end

          if (reset_ctr_r != reset_ctr_width_lp'(PROG_RESET_CYCLES_P - 1)) begin
            reset_ctr_r <= reset_ctr_r + 1'b1;
          end
        end

        if (state_r == e_prog_shift && serializer_yumi_li) begin
          if (bit_ctr_r == bit_ctr_width_lp'(PROG_BITSTREAM_BITS_P - 1)) begin
            flush_ctr_r  <= '0;
            programmed_r <= 1'b1;
          end else begin
            bit_ctr_r <= bit_ctr_r + 1'b1;
          end
        end

        if (state_r == e_prog_flush
            && flush_ctr_r != flush_ctr_width_lp'(PROG_FLUSH_CYCLES_P-1)) begin
          flush_ctr_r <= flush_ctr_r + 1'b1;
        end

        if (state_r == e_serializer_rearm) begin
          serializer_loaded_r <= 1'b0;
        end
      end

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

      if (cm0_chunk_en_i != '0) begin
        bank_valid_r[0] <= &next_cm0_mask_li;
      end

      if (cm1_chunk_en_i != '0) begin
        bank_valid_r[1] <= &next_cm1_mask_li;
      end
    end
  end

endmodule
