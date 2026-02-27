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
    parameter int NUM_SPECIAL_REG = `DICE_PR_NUM,
    parameter int MAX_CTA_ID = `DICE_MAX_GRID_SIZE,
    parameter int CTA_ID_WIDTH = DICE_CTA_ID_WIDTH,
    parameter int BUF_DEPTH = LDST_BUF_DEPTH
)
(
      input  logic              clk_i
    , input  logic              reset_i

    // Read Input
    // take anywhere from 1 to 4 tids
    // take one bitmap
    // send to a new module called called read_org

    // valid ready for tid and bitmap
    , input logic                             rd_tid_valid_i
    , output logic                            rd_tid_ready_o

    // some signal for unrolling factor to select
    , input logic [1:0]                       rd_unroll_factor_i
    , input logic                             rd_en_i
    , input logic [(4*TID_WIDTH)-1:0]         rd_tid_i
    , input logic [NUM_PORTS-1:0]             rd_bitmap_i
    , output logic [NUM_PORTS*DATA_WIDTH-1:0] rd_data_o
    , output logic                            rf_rd_valid_o
    // TODO: add v_o signal for cgra, so when rf_v_o and disp_v_o, compute 


    // Write Input
    // ldst unit will give me write packets packaged by bank!
    , input logic [(4*TID_WIDTH)-1:0]           cgra_tid_i
    , input logic [(NUM_PORTS*DATA_WIDTH)-1:0]  cgra_data_i
    , input logic [NUM_PORTS-1:0]               wr_bitmap_i
    , input logic                               cgra_valid_i

    , input cache_wr_cmd                    ldst_wr_i
    , input logic                           ldst_valid_i
    , output logic                          ldst_ready_o


    , input logic [NUM_SPECIAL_REG-1:0] clear_i
    // special register input
    , input logic [NUM_SPECIAL_REG-1:0] spec_rd_enable_i
    , input logic [NUM_SPECIAL_REG*4-1:0] spec_reg_sel_i
    , input logic [NUM_SPECIAL_REG*DATA_WIDTH-1:0] const_reg_i
    // tid info
    , input logic [TID_WIDTH-1:0] tid_x_i
    , input logic [TID_WIDTH-1:0] tid_y_i
    , input logic [TID_WIDTH-1:0] tid_z_i
    , input logic [TID_WIDTH-1:0] ntid_x_i
    , input logic [TID_WIDTH-1:0] ntid_y_i
    , input logic [TID_WIDTH-1:0] ntid_z_i
    , input logic [CTA_ID_WIDTH-1:0] ctaid_x_i
    , input logic [CTA_ID_WIDTH-1:0] ctaid_y_i
    , input logic [CTA_ID_WIDTH-1:0] ctaid_z_i
    , input logic [CTA_ID_WIDTH-1:0] nctaid_x_i
    , input logic [CTA_ID_WIDTH-1:0] nctaid_y_i
    , input logic [CTA_ID_WIDTH-1:0] nctaid_z_i
    // output
    , output logic [NUM_SPECIAL_REG*DATA_WIDTH-1:0] spec_reg_out_o
);

    logic [NUM_PORTS-1:0] rf_rd_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_rd_addr;
    logic [NUM_PORTS*DATA_WIDTH-1:0] rf_rd_data;

    // Write port
    logic [NUM_PORTS-1:0]    rf_wr_en;
    logic [NUM_PORTS*ADDR_WIDTH-1:0] rf_wr_addr;
    logic [NUM_PORTS*DATA_WIDTH-1:0] rf_wr_data;


    // wr arbitration signals 
    // logic [NUM_PORTS*7:0] fw_hit_cgra;
    // logic [NUM_PORTS*7:0] fw_hit_ldst;
    // logic [NUM_PORTS*DATA_WIDTH-1:0] fw_data;

    // logic [NUM_PORTS*DICE_TID_WIDTH-1:0] fw_req_i;

    logic [NUM_PORTS-1:0] stall_o;

    assign ldst_ready_o = ~(|stall_o);

    // assign fw_req_i = rf_rd_addr;

    reg_wr_cmd cgra_wr_li [NUM_PORTS-1:0];

    logic [NUM_PORTS-1:0] wr_bitmap_r;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            wr_bitmap_r <= '0;
        end else begin
            wr_bitmap_r <= wr_bitmap_i;
        end
    end


    genvar i;
    generate 
        for (i = 0; i < NUM_PORTS; i++) begin
            assign cgra_wr_li[i].data = cgra_data_i[i*DATA_WIDTH +: DATA_WIDTH];
            assign cgra_wr_li[i].mask = wr_bitmap_r[i];
            // Only assign the lowest TID from the cgra_tid_i bus (corresponds to the lowest bits)
            // no unrolling factor for now
            assign cgra_wr_li[i].tid = cgra_tid_i[0 +: TID_WIDTH];
        end
    endgenerate

    ldst_wr_cmd [NUM_PORTS-1:0] ldst_wr_li;

    assign ldst_wr_li = unpack_ldsr_wr(assemble_ldst_wr(ldst_wr_i));
    
    generate
        for (i = 0;  i < NUM_PORTS; i++) begin
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
                ,.cgra_ready_o ()

                , .wr_ldst_i (ldst_wr_li[i])
                , .ldst_valid_i (ldst_valid_i)

                // , .fw_req_i (fw_req_i[i*DICE_TID_WIDTH +: DICE_TID_WIDTH])

                , .stall_o (stall_o[i])

                // , .fw_hit_cgra_o (fw_hit_cgra[i*8 +: 8])
                // , .fw_hit_ldst_o (fw_hit_ldst[i*8 +: 8])
                // , .fw_data_o (fw_data[i*DATA_WIDTH +: DATA_WIDTH])

                , .ws_o (rf_wr_addr[i*ADDR_WIDTH +: ADDR_WIDTH])
                , .data_o (rf_wr_data[i*DATA_WIDTH +: DATA_WIDTH])
                , .we_o (rf_wr_en[i])
            );

            dice_rd_ctrl_bank#
            (
                .WIDTH (DATA_WIDTH)
                , .DEPTH (DEPTH)
                , .ADDR_WIDTH (ADDR_WIDTH)
            ) w_rd_ctrl (
                .clk_i (clk_i)
                , .reset_i (reset_i)
                , .reg_data_i (rf_rd_data[i*DATA_WIDTH +: DATA_WIDTH])
                // , .fw_data_i (fw_data[i*DATA_WIDTH +: DATA_WIDTH])
                // , .fw_valid_i ('0) // no forwarding for now
                , .data_o (rd_data_o[i*DATA_WIDTH +: DATA_WIDTH])
            );



        end
    endgenerate

    generate 
        for (i = 0; i < NUM_SPECIAL_REG; i++) begin
            dice_special_reg#
            (
                .DATA_WIDTH (DATA_WIDTH)
                ,.NUM_TID (NUM_TID)
                ,.TID_WIDTH (TID_WIDTH)
                ,.MAX_CTA_ID (MAX_CTA_ID)
                ,.CTA_ID_WIDTH (CTA_ID_WIDTH)
            ) u_special_reg (
                .clk_i (clk_i)
                , .reset_i (reset_i)
                , .clear_i (clear_i[i])
                , .rd_en (spec_rd_enable_i[i])
                , .rd_sel (spec_reg_sel_i[i*4 +: 4])
                , .const_data (const_reg_i[i*DATA_WIDTH +: DATA_WIDTH])
                , .tid_x (tid_x_i)
                , .tid_y (tid_y_i)
                , .tid_z (tid_z_i)
                , .ntid_x (ntid_x_i)
                , .ntid_y (ntid_y_i)
                , .ntid_z (ntid_z_i)
                , .ctaid_x (ctaid_x_i)
                , .ctaid_y (ctaid_y_i)
                , .ctaid_z (ctaid_z_i)
                , .nctaid_x (nctaid_x_i)
                , .nctaid_y (nctaid_y_i)
                , .nctaid_z (nctaid_z_i)
                , .out_data (spec_reg_out_o[i*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate


    
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

        , .rd_unroll_factor_i (rd_unroll_factor_i)
        , .rd_en_i (rd_en_i)
        , .rd_tid_i (rd_tid_i)
        , .rd_bitmap_i (rd_bitmap_i)

        , .rd_sel_o (rf_rd_addr)
        , .rd_en_o (rf_rd_en)
        , .rd_valid_o (rf_rd_valid_o)
    );

    

    dice_register_file
     registers (
          .clk (clk_i)

        , .rd_addr (rf_rd_addr)
        , .rd_data (rf_rd_data)

        , .wr_en   (shift_bitmap(rf_wr_en, rf_wr_addr[0 +: TID_WIDTH]))
        , .wr_addr (rf_wr_addr)
        , .wr_data (rf_wr_data)
    );





endmodule
