`include "DE_pkg.sv"
`include "dice_pkg.sv"

module dice_rf_square

import DE_pkg::*;
import dice_pkg::*;

#(
    parameter int NUM_PORTS  = DICE_NUM_BANKS,
    parameter int DATA_WIDTH = DICE_REG_DATA_WIDTH,
    parameter int NUM_TID    = DICE_NUM_MAX_THREADS_PER_CORE,
    parameter int TID_WIDTH  = $clog2(NUM_TID),
    parameter int DEPTH      = DICE_REGS_PER_BANK,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int NUM_CONST  = DICE_NUM_CONST,
    parameter int NUM_PRED   = DICE_NUM_PRED,
    parameter int TOTAL_REGS = DICE_TOTAL_REGS,
    parameter int BUF_DEPTH  = LDST_BUF_DEPTH
)
(
      input  logic              clk_i
    , input  logic              reset_i

    // Read Interface
    , input logic                             rd_tid_valid_i
    , output logic                            rd_tid_ready_o

    , input logic                             rd_en_i
    , input logic [TID_WIDTH-1:0]             rd_tid_i
    , input logic [TOTAL_REGS-1:0]            rd_bitmap_i
    , output logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0] rd_data_o
    , output logic                            rf_rd_valid_o
    , output logic [TID_WIDTH-1:0]            tid_o

    // Predicate output — all TIDs, all preds, always valid
    , output logic [NUM_PRED*NUM_TID-1:0]     pred_o

    // Write Interface — CGRA
    , input logic [TID_WIDTH-1:0]               cgra_tid_i
    , input logic [((NUM_PORTS+NUM_PRED+1)*DATA_WIDTH)-1:0] cgra_data_i
    , input logic [TOTAL_REGS-1:0]              cgra_wr_bitmap_i
    , input logic                               cgra_valid_i

    // Write Interface — LDST
    , input logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i
    , input logic                           ldst_valid_i
    , output logic                          ldst_ready_o
);

    // =========================================================================
    // Square layout local parameters
    // Each row holds REGS_PER_ROW 8-bit regs (one per TID).
    //   TID[TID_WIDTH-1 : SUB_IDX_WIDTH]  ->  row address
    //   TID[SUB_IDX_WIDTH-1 : 0]          ->  sub-index within row
    // =========================================================================
    localparam int SUB_IDX_WIDTH  = TID_WIDTH / 2;
    localparam int REGS_PER_ROW   = 2**SUB_IDX_WIDTH;
    localparam int ROW_DEPTH      = DEPTH / REGS_PER_ROW;
    localparam int ROW_ADDR_WIDTH = TID_WIDTH - SUB_IDX_WIDTH;

    // Packed address split — computed once per TID
    typedef struct packed {
        logic [ROW_ADDR_WIDTH-1:0] row;
        logic [SUB_IDX_WIDTH-1:0]  sub;
    } tid_addr_t;

    function automatic tid_addr_t split_tid(input logic [TID_WIDTH-1:0] tid);
        tid_addr_t a;
        a.row = tid[TID_WIDTH-1:SUB_IDX_WIDTH];
        a.sub = tid[SUB_IDX_WIDTH-1:0];
        return a;
    endfunction

    // =========================================================================
    // GPR bank signals (same widths as original — wr_ctrl still outputs full TID)
    // =========================================================================
    logic [NUM_PORTS-1:0]            rf_rd_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_rd_addr;

    logic [NUM_PORTS-1:0]            rf_wr_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_wr_addr;
    logic [NUM_PORTS*DATA_WIDTH-1:0] rf_wr_data;

    logic [NUM_PORTS-1:0] stall_o;

    logic special_fifo_full;

    // =========================================================================
    // GPR write path (regs 0 .. NUM_PORTS-1)
    // =========================================================================
    reg_wr_cmd cgra_wr_li [NUM_PORTS-1:0];

    // GPR portion of the bitmap (no swizzling)
    logic [NUM_PORTS-1:0] cgra_bitmap;
    assign cgra_bitmap = cgra_wr_bitmap_i[NUM_PORTS-1:0];

    genvar i;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_cgra_wr
            assign cgra_wr_li[i].data = cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH];
            assign cgra_wr_li[i].mask = cgra_bitmap[i];
            assign cgra_wr_li[i].tid  = cgra_tid_i;
        end
    endgenerate

    reg_wr_cmd [NUM_PORTS-1:0] ldst_wr_li;
    cache_wr_cmd ldst_convert;

    assign ldst_convert = ldst_wr_i;
    assign ldst_wr_li   = unpack_ldsr_wr(assemble_ldst_wr(ldst_convert));

    // =========================================================================
    // LDST target decode — GPR vs special (const/pred)
    // =========================================================================
    logic ldst_gpr_valid;
    logic ldst_special_valid;

    assign ldst_gpr_valid     = ldst_valid_i
                                && (|ldst_convert.wr_bitmap[NUM_PORTS-1:0]);
    assign ldst_special_valid = ldst_valid_i
                                && (|ldst_convert.wr_bitmap[TOTAL_REGS-1:NUM_PORTS]);

    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_wr_ctrl
            dice_wr_ctrl_bank #(
                  .WIDTH(DATA_WIDTH)
                , .DEPTH(DEPTH)
                , .ADDR_WIDTH(ADDR_WIDTH)
                , .BUF_DEPTH(BUF_DEPTH)
            ) u_wr_ctrl (
                  .clk_i(clk_i)
                , .reset_i(reset_i)

                , .cgra_wr_i(cgra_wr_li[i])
                , .cgra_valid_i(cgra_valid_i)
                , .cgra_ready_o()

                , .wr_ldst_i(ldst_wr_li[i])
                , .ldst_valid_i(ldst_gpr_valid)

                , .stall_o(stall_o[i])

                , .ws_o(rf_wr_addr[i*ADDR_WIDTH +: ADDR_WIDTH])
                , .data_o(rf_wr_data[i*DATA_WIDTH +: DATA_WIDTH])
                , .we_o(rf_wr_en[i])
            );
        end
    endgenerate

    // =========================================================================
    // Special registers (const + pred) write path
    // LDST writes buffered in FIFO, CGRA has priority
    // =========================================================================
    special_regs_cmd cgra_special, ldst_special_in;
    special_regs_cmd ldst_special_wb, special_cmd;

    // CGRA special regs command from bitmap
    always_comb begin
        cgra_special = '0;
        for (int j = 0; j < NUM_CONST; j++) begin
            cgra_special.const_mask[j] = cgra_wr_bitmap_i[NUM_PORTS + j];
            cgra_special.const_data[j*DATA_WIDTH +: DATA_WIDTH] =
                cgra_data_i[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH];
        end
        for (int j = 0; j < NUM_PRED; j++) begin
            cgra_special.pred_mask[j] = cgra_wr_bitmap_i[NUM_PORTS + NUM_CONST + j];
            cgra_special.pred_data[j] = cgra_data_i[(NUM_PORTS + 1 + j)*DATA_WIDTH];
        end
    end

    // LDST special regs command from cache response
    assign ldst_special_in = assemble_special_wr(ldst_convert);

    logic [TID_WIDTH-1:0] ldst_special_tid_in;
    assign ldst_special_tid_in = ldst_convert.tid;

    // FIFO buffer for LDST special writes (widened to include TID for pred)
    localparam int SPECIAL_ENTRY_WIDTH = $bits(special_regs_cmd) + TID_WIDTH;
    logic special_fifo_ready, special_fifo_valid;
    logic pop_special;
    logic [SPECIAL_ENTRY_WIDTH-1:0] special_fifo_data;

    bsg_fifo_1r1w_small #(
          .width_p(SPECIAL_ENTRY_WIDTH)
        , .els_p(BUF_DEPTH)
    ) u_special_fifo (
          .clk_i   (clk_i)
        , .reset_i (reset_i)
        , .v_i     (ldst_special_valid)
        , .ready_o (special_fifo_ready)
        , .data_i  ({ldst_special_in, ldst_special_tid_in})
        , .v_o     (special_fifo_valid)
        , .yumi_i  (pop_special)
        , .data_o  (special_fifo_data)
    );

    logic [TID_WIDTH-1:0] ldst_special_wb_tid;
    assign {ldst_special_wb, ldst_special_wb_tid} = special_fifo_data;

    // Arbitration: CGRA has priority over buffered LDST
    assign pop_special = !cgra_valid_i && special_fifo_valid;
    assign special_cmd = cgra_valid_i ? cgra_special : ldst_special_wb;

    logic [TID_WIDTH-1:0] special_tid;
    assign special_tid = cgra_valid_i ? cgra_tid_i : ldst_special_wb_tid;

    logic special_wr_valid;
    assign special_wr_valid = cgra_valid_i || special_fifo_valid;

    assign special_fifo_full = ~special_fifo_ready;
    assign ldst_ready_o = ~(|stall_o) & ~special_fifo_full;

    // =========================================================================
    // Constant registers (regs NUM_PORTS .. NUM_PORTS+NUM_CONST-1)
    // Flip-flops, shared across all threads
    // =========================================================================
    logic [NUM_CONST-1:0][DATA_WIDTH-1:0] const_regs;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            const_regs <= '0;
        end else if (special_wr_valid) begin
            for (int j = 0; j < NUM_CONST; j++) begin
                if (special_cmd.const_mask[j])
                    const_regs[j] <= special_cmd.const_data[j*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end

    generate
        for (i = 0; i < NUM_CONST; i++) begin : gen_const_rd
            assign rd_data_o[(NUM_PORTS + i)*DATA_WIDTH +: DATA_WIDTH] = const_regs[i];
        end
    endgenerate

    // =========================================================================
    // Predicate registers — NUM_PRED banks × NUM_TID entries (1 bit each)
    // Conceptually square (ROW_DEPTH rows × REGS_PER_ROW per row) but
    // implemented as flat flip-flops since we read all continuously.
    // =========================================================================
    logic [NUM_TID-1:0][NUM_PRED-1:0] pred_regs;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            pred_regs <= '0;
        end else if (special_wr_valid) begin
            for (int j = 0; j < NUM_PRED; j++) begin
                if (special_cmd.pred_mask[j])
                    pred_regs[special_tid][j] <= special_cmd.pred_data[j];
            end
        end
    end

    // Predicate output — all TIDs driven continuously
    assign pred_o = pred_regs;

    // =========================================================================
    // GPR read path
    // =========================================================================
    dice_read_org #(
          .NUM_PORTS(NUM_PORTS)
        , .DATA_WIDTH(DATA_WIDTH)
        , .NUM_TID(NUM_TID)
        , .TID_WIDTH(TID_WIDTH)
        , .DEPTH(DEPTH)
        , .ADDR_WIDTH(ADDR_WIDTH)
    ) read_org (
          .clk_i(clk_i)
        , .reset_i(reset_i)

        , .rd_tid_valid_i(rd_tid_valid_i)
        , .rd_tid_ready_o(rd_tid_ready_o)

        , .rd_en_i(rd_en_i)
        , .rd_tid_i(rd_tid_i)
        , .rd_bitmap_i(rd_bitmap_i[NUM_PORTS-1:0])

        , .rd_sel_o(rf_rd_addr)
        , .rd_en_o(rf_rd_en)
        , .rd_valid_o(rf_rd_valid_o)
    );

    // =========================================================================
    // Square GPR register file
    //
    // Each bank contains REGS_PER_ROW sub-SRAMs, each ROW_DEPTH × DATA_WIDTH.
    //   - All sub-SRAMs in a bank share the same row address.
    //   - Write: only the sub-SRAM selected by sub-index is written.
    //   - Read:  all sub-SRAMs are read; output is muxed by pipelined sub-index.
    // =========================================================================

    // Split write addresses once per bank
    tid_addr_t [NUM_PORTS-1:0] wr_addr_split;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_wr_split
            assign wr_addr_split[i] = split_tid(rf_wr_addr[i*ADDR_WIDTH +: ADDR_WIDTH]);
        end
    endgenerate

    // Split read addresses once per bank
    tid_addr_t [NUM_PORTS-1:0] rd_addr_split;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_rd_split
            assign rd_addr_split[i] = split_tid(rf_rd_addr[i*ADDR_WIDTH +: ADDR_WIDTH]);
        end
    endgenerate

    // Pipeline read sub-index (bsg_mem_1r1w_sync has 1-cycle read latency)
    logic [NUM_PORTS-1:0][SUB_IDX_WIDTH-1:0] rd_sub_idx_r;
    always_ff @(posedge clk_i) begin
        for (int k = 0; k < NUM_PORTS; k++)
            rd_sub_idx_r[k] <= rd_addr_split[k].sub;
    end

    // Sub-SRAM read data (before mux)
    logic [NUM_PORTS-1:0][REGS_PER_ROW-1:0][DATA_WIDTH-1:0] sub_rd_data;

    // Instantiate sub-SRAMs: NUM_PORTS banks × REGS_PER_ROW sub-SRAMs each
    genvar j;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_bank
            for (j = 0; j < REGS_PER_ROW; j++) begin : gen_sub
                bsg_mem_1r1w_sync #(
                      .width_p(DATA_WIDTH)
                    , .els_p(ROW_DEPTH)
                    , .read_write_same_addr_p(1)
                ) u_sub_ram (
                      .clk_i   (clk_i)
                    , .reset_i (1'b0)
                    , .w_v_i   (rf_wr_en[i] & (wr_addr_split[i].sub == SUB_IDX_WIDTH'(j)))
                    , .w_addr_i(wr_addr_split[i].row)
                    , .w_data_i(rf_wr_data[i*DATA_WIDTH +: DATA_WIDTH])
                    , .r_v_i   (1'b1)
                    , .r_addr_i(rd_addr_split[i].row)
                    , .r_data_o(sub_rd_data[i][j])
                );
            end
        end
    endgenerate

    // Mux read data by pipelined sub-index
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_rd_mux
            assign rd_data_o[i*DATA_WIDTH +: DATA_WIDTH] = sub_rd_data[i][rd_sub_idx_r[i]];
        end
    endgenerate

    // =========================================================================
    // TID pipeline
    // =========================================================================
    always_ff @(posedge clk_i) begin
        if (reset_i)
            tid_o <= '0;
        else
            tid_o <= rd_tid_i;
    end

endmodule
