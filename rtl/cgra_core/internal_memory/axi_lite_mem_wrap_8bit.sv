`include "axi/typedef.svh"

module axi_lite_mem_wrap_8bit #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 8,
    parameter int NUM_WORDS      = 256
)(
    input logic clk_i,
    input logic rst_ni,
    AXI_LITE.Slave axi_i
);
    localparam int ADDR_WIDTH = $clog2(NUM_WORDS);
    localparam int STRB_WIDTH = AXI_DATA_WIDTH / 8;

    // -------------------------------------------------------------------------
    // BaseJump 1RW Memory Signals
    // -------------------------------------------------------------------------
    logic                      mem_v;
    logic                      mem_w;
    logic [ADDR_WIDTH-1:0]     mem_addr;
    logic [AXI_DATA_WIDTH-1:0] mem_w_mask_bit;

    // Fan out the byte strobe to a bit mask
    always_comb begin
        for (int i = 0; i < STRB_WIDTH; i++) begin
            mem_w_mask_bit[i*8 +: 8] = axi_i.w_strb[i] ? 8'hFF : 8'h00;
        end
    end

    // -------------------------------------------------------------------------
    // Write address buffer
    //
    // The AXI crossbar (axi_lite_mux) delivers AW and W through separate
    // pipelines with a FIFO gate in between, so AW always arrives at least
    // one cycle before W.  Buffer the AW address and fire the actual memory
    // write only when the W data arrives.
    // -------------------------------------------------------------------------
    logic                  aw_pending_q;
    logic [ADDR_WIDTH-1:0] aw_addr_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q <= 1'b0;
            aw_addr_q    <= '0;
        end else begin
            if (axi_i.aw_valid && !aw_pending_q) begin
                // Latch incoming write address
                aw_pending_q <= 1'b1;
                aw_addr_q    <= axi_i.aw_addr[ADDR_WIDTH-1:0];
            end else if (axi_i.w_valid && aw_pending_q) begin
                // Write data arrived — clear the pending flag
                aw_pending_q <= 1'b0;
            end
        end
    end

    // Write fires when W data arrives and an AW address is already buffered
    logic do_write;
    assign do_write = aw_pending_q & axi_i.w_valid;

    // -------------------------------------------------------------------------
    // Memory port steering
    // -------------------------------------------------------------------------
    assign mem_v    = do_write | axi_i.ar_valid;
    assign mem_w    = do_write;
    assign mem_addr = do_write ? aw_addr_q : axi_i.ar_addr[ADDR_WIDTH-1:0];

    // -------------------------------------------------------------------------
    // AXI Handshakes
    // -------------------------------------------------------------------------
    // Only accept a new AW when we are not already holding one
    assign axi_i.aw_ready = ~aw_pending_q;
    // Only accept W after the matching AW has been latched
    assign axi_i.w_ready  = aw_pending_q;
    assign axi_i.ar_ready = 1'b1;

    // Write response: fires the same cycle as the actual memory write
    assign axi_i.b_valid = do_write;
    assign axi_i.b_resp  = axi_pkg::RESP_OKAY;

    // Read response: register r_valid by one cycle so it aligns with the
    // synchronous memory output (data_o updates one cycle after ar_valid)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) axi_i.r_valid <= 1'b0;
        else         axi_i.r_valid <= axi_i.ar_valid;
    end
    assign axi_i.r_resp  = axi_pkg::RESP_OKAY;

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
