`include "axi/typedef.svh"

// AXI-Lite slave bridge to a bank of io_csr_cta_desc_info registers.
//
// Address map (byte-addressed, 16-bit / 2-byte words):
//   CSR[0]  @ offset 0x00  (byte addr 0x00, word addr 0)
//   CSR[1]  @ offset 0x02  (byte addr 0x02, word addr 1)
//   ...
//   CSR[N-1]@ offset N*2-2
//
// Register index extracted as: aw_addr[REG_IDX_W : 1]  (drops byte-lane bit 0)
//
// Write strobes are honoured via read-modify-write on the data path.
// Reads are zero-latency (CSR rd_data_o is combinatorial from stored reg_r).
// AXI r_valid is registered one cycle after ar_valid, aligned with data output.

module axi_lite_csr_wrap_16bit #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 16,
    parameter int NUM_REGS   = 8    // number of 16-bit CSR registers
)(
    input  logic clk_i,
    input  logic rst_i,
    AXI_LITE.Slave axi_i
);
    // BYTE_OFFSET = log2(DATA_WIDTH/8) = 1 for 16-bit data
    localparam int BYTE_OFFSET = $clog2(DATA_WIDTH / 8);   // 1
    localparam int REG_IDX_W   = $clog2(NUM_REGS);         // e.g. 4 for NUM_REGS=16

    // -------------------------------------------------------------------------
    // Write address buffer (same pattern as axi_lite_mem_wrap_8bit)
    // -------------------------------------------------------------------------
    logic              aw_pending_q;
    logic [REG_IDX_W-1:0] aw_idx_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            aw_pending_q <= 1'b0;
            aw_idx_q     <= '0;
        end else begin
            if (axi_i.aw_valid && !aw_pending_q) begin
                aw_pending_q <= 1'b1;
                aw_idx_q     <= axi_i.aw_addr[REG_IDX_W + BYTE_OFFSET - 1 : BYTE_OFFSET];
            end else if (aw_pending_q && axi_i.w_valid) begin
                aw_pending_q <= 1'b0;
            end
        end
    end

    logic do_write;
    assign do_write = aw_pending_q & axi_i.w_valid;

    // -------------------------------------------------------------------------
    // Per-register enables and strobe-merged write data
    // -------------------------------------------------------------------------
    logic [NUM_REGS-1:0]   csr_wr_en;
    logic [DATA_WIDTH-1:0] csr_wr_data   [NUM_REGS-1:0];  // strobe-merged
    logic [DATA_WIDTH-1:0] csr_rd_data   [NUM_REGS-1:0];  // from CSR instances

    always_comb begin
        for (int i = 0; i < NUM_REGS; i++) begin
            csr_wr_en[i] = do_write & (REG_IDX_W'(i) == aw_idx_q);
            // Read-modify-write: preserve bytes where strobe is 0
            csr_wr_data[i][7:0]  = axi_i.w_strb[0] ? axi_i.w_data[7:0]  : csr_rd_data[i][7:0];
            csr_wr_data[i][15:8] = axi_i.w_strb[1] ? axi_i.w_data[15:8] : csr_rd_data[i][15:8];
        end
    end

    // -------------------------------------------------------------------------
    // Read address latch
    // -------------------------------------------------------------------------
    logic [REG_IDX_W-1:0] ar_idx_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            axi_i.r_valid <= 1'b0;
            ar_idx_q      <= '0;
        end else begin
            axi_i.r_valid <= axi_i.ar_valid & axi_i.ar_ready;
            if (axi_i.ar_valid)
                ar_idx_q <= axi_i.ar_addr[REG_IDX_W + BYTE_OFFSET - 1 : BYTE_OFFSET];
        end
    end

    // Drive rd_en on matching CSR
    logic [NUM_REGS-1:0] csr_rd_en;
    always_comb begin
        csr_rd_en = '0;
        if (axi_i.ar_valid)
            csr_rd_en[axi_i.ar_addr[REG_IDX_W + BYTE_OFFSET - 1 : BYTE_OFFSET]] = 1'b1;
    end

    // -------------------------------------------------------------------------
    // CSR register instances
    // -------------------------------------------------------------------------
    generate
        for (genvar g = 0; g < NUM_REGS; g++) begin : gen_csrs
            io_csr_cta_desc_info i_csr (
                .clk_i     ( clk_i           ),
                .reset_i   ( rst_i           ),
                .wr_en_i   ( csr_wr_en[g]    ),
                .wr_data_i ( csr_wr_data[g]  ),
                .rd_en_i   ( csr_rd_en[g]    ),
                .rd_data_o ( csr_rd_data[g]  ),
                .rd_valid_o(                 )   // use our registered r_valid instead
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // AXI handshakes
    // -------------------------------------------------------------------------
    assign axi_i.aw_ready = ~aw_pending_q;
    assign axi_i.w_ready  = aw_pending_q;
    assign axi_i.ar_ready = 1'b1;

    assign axi_i.b_valid  = do_write;
    assign axi_i.b_resp   = axi_pkg::RESP_OKAY;

    assign axi_i.r_data   = csr_rd_data[ar_idx_q];
    assign axi_i.r_resp   = axi_pkg::RESP_OKAY;

endmodule
