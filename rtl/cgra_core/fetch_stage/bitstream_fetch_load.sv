module bitstream_fetch_load
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import axi4_xbar_pkg::*;
#(
    parameter int CHUNK_SIZE    = DICE_MEM_DATA_WIDTH,                           // 512 bits per CM chunk
    parameter int BITSTREAM_SIZE = DICE_BITSTREAM_SIZE,  // 2048 bits max
    parameter int NUM_CHUNKS    = (BITSTREAM_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE // 4 chunks
) (
    input logic clk_i,
    input logic rst_i,

    // Flush signal (cancels in-progress load)
    input logic flush_i,

    //from decoder
    input logic                       meta_valid_i,
    input logic [DICE_ADDR_WIDTH-1:0] bitstream_addr_i,

    //to cgra buffers
    output logic [CHUNK_SIZE-1:0]  cm0_data_o,
    output logic [NUM_CHUNKS-1:0]  cm0_chunk_en_o,

    output logic [CHUNK_SIZE-1:0]  cm1_data_o,
    output logic [NUM_CHUNKS-1:0]  cm1_chunk_en_o,

    //to valid checker
    output logic done_streaming_o,

    // AXI4 read master → crossbar slave port
    output slv_req_t  bs_req_o,
    input  slv_resp_t bs_resp_i,

    //to FDR EX buffer
    output logic cm_num_o
);

  localparam int CounterBits   = $clog2(NUM_CHUNKS + 1);
  localparam int WordsPerChunk = CHUNK_SIZE / 16;                   // 32 words of 16 bits per chunk
  localparam int TotalWords    = BITSTREAM_SIZE / 16;               // 128 words total
  localparam int WordIdxBits   = $clog2(WordsPerChunk);
  localparam int BurstLen      = TotalWords - 1;                    // 127 (ar_len value)

  typedef enum logic [1:0] {
    StateIdle,
    StateStreaming,  // Handles both Request and Response phases
    StateDone
  } bitstream_fetch_state_e;

  bitstream_fetch_state_e state_q, state_d;

  // registered states
  logic [DICE_ADDR_WIDTH-1:0] cm0_addr_q, cm1_addr_q, cm0_addr_d, cm1_addr_d;
  logic cm_select_q, cm_select_d;  // 0 = cm0, 1 = cm1

  logic [CounterBits-1:0] chunk_count_q, chunk_count_d;  // chunks streamed so far

  // 512-bit assembly buffer: pack 32 × 16-bit words into one CM chunk
  logic [CHUNK_SIZE-1:0] word_buf_q, word_buf_d;

  // Index of current 16-bit word within the active chunk (0–31)
  logic [WordIdxBits-1:0] word_idx_q, word_idx_d;

  logic [DICE_ADDR_WIDTH-1:0] addr_q, addr_d;
  logic cm0_valid_d, cm1_valid_d, cm0_valid_q, cm1_valid_q;

  // AR transaction has been accepted; R phase is now active
  logic ar_sent_q, ar_sent_d;

  logic [NUM_CHUNKS-1:0] load_chunk_en_d;
  logic [NUM_CHUNKS-1:0] load_chunk_en_q;

  // Registered chunk data snapshot written to CM on chunk boundary
  logic [CHUNK_SIZE-1:0] cm_data_q, cm_data_d;

  // Byte address alias for done_streaming_o comparison
  logic [DICE_ADDR_WIDTH-1:0] bitstream_addr_dec;
  assign bitstream_addr_dec = bitstream_addr_i;

  // AXI handshake pulses
  logic ar_fire;
  logic r_fire;
  assign ar_fire = bs_req_o.ar_valid && bs_resp_i.ar_ready;
  assign r_fire  = bs_resp_i.r_valid && bs_req_o.r_ready;

  // Chunk boundary: last word in a chunk, or final word of burst
  logic chunk_done;
  assign chunk_done = r_fire && ((word_idx_q == WordIdxBits'(WordsPerChunk - 1)) ||
                                  bs_resp_i.r.last);

  assign done_streaming_o = (cm_select_q == 1'b0 && cm0_valid_q &&
                             cm0_addr_q == bitstream_addr_dec) ||
                            (cm_select_q == 1'b1 && cm1_valid_q &&
                             cm1_addr_q == bitstream_addr_dec);

  always_comb begin
    state_d         = state_q;
    chunk_count_d   = chunk_count_q;
    cm_select_d     = cm_select_q;
    cm0_addr_d      = cm0_addr_q;
    cm1_addr_d      = cm1_addr_q;
    word_buf_d      = word_buf_q;
    word_idx_d      = word_idx_q;
    addr_d          = addr_q;
    cm0_valid_d     = cm0_valid_q;
    cm1_valid_d     = cm1_valid_q;
    ar_sent_d       = ar_sent_q;
    load_chunk_en_d = '0;
    cm_data_d       = cm_data_q;
    cm0_chunk_en_o  = '0;
    cm1_chunk_en_o  = '0;

    // Route chunk enables to selected buffer
    if (cm_select_q == 1'b0) begin
      cm0_chunk_en_o = load_chunk_en_q;
    end else begin
      cm1_chunk_en_o = load_chunk_en_q;
    end

    unique case (state_q)
      StateIdle: begin
        ar_sent_d   = 1'b0;
        word_idx_d  = '0;
        if (meta_valid_i) begin
          if (!done_streaming_o) begin
            if (cm_select_q == 1'b0 && cm1_valid_q && cm1_addr_q == bitstream_addr_dec) begin
              cm_select_d = 1'b1;
            end else if (cm_select_q == 1'b1 && cm0_valid_q &&
                         cm0_addr_q == bitstream_addr_dec) begin
              cm_select_d = 1'b0;
            end else begin
              if (cm0_valid_q || cm1_valid_q) cm_select_d = ~cm_select_q;
              else cm_select_d = 1'b0;

              addr_d        = bitstream_addr_i;
              state_d       = StateStreaming;
              chunk_count_d = '0;

              if (cm_select_d == 1'b0) begin
                cm0_addr_d  = bitstream_addr_dec;
                cm0_valid_d = 1'b0;
              end else begin
                cm1_addr_d  = bitstream_addr_dec;
                cm1_valid_d = 1'b0;
              end
            end
          end
        end
      end

      StateStreaming: begin
        if (flush_i) begin
          state_d   = StateIdle;
          ar_sent_d = 1'b0;
          word_idx_d = '0;
          chunk_count_d = '0;
        end else if (!ar_sent_q) begin
          // AR phase: assert ar_valid until ar_ready
          if (ar_fire) begin
            ar_sent_d = 1'b1;
          end
        end else begin
          // R phase: pack 16-bit beats into chunk buffer
          if (r_fire) begin
            word_buf_d[word_idx_q*16 +: 16] = bs_resp_i.r.data;
          end

          if (chunk_done) begin
            // Capture completed chunk and pulse chunk enable
            cm_data_d       = word_buf_d;
            load_chunk_en_d = ({{(NUM_CHUNKS-1){1'b0}}, 1'b1} << chunk_count_q);
            chunk_count_d   = chunk_count_q + 1'b1;
            word_idx_d      = '0;
            word_buf_d      = '0;

            if (bs_resp_i.r.last) begin
              state_d   = StateDone;
              ar_sent_d = 1'b0;
            end
          end else if (r_fire) begin
            word_idx_d = word_idx_q + 1'b1;
          end
        end
      end

      StateDone: begin
        state_d = StateIdle;
        if (cm_select_q == 1'b1) begin
          cm1_valid_d = 1'b1;
        end else begin
          cm0_valid_d = 1'b1;
        end
      end

      default: state_d = StateIdle;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q         <= StateIdle;
      chunk_count_q   <= '0;
      cm_select_q     <= 1'b0;
      word_buf_q      <= '0;
      word_idx_q      <= '0;
      cm_data_q       <= '0;
      cm0_addr_q      <= '0;
      cm1_addr_q      <= '0;
      addr_q          <= '0;
      cm0_valid_q     <= 1'b0;
      cm1_valid_q     <= 1'b0;
      load_chunk_en_q <= '0;
      ar_sent_q       <= 1'b0;
    end else begin
      state_q         <= state_d;
      chunk_count_q   <= chunk_count_d;
      cm0_addr_q      <= cm0_addr_d;
      cm1_addr_q      <= cm1_addr_d;
      word_buf_q      <= word_buf_d;
      word_idx_q      <= word_idx_d;
      cm_data_q       <= cm_data_d;
      cm_select_q     <= cm_select_d;
      addr_q          <= addr_d;
      cm0_valid_q     <= cm0_valid_d;
      cm1_valid_q     <= cm1_valid_d;
      load_chunk_en_q <= load_chunk_en_d;
      ar_sent_q       <= ar_sent_d;
    end
  end

  // AR channel: driven fields
  assign bs_req_o.ar_valid  = (state_q == StateStreaming) && !ar_sent_q && !flush_i;
  assign bs_req_o.ar.addr   = addr_q;
  assign bs_req_o.ar.len    = 8'(BurstLen);
  assign bs_req_o.ar.size   = 3'b001;  // 2 bytes per beat
  assign bs_req_o.ar.burst  = 2'b01;   // INCR
  assign bs_req_o.ar.id     = '0;
  assign bs_req_o.ar.lock   = '0;
  assign bs_req_o.ar.cache  = '0;
  assign bs_req_o.ar.prot   = '0;
  assign bs_req_o.ar.qos    = '0;
  assign bs_req_o.ar.region = '0;
  assign bs_req_o.ar.user   = '0;

  // R channel: accept data in StateStreaming after AR has fired
  assign bs_req_o.r_ready   = (state_q == StateStreaming) && ar_sent_q;

  // Write channels tied off (read-only master)
  always_comb begin
    bs_req_o.aw       = '0;
    bs_req_o.aw_valid = 1'b0;
    bs_req_o.w        = '0;
    bs_req_o.w_valid  = 1'b0;
    bs_req_o.b_ready  = 1'b1;
  end

  // CM data outputs: use registered snapshot
  assign cm0_data_o = cm_data_q;
  assign cm1_data_o = cm_data_q;

  assign cm_num_o = cm_select_q;

endmodule
