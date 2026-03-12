`include "axi/typedef.svh"

module axi_lite_mem_wrap_256bit #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 256,
    parameter int NUM_WORDS      = 32   // 32 words x 256 bits (32 bytes) = 1KB total
)(
    input logic clk_i,
    input logic rst_ni,
    AXI_LITE.Slave axi_i
);
    localparam int WORD_ADDR_WIDTH = $clog2(NUM_WORDS);        // 5 bits
    localparam int BYTE_OFFSET     = $clog2(AXI_DATA_WIDTH/8); // 5 bits (32 bytes/word)
    localparam int STRB_WIDTH      = AXI_DATA_WIDTH / 8;       // 32 bytes

    // -------------------------------------------------------------------------
    // BaseJump 1RW Memory Signals
    // -------------------------------------------------------------------------
    logic                          mem_v;
    logic                          mem_w;
    logic [WORD_ADDR_WIDTH-1:0]    mem_addr;
    logic [AXI_DATA_WIDTH-1:0]     mem_w_mask_bit;

    // Fan out the byte strobe to a bit mask (1 strobe bit -> 8 data bits)
    always_comb begin
        for (int i = 0; i < STRB_WIDTH; i++) begin
            mem_w_mask_bit[i*8 +: 8] = axi_i.w_strb[i] ? 8'hFF : 8'h00;
        end
    end

    // -------------------------------------------------------------------------
    // Write address buffer
    //
    // AXI crossbar delivers AW and W through separate pipelines; AW arrives
    // before W.  Buffer the AW address and fire the memory write when W arrives.
    // -------------------------------------------------------------------------
    logic                       aw_pending_q;
    logic [WORD_ADDR_WIDTH-1:0] aw_addr_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q <= 1'b0;
            aw_addr_q    <= '0;
        end else begin
            if (axi_i.aw_valid && !aw_pending_q) begin
                aw_pending_q <= 1'b1;
                // Strip the 5-bit byte offset to get the 5-bit word index
                aw_addr_q    <= axi_i.aw_addr[WORD_ADDR_WIDTH-1+BYTE_OFFSET : BYTE_OFFSET];
            end else if (axi_i.w_valid && aw_pending_q) begin
                aw_pending_q <= 1'b0;
            end
        end
    end

    logic do_write;
    assign do_write = aw_pending_q & axi_i.w_valid;

    // -------------------------------------------------------------------------
    // Memory port steering
    // -------------------------------------------------------------------------
    assign mem_v    = do_write | axi_i.ar_valid;
    assign mem_w    = do_write;
    assign mem_addr = do_write ? aw_addr_q
                               : axi_i.ar_addr[WORD_ADDR_WIDTH-1+BYTE_OFFSET : BYTE_OFFSET];

    // -------------------------------------------------------------------------
    // AXI Handshakes
    // -------------------------------------------------------------------------
    assign axi_i.aw_ready = ~aw_pending_q;
    assign axi_i.w_ready  = aw_pending_q;
    assign axi_i.ar_ready = 1'b1;

    assign axi_i.b_valid = do_write;
    assign axi_i.b_resp  = axi_pkg::RESP_OKAY;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) axi_i.r_valid <= 1'b0;
        else         axi_i.r_valid <= axi_i.ar_valid;
    end
    assign axi_i.r_resp = axi_pkg::RESP_OKAY;

    // -------------------------------------------------------------------------
    // Instantiate RAM
    // -------------------------------------------------------------------------
    bsg_mem_1rw_sync_mask_write_bit #(
        .width_p           ( AXI_DATA_WIDTH ),
        .els_p             ( NUM_WORDS      ),
        .latch_last_read_p ( 1              )
    ) i_bsg_mem (
        .clk_i    ( clk_i          ),
        .reset_i  ( ~rst_ni        ),
        .v_i      ( mem_v          ),
        .w_i      ( mem_w          ),
        .addr_i   ( mem_addr       ),
        .data_i   ( axi_i.w_data   ),
        .w_mask_i ( mem_w_mask_bit ),
        .data_o   ( axi_i.r_data   )
    );

endmodule
