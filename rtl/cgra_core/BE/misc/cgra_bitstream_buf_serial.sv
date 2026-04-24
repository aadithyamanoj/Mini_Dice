`include "bsg_defines.sv"

module cgra_bitstream_buf_serial
  import dice_pkg::*;
#(
    parameter int PROG_BITSTREAM_BITS_P = DICE_BITSTREAM_SIZE,
    parameter int PROG_RESET_CYCLES_P   = 10,
    parameter int PROG_FLUSH_CYCLES_P   = 84
) (
      input logic clk_i
    , input logic reset_i

    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i
    , input logic [((PROG_BITSTREAM_BITS_P + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm0_chunk_en_i
    , input logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i
    , input logic [((PROG_BITSTREAM_BITS_P + DICE_MEM_DATA_WIDTH - 1)
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

  localparam int num_chunks_lp = (PROG_BITSTREAM_BITS_P + DICE_MEM_DATA_WIDTH - 1)
                                 / DICE_MEM_DATA_WIDTH;
  localparam int bank_payload_bits_lp = num_chunks_lp * DICE_MEM_DATA_WIDTH;
  localparam int bank_storage_bits_lp = 1 << $clog2(bank_payload_bits_lp);
  localparam int last_chunk_bits_lp = PROG_BITSTREAM_BITS_P
                                      - ((num_chunks_lp - 1) * DICE_MEM_DATA_WIDTH);
  localparam int bit_ctr_width_lp = (PROG_BITSTREAM_BITS_P > 1) ? $clog2(
      PROG_BITSTREAM_BITS_P
  ) : 1;
  localparam int chunk_ctr_width_lp = (num_chunks_lp > 1) ? $clog2(num_chunks_lp) : 1;
  localparam int chunk_bit_ctr_width_lp = (DICE_MEM_DATA_WIDTH > 1) ? $clog2(
      DICE_MEM_DATA_WIDTH
  ) : 1;
  localparam int reset_ctr_width_lp = (PROG_RESET_CYCLES_P > 1) ? $clog2(PROG_RESET_CYCLES_P) : 1;
  localparam int flush_ctr_width_lp = (PROG_FLUSH_CYCLES_P > 1) ? $clog2(PROG_FLUSH_CYCLES_P) : 1;

  function automatic logic [DICE_MEM_DATA_WIDTH-1:0] read_chunk(
      input logic [bank_storage_bits_lp-1:0] bank_bits,
      input int unsigned chunk_idx
  );
    read_chunk = '0;
    if (chunk_idx < num_chunks_lp) begin
      read_chunk = bank_bits[chunk_idx*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH];
    end
  endfunction

  typedef enum logic [1:0] {
      e_idle
    , e_prog_reset
    , e_prog_shift
    , e_prog_flush
  } state_e;

  logic [1:0][bank_storage_bits_lp-1:0] bank_data_r;
  logic [1:0][num_chunks_lp-1:0] bank_chunk_valid_r;
  logic [1:0] bank_valid_r;
  logic programmed_r;

  logic active_bank_r;
  logic [DICE_MEM_DATA_WIDTH-1:0] shift_word_r;
  logic [DICE_MEM_DATA_WIDTH-1:0] next_chunk_li;

  state_e state_r, state_n;
  logic [bit_ctr_width_lp-1:0] bit_ctr_r;
  logic [chunk_ctr_width_lp-1:0] chunk_ctr_r;
  logic [chunk_bit_ctr_width_lp-1:0] chunk_bit_ctr_r;
  logic [reset_ctr_width_lp-1:0] reset_ctr_r;
  logic [flush_ctr_width_lp-1:0] flush_ctr_r;

  logic request_fire;
  logic [num_chunks_lp-1:0] next_cm0_mask_li;
  logic [num_chunks_lp-1:0] next_cm1_mask_li;

  // --------------------------------------------------------------------------
  // Stage 1: resident bitstream banks
  // Assemble full bitstreams from fetch-stage chunks into two persistent banks.
  // Banks are padded to a power-of-two width so the serializer can read a full
  // chunk with a single variable part-select even when the true bitstream size
  // is not chunk-aligned.
  // --------------------------------------------------------------------------
  assign next_chunk_li   = read_chunk(bank_data_r[active_bank_r], chunk_ctr_r + 1'b1);

  assign request_fire = v_i & ready_o;
  assign ready_o = (state_r == e_idle) & bank_valid_r[bank_i];
  assign busy_o = (state_r != e_idle);
  assign bank_valid_o = bank_valid_r;

  assign prog_rst_o = reset_i | (state_r == e_prog_reset);
  assign prog_done_o = programmed_r & (state_r == e_idle);
  assign prog_we_o = (state_r == e_prog_shift);
  assign prog_din_o = (state_r == e_prog_shift) ? shift_word_r[0] : 1'b0;

  always_comb begin
    state_n = state_r;

    unique case (state_r)
      e_idle: begin
        if (request_fire) begin
          state_n = e_prog_reset;
        end
      end

      e_prog_reset: begin
        if (reset_ctr_r == reset_ctr_width_lp'(PROG_RESET_CYCLES_P-1)) begin
          state_n = e_prog_shift;
        end
      end

      e_prog_shift: begin
        if (bit_ctr_r == bit_ctr_width_lp'(PROG_BITSTREAM_BITS_P - 1)) begin
          state_n = e_prog_flush;
        end
      end

      e_prog_flush: begin
        if (flush_ctr_r == flush_ctr_width_lp'(PROG_FLUSH_CYCLES_P - 1)) begin
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
      chunk_ctr_r <= '0;
      chunk_bit_ctr_r <= '0;
      reset_ctr_r <= '0;
      flush_ctr_r <= '0;
      active_bank_r <= '0;
      bank_data_r <= '0;
      bank_chunk_valid_r <= '0;
      bank_valid_r <= '0;
      programmed_r <= 1'b0;
      shift_word_r <= '0;
    end else begin
      state_r <= state_n;

      next_cm0_mask_li = cm0_chunk_en_i[0] ? '0 : bank_chunk_valid_r[0];
      next_cm1_mask_li = cm1_chunk_en_i[0] ? '0 : bank_chunk_valid_r[1];

      if (request_fire) begin
        active_bank_r <= bank_i;
        programmed_r <= 1'b0;
        bit_ctr_r <= '0;
        chunk_ctr_r <= '0;
        chunk_bit_ctr_r <= '0;
        shift_word_r <= read_chunk(bank_data_r[bank_i], 0);
        reset_ctr_r <= '0;
        flush_ctr_r <= '0;
      end else begin
        if (state_r == e_prog_reset) begin
          if (reset_ctr_r != reset_ctr_width_lp'(PROG_RESET_CYCLES_P - 1)) begin
            reset_ctr_r <= reset_ctr_r + 1'b1;
          end
        end

        if (state_r == e_prog_shift) begin
          if (bit_ctr_r == bit_ctr_width_lp'(PROG_BITSTREAM_BITS_P - 1)) begin
            flush_ctr_r  <= '0;
            programmed_r <= 1'b1;
          end else begin
            bit_ctr_r <= bit_ctr_r + 1'b1;
            if (chunk_bit_ctr_r == chunk_bit_ctr_width_lp'(DICE_MEM_DATA_WIDTH - 1)) begin
              chunk_ctr_r <= chunk_ctr_r + 1'b1;
              chunk_bit_ctr_r <= '0;
              shift_word_r <= next_chunk_li;
            end else begin
              chunk_bit_ctr_r <= chunk_bit_ctr_r + 1'b1;
              shift_word_r <= {1'b0, shift_word_r[DICE_MEM_DATA_WIDTH-1:1]};
            end
          end
        end

        if (state_r == e_prog_flush
            && flush_ctr_r != flush_ctr_width_lp'(PROG_FLUSH_CYCLES_P-1)) begin
          flush_ctr_r <= flush_ctr_r + 1'b1;
        end
      end

      for (i = 0; i < num_chunks_lp; i++) begin
        if (cm0_chunk_en_i[i]) begin
          if (i == num_chunks_lp - 1) begin
            bank_data_r[0][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH]
              <= {{(DICE_MEM_DATA_WIDTH-last_chunk_bits_lp){1'b0}},
                  cm0_data_i[last_chunk_bits_lp-1:0]};
          end else begin
            bank_data_r[0][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH] <= cm0_data_i;
          end
          next_cm0_mask_li[i] = 1'b1;
        end

        if (cm1_chunk_en_i[i]) begin
          if (i == num_chunks_lp - 1) begin
            bank_data_r[1][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH]
              <= {{(DICE_MEM_DATA_WIDTH-last_chunk_bits_lp){1'b0}},
                  cm1_data_i[last_chunk_bits_lp-1:0]};
          end else begin
            bank_data_r[1][i*DICE_MEM_DATA_WIDTH+:DICE_MEM_DATA_WIDTH] <= cm1_data_i;
          end
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
