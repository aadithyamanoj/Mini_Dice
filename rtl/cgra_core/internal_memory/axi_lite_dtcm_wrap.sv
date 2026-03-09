`include "axi/typedef.svh"

module axi_lite_dtcm_wrap #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32
)(
    input logic clk_i,
    input logic rst_ni,
    AXI_LITE.Slave axi_i 
);
    localparam int ROW_BYTES = 128;
    localparam int ROW_BITS  = ROW_BYTES * 8;

    logic                 sram_en;
    logic [ROW_BYTES-1:0] sram_we;
    logic [2:0]           sram_addr;
    logic [ROW_BITS-1:0]  sram_wdata;
    logic [ROW_BITS-1:0]  sram_rdata;

    dtcm i_dtcm (
        .clk_i   ( clk_i      ),
        .en_i    ( sram_en    ),
        .we_i    ( sram_we    ),
        .addr_i  ( sram_addr  ),
        .wdata_i ( sram_wdata ),
        .rdata_o ( sram_rdata )
    );

    typedef enum logic [2:0] { IDLE, READ_WAIT, READ_RESP, WRITE_DO, WRITE_RESP } state_t;
    state_t state_d, state_q;

    logic [2:0]  saved_row_idx;
    logic [6:0]  saved_byte_offset;
    logic [2:0]  saved_wr_row;
    logic [6:0]  saved_wr_offset;
    wire [31:0] ar_addr_flat;
    wire [31:0] aw_addr_flat;
    assign ar_addr_flat = axi_i.ar_addr;
    assign aw_addr_flat = axi_i.aw_addr;
    logic [31:0] saved_wr_data;
    logic [3:0]  saved_wr_strb;
    logic [6:0]  byte_offset;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q           <= IDLE;
            saved_row_idx     <= '0;
            saved_byte_offset <= '0;
            saved_wr_row      <= '0;
            saved_wr_offset   <= '0;
            saved_wr_data     <= '0;
            saved_wr_strb     <= '0;
        end else begin
            state_q <= state_d;
            if (state_q == IDLE && state_d == READ_WAIT) begin
                saved_row_idx <= ar_addr_flat[9:7];
                saved_byte_offset <= ar_addr_flat[6:0];
            end
            if (state_q == IDLE && state_d == WRITE_DO) begin
                saved_wr_row    <= aw_addr_flat[9:7];
                saved_wr_offset <= aw_addr_flat[6:0];
                saved_wr_data   <= axi_i.w_data;
                saved_wr_strb   <= axi_i.w_strb;
            end
        end
    end

    always_comb begin
        sram_en     = 1'b0;
        sram_we     = '0;
        sram_wdata  = '0;
        sram_addr   = '0;
        byte_offset = '0;

        axi_i.aw_ready = 1'b0;
        axi_i.w_ready  = 1'b0;
        axi_i.b_valid  = 1'b0;
        axi_i.b_resp   = axi_pkg::RESP_OKAY;

        axi_i.ar_ready = 1'b0;
        axi_i.r_valid  = 1'b0;
        axi_i.r_resp   = axi_pkg::RESP_OKAY;
        axi_i.r_data   = '0;

        state_d = state_q;

        case (state_q)
            IDLE: begin
                if (axi_i.aw_valid && axi_i.w_valid) begin
                    axi_i.aw_ready = 1'b1;
                    axi_i.w_ready  = 1'b1;
                    state_d        = WRITE_DO;
                end
                else if (axi_i.ar_valid) begin
                    sram_addr      = axi_i.ar_addr[9:7];
                    sram_en        = 1'b1;
                    axi_i.ar_ready = 1'b1;
                    state_d        = READ_WAIT;
                end
            end

            WRITE_DO: begin
                sram_addr  = saved_wr_row;
                sram_en    = 1'b1;
                sram_wdata = { {(ROW_BITS-AXI_DATA_WIDTH){1'b0}}, saved_wr_data } << (saved_wr_offset * 8);
                for (int i = 0; i < (AXI_DATA_WIDTH/8); i++) begin
                    if (saved_wr_strb[i]) sram_we[saved_wr_offset + i] = 1'b1;
                end
                state_d = WRITE_RESP;
            end

            WRITE_RESP: begin
                axi_i.b_valid = 1'b1;
                if (axi_i.b_ready) state_d = IDLE;
            end

            READ_WAIT: begin
                sram_addr = saved_row_idx;
                sram_en   = 1'b1;
                state_d   = READ_RESP;
            end

            READ_RESP: begin
                axi_i.r_valid = 1'b1;
                axi_i.r_data  = sram_rdata >> (saved_byte_offset * 8);
                if (axi_i.r_ready) state_d = IDLE;
            end

            default: state_d = IDLE;
        endcase
    end

endmodule
