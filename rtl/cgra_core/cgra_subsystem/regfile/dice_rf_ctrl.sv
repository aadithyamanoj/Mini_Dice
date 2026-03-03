`include "DE_pkg.sv"
`include "dice_pkg.sv"



module dice_rf_ctrl

import DE_pkg::*;
import dice_pkg::*;

#(
    parameter int NUM_PORTS = DICE_NUM_BANKS,
    parameter int DATA_WIDTH = DICE_REG_DATA_WIDTH,
    parameter int NUM_TID = DICE_NUM_MAX_THREADS_PER_CORE,
    parameter int TID_WIDTH = $clog2(NUM_TID),
    parameter int DEPTH = DICE_REGS_PER_BANK,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int NUM_CONST = DICE_NUM_CONST,
    parameter int NUM_PRED = DICE_NUM_PRED,
    parameter int TOTAL_REGS = DICE_TOTAL_REGS,
    parameter int BUF_DEPTH = LDST_BUF_DEPTH
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

    // Predicate output — always valid, 1 bit per predicate
    , output logic [NUM_PRED-1:0]             pred_o

    // Write Interface — CGRA
    , input logic [TID_WIDTH-1:0]               cgra_tid_i
    , input logic [(TOTAL_REGS*DATA_WIDTH)-1:0] cgra_data_i
    , input logic [TOTAL_REGS-1:0]              wr_bitmap_i
    , input logic                               cgra_valid_i

    // Write Interface — LDST
    , input logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i
    , input logic                           ldst_valid_i
    , output logic                          ldst_ready_o
);

    // =========================================================================
    // GPR bank signals
    // =========================================================================
    logic [NUM_PORTS-1:0] rf_rd_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_rd_addr;

    logic [NUM_PORTS-1:0]    rf_wr_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_wr_addr;
    logic [NUM_PORTS*DATA_WIDTH-1:0] rf_wr_data;

    logic [NUM_PORTS-1:0] stall_o;

    logic special_fifo_full;
    

    // =========================================================================
    // GPR write path (regs 0 .. NUM_PORTS-1)
    // =========================================================================
    reg_wr_cmd cgra_wr_li [NUM_PORTS-1:0];

    // Shift only the GPR portion of the bitmap
    logic [NUM_PORTS-1:0] cgra_shifted_bitmap;
    assign cgra_shifted_bitmap = shift_bitmap(wr_bitmap_i[NUM_PORTS-1:0], cgra_tid_i);

    genvar i;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin
            assign cgra_wr_li[i].data = cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH];
            assign cgra_wr_li[i].mask = cgra_shifted_bitmap[i];
            assign cgra_wr_li[i].tid = cgra_tid_i;
        end
    endgenerate

    reg_wr_cmd [NUM_PORTS-1:0] ldst_wr_li;
    cache_wr_cmd ldst_convert;

    assign ldst_convert = ldst_wr_i;
    assign ldst_wr_li = unpack_ldsr_wr(assemble_ldst_wr(ldst_convert));

    // =========================================================================
    // LDST target decode — GPR vs special (const/pred)
    // =========================================================================
    logic ldst_gpr_valid;
    logic ldst_special_valid;

    assign ldst_gpr_valid     = ldst_valid_i
                                && (ldst_convert.outcmd_ld_dest_reg < DICE_REG_ADDR_WIDTH'(NUM_PORTS));
    assign ldst_special_valid = ldst_valid_i
                                && (ldst_convert.outcmd_ld_dest_reg >= DICE_REG_ADDR_WIDTH'(NUM_PORTS));

    generate
        for (i = 0; i < NUM_PORTS; i++) begin
            dice_wr_ctrl_bank#
            (
                  .WIDTH(DATA_WIDTH)
                , .DEPTH (DEPTH)
                , .ADDR_WIDTH (ADDR_WIDTH)
                , .BUF_DEPTH (BUF_DEPTH)
            ) u_wr_ctrl (
                .clk_i (clk_i)
                , .reset_i (reset_i)

                , .cgra_wr_i (cgra_wr_li[i])
                , .cgra_valid_i (cgra_valid_i)
                , .cgra_ready_o ()

                , .wr_ldst_i (ldst_wr_li[i])
                , .ldst_valid_i (ldst_gpr_valid)

                , .stall_o (stall_o[i])

                , .ws_o (rf_wr_addr[i*ADDR_WIDTH +: ADDR_WIDTH])
                , .data_o (rf_wr_data[i*DATA_WIDTH +: DATA_WIDTH])
                , .we_o (rf_wr_en[i])
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
            cgra_special.const_mask[j] = wr_bitmap_i[NUM_PORTS + j];
            cgra_special.const_data[j*DATA_WIDTH +: DATA_WIDTH] =
                cgra_data_i[(NUM_PORTS + j)*DATA_WIDTH +: DATA_WIDTH];
        end
        for (int j = 0; j < NUM_PRED; j++) begin
            cgra_special.pred_mask[j] = wr_bitmap_i[NUM_PORTS + NUM_CONST + j];
            cgra_special.pred_data[j] = cgra_data_i[(NUM_PORTS + NUM_CONST + j)*DATA_WIDTH];
        end
    end

    // LDST special regs command from cache response
    assign ldst_special_in = assemble_special_wr(ldst_convert);

    // FIFO buffer for LDST special writes
    logic special_fifo_ready, special_fifo_valid;
    logic pop_special;
    logic [$bits(special_regs_cmd)-1:0] special_fifo_data;

    bsg_fifo_1r1w_small #(
          .width_p($bits(special_regs_cmd))
        , .els_p(BUF_DEPTH)
    ) u_special_fifo (
          .clk_i   (clk_i)
        , .reset_i (reset_i)
        , .v_i     (ldst_special_valid)
        , .ready_o (special_fifo_ready)
        , .data_i  (ldst_special_in)
        , .v_o     (special_fifo_valid)
        , .yumi_i  (pop_special)
        , .data_o  (special_fifo_data)
    );

    assign ldst_special_wb = special_fifo_data;

    // Arbitration: CGRA has priority over buffered LDST
    assign pop_special = !cgra_valid_i && special_fifo_valid;
    assign special_cmd = cgra_valid_i ? cgra_special : ldst_special_wb;

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

    // Const read: wire flip-flop outputs to rd_data_o positions [NUM_PORTS .. NUM_PORTS+NUM_CONST-1]
    generate
        for (i = 0; i < NUM_CONST; i++) begin : gen_const_rd
            assign rd_data_o[(NUM_PORTS + i)*DATA_WIDTH +: DATA_WIDTH] = const_regs[i];
        end
    endgenerate

    // =========================================================================
    // Predicate registers (1 bit each, shared across all threads)
    // =========================================================================
    logic [NUM_PRED-1:0] pred_regs;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            pred_regs <= '0;
        end else if (special_wr_valid) begin
            for (int j = 0; j < NUM_PRED; j++) begin
                if (special_cmd.pred_mask[j])
                    pred_regs[j] <= special_cmd.pred_data[j];
            end
        end
    end

    // Predicate output — continuously driven
    assign pred_o = pred_regs;

    // =========================================================================
    // GPR read path — only pass GPR portion of bitmap to read_org
    // =========================================================================
    dice_read_org#
    (
        .NUM_PORTS (NUM_PORTS)
        , .DATA_WIDTH (DATA_WIDTH)
        , .NUM_TID (NUM_TID)
        , .TID_WIDTH (TID_WIDTH)
        , .DEPTH (DEPTH)
        , .ADDR_WIDTH (ADDR_WIDTH)
    ) read_org (
        .clk_i (clk_i)
        , .reset_i (reset_i)

        , .rd_tid_valid_i (rd_tid_valid_i)
        , .rd_tid_ready_o (rd_tid_ready_o)

        , .rd_en_i (rd_en_i)
        , .rd_tid_i (rd_tid_i)
        , .rd_bitmap_i (rd_bitmap_i[NUM_PORTS-1:0])

        , .rd_sel_o (rf_rd_addr)
        , .rd_en_o (rf_rd_en)
        , .rd_valid_o (rf_rd_valid_o)
    );

    dice_register_file
     registers (
          .clk (clk_i)

        , .rd_addr (rf_rd_addr)
        , .rd_data (rd_data_o[NUM_PORTS*DATA_WIDTH-1:0])

        , .wr_en   (rf_wr_en)
        , .wr_addr (rf_wr_addr)
        , .wr_data (rf_wr_data)
    );

endmodule
