`include "axi/typedef.svh"

// AXI-Lite slave bridge to a 16-bit wide synchronous SRAM.
//
// Simulates the off-chip FPGA SRAM using bsg_mem_1rw_sync_mask_write_bit.
// AXI addresses are byte-addressed; the word address strips the byte-lane
// bit (bit 0) and the base address offset.
//
// Default parameters give a 1024-word (2 KB) SRAM suitable for simulation.
// For a full 16-bit address space model set NUM_WORDS = 32768 (64 KB / 2).
//
// AW arrives before W (guaranteed by axi_lite_mux FIFO ordering); the
// address is buffered until W data arrives, mirroring axi_lite_mem_wrap_8bit.

module axi_lite_fpgamem_wrap_16bit #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 16,
    parameter int NUM_WORDS  = 1024   // simulation depth; parameterise for full 32K
)(
    input  logic clk_i,
    input  logic rst_i,
    AXI_LITE.Slave axi_i
);
    localparam int WORD_ADDR_W = $clog2(NUM_WORDS);     // 10 for 1024 words
    localparam int BYTE_OFFSET = $clog2(DATA_WIDTH / 8); // 1 for 16-bit
    localparam int STRB_WIDTH  = DATA_WIDTH / 8;         // 2

    // -------------------------------------------------------------------------
    // Byte-strobe → bit-mask expansion
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem_w_mask_bit;
    always_comb begin
        for (int i = 0; i < STRB_WIDTH; i++)
            mem_w_mask_bit[i*8 +: 8] = axi_i.w_strb[i] ? 8'hFF : 8'h00;
    end

    // -------------------------------------------------------------------------
    // Write address buffer
    // -------------------------------------------------------------------------
    logic                  aw_pending_q;
    logic [WORD_ADDR_W-1:0] aw_word_addr_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            aw_pending_q      <= 1'b0;
            aw_word_addr_q    <= '0;
        end else begin
            if (axi_i.aw_valid && !aw_pending_q) begin
                aw_pending_q   <= 1'b1;
                // Strip byte-lane bit; base address offset (bit 16 for 0x0001_0000)
                // sits above WORD_ADDR_W so lower bits give the correct offset.
                aw_word_addr_q <= axi_i.aw_addr[WORD_ADDR_W + BYTE_OFFSET - 1 : BYTE_OFFSET];
            end else if (aw_pending_q && axi_i.w_valid) begin
                aw_pending_q <= 1'b0;
            end
        end
    end

    logic do_write;
    assign do_write = aw_pending_q & axi_i.w_valid;

    // -------------------------------------------------------------------------
    // Memory port steering
    // -------------------------------------------------------------------------
    logic                   mem_v, mem_w;
    logic [WORD_ADDR_W-1:0] mem_addr;

    assign mem_v    = do_write | (axi_i.ar_valid & axi_i.ar_ready);
    assign mem_w    = do_write;
    assign mem_addr = do_write
                    ? aw_word_addr_q
                    : axi_i.ar_addr[WORD_ADDR_W + BYTE_OFFSET - 1 : BYTE_OFFSET];

    // -------------------------------------------------------------------------
    // AXI handshakes
    // -------------------------------------------------------------------------
    assign axi_i.aw_ready = ~aw_pending_q;
    assign axi_i.w_ready  = aw_pending_q;
    assign axi_i.ar_ready = 1'b1;

    assign axi_i.b_valid  = do_write;
    assign axi_i.b_resp   = axi_pkg::RESP_OKAY;

    always_ff @(posedge clk_i) begin
        if (rst_i) axi_i.r_valid <= 1'b0;
        else       axi_i.r_valid <= axi_i.ar_valid & axi_i.ar_ready;
    end
    assign axi_i.r_resp = axi_pkg::RESP_OKAY;

    // -------------------------------------------------------------------------
    // SRAM: bsg_mem_1rw_sync_mask_write_bit
    // -------------------------------------------------------------------------
    bsg_mem_1rw_sync_mask_write_bit #(
        .width_p           ( DATA_WIDTH ),
        .els_p             ( NUM_WORDS  ),
        .latch_last_read_p ( 1          )
    ) i_bsg_mem (
        .clk_i    ( clk_i          ),
        .reset_i  ( rst_i          ),
        .v_i      ( mem_v          ),
        .w_i      ( mem_w          ),
        .addr_i   ( mem_addr       ),
        .data_i   ( axi_i.w_data   ),
        .w_mask_i ( mem_w_mask_bit ),
        .data_o   ( axi_i.r_data   )
    );

endmodule
