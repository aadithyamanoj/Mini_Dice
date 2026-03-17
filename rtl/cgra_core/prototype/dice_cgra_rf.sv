module dice_cgra_rf
  import dice_pkg::*;
  import DE_pkg::*;
(
    input  logic clk_i,
    input  logic reset_i,
    input  logic en_i,

    input  logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm0_chunk_en_i,
    input  logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm1_chunk_en_i,
    input  logic v_i,
    input  logic bank_i,
    output logic ready_o,
    output logic busy_o,
    output logic [1:0] bank_valid_o,
    output logic prog_dout_o,
    output logic prog_we_o,
    output logic [DICE_REG_DATA_WIDTH-1:0]                         mem_data_o,
    output logic [DICE_REG_DATA_WIDTH-1:0]                         mem_addr_o,
    output logic                                                   mem_valid_o,
    input  logic [7:0]                                             latency_i,

    input  logic                                                 rd_tid_valid_i,
    output logic                                                 rd_tid_ready_o,
    input  logic                                                 rd_en_i,
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]     rd_tid_i,
    input  logic [DICE_TOTAL_REGS-1:0]                           rd_bitmap_i,
    input  logic [DICE_TOTAL_REGS-1:0]                           wr_bitmap_i,
    output logic                                                 rf_rd_valid_o,

    input  logic [$bits(cache_wr_cmd)-1:0]                       ldst_wr_i,
    input  logic                                                 ldst_valid_i,
    output logic                                                 ldst_ready_o
);

  localparam int NUM_BANKS = DICE_NUM_BANKS;
  localparam int NUM_CONST = DICE_NUM_CONST;
  localparam int NUM_PRED = DICE_NUM_PRED;
  localparam int TOTAL_REGS = DICE_TOTAL_REGS;
  localparam int DATA_WIDTH = DICE_REG_DATA_WIDTH;
  localparam int SHIFT_LAT_W = $clog2(128);

  logic [(NUM_BANKS+NUM_CONST)*DATA_WIDTH-1:0] rf_rd_data_lo;
  logic [NUM_PRED-1:0]                         pred_lo;

  logic [7:0] cgra_ext_data_o [0:15];
  logic       cgra_ext_pred_o [0:1];
  logic [((NUM_BANKS+NUM_PRED+1)*DATA_WIDTH)-1:0] cgra_data_li;
  logic [TOTAL_REGS-1:0]                           cgra_wr_bitmap_li;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] cgra_tid_li;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] cgra_tid_lo;
  logic [TOTAL_REGS-1:0]                            wr_bitmap_reg_li;
  logic                                             cgra_valid_lo;

  always_comb begin
    cgra_data_li = '0;

    for (int j = 0; j < NUM_BANKS; j++) begin
      cgra_data_li[j*DATA_WIDTH +: DATA_WIDTH] = cgra_ext_data_o[j];
    end

    cgra_data_li[NUM_BANKS*DATA_WIDTH +: DATA_WIDTH] = cgra_ext_data_o[8];
    cgra_data_li[(NUM_BANKS + 1)*DATA_WIDTH +: DATA_WIDTH] = {{(DATA_WIDTH-1){1'b0}}, cgra_ext_pred_o[0]};
    cgra_data_li[(NUM_BANKS + 2)*DATA_WIDTH +: DATA_WIDTH] = {{(DATA_WIDTH-1){1'b0}}, cgra_ext_pred_o[1]};
  end

  dice_cgra_subs cgra_subs_inst (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .en_i(en_i),
      .cm0_data_i(cm0_data_i),
      .cm0_chunk_en_i(cm0_chunk_en_i),
      .cm1_data_i(cm1_data_i),
      .cm1_chunk_en_i(cm1_chunk_en_i),
      .v_i(v_i),
      .bank_i(bank_i),
      .ready_o(ready_o),
      .busy_o(busy_o),
      .bank_valid_o(bank_valid_o),
      .prog_dout_o(prog_dout_o),
      .prog_we_o(prog_we_o),
      .ext_data_i_0(rf_rd_data_lo[0*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_1(rf_rd_data_lo[1*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_2(rf_rd_data_lo[2*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_3(rf_rd_data_lo[3*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_4(rf_rd_data_lo[4*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_5(rf_rd_data_lo[5*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_6(rf_rd_data_lo[6*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_7(rf_rd_data_lo[7*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_8(rf_rd_data_lo[8*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_9(rf_rd_data_lo[9*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_10(rf_rd_data_lo[10*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_11(rf_rd_data_lo[11*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_12(rf_rd_data_lo[12*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_13(rf_rd_data_lo[13*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_14(rf_rd_data_lo[14*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_i_15(rf_rd_data_lo[15*DATA_WIDTH +: DATA_WIDTH]),
      .ext_data_o_0(cgra_ext_data_o[0]),
      .ext_data_o_1(cgra_ext_data_o[1]),
      .ext_data_o_2(cgra_ext_data_o[2]),
      .ext_data_o_3(cgra_ext_data_o[3]),
      .ext_data_o_4(cgra_ext_data_o[4]),
      .ext_data_o_5(cgra_ext_data_o[5]),
      .ext_data_o_6(cgra_ext_data_o[6]),
      .ext_data_o_7(cgra_ext_data_o[7]),
      .ext_data_o_8(cgra_ext_data_o[8]),
      .ext_data_o_9(cgra_ext_data_o[9]),
      .ext_data_o_10(cgra_ext_data_o[10]),
      .ext_data_o_11(cgra_ext_data_o[11]),
      .ext_data_o_12(cgra_ext_data_o[12]),
      .ext_data_o_13(cgra_ext_data_o[13]),
      .ext_data_o_14(cgra_ext_data_o[14]),
      .ext_data_o_15(cgra_ext_data_o[15]),
      .ext_pred_i_0(pred_lo[0]),
      .ext_pred_i_1(pred_lo[1]),
      .ext_pred_o_0(cgra_ext_pred_o[0]),
      .ext_pred_o_1(cgra_ext_pred_o[1]),
      .mem_data_o(mem_data_o),
      .mem_addr_o(mem_addr_o)
  );

  shift_reg
      #(.WIDTH          (DICE_TID_WIDTH)
       ,.MAX_PIPE_STAGE (128)
      )
      TID_SHIFT
      (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.latency(latency_i[SHIFT_LAT_W-1:0])
      ,.in_data(cgra_tid_li)
      ,.out_data(cgra_tid_lo)
      );

  shift_reg
      #(.WIDTH          (DICE_TOTAL_REGS)
       ,.MAX_PIPE_STAGE (128)
      )
      WB_MAP_SHIFT
      (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.latency(latency_i[SHIFT_LAT_W-1:0])
      ,.in_data(wr_bitmap_reg_li)
      ,.out_data(cgra_wr_bitmap_li)
      );

  shift_reg
      #(.WIDTH          (1)
       ,.MAX_PIPE_STAGE (128)
      )
      VALID_SHIFT
      (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.latency(latency_i[SHIFT_LAT_W-1:0])
      ,.in_data(rf_rd_valid_o)
      ,.out_data(cgra_valid_lo)
      );

  dice_rf_ctrl rf_ctrl_inst (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .rd_tid_valid_i(rd_tid_valid_i),
      .rd_tid_ready_o(rd_tid_ready_o),
      .rd_en_i(rd_en_i),
      .rd_tid_i(rd_tid_i),
      .rd_bitmap_i(rd_bitmap_i),
      .wr_bitmap_i(wr_bitmap_i),
      .rd_data_o(rf_rd_data_lo),
      .rf_rd_valid_o(rf_rd_valid_o),
      .tid_o(cgra_tid_li),
      .wr_bitmap_o(wr_bitmap_reg_li),
      .pred_o(pred_lo),
      .cgra_tid_i(cgra_tid_lo),
      .cgra_data_i(cgra_data_li),
      .cgra_wr_bitmap_i(cgra_wr_bitmap_li),
      .cgra_valid_i(cgra_valid_lo),
      .ldst_wr_i(ldst_wr_i),
      .ldst_valid_i(ldst_valid_i),
      .ldst_ready_o(ldst_ready_o)
  );
  assign mem_valid_o = cgra_valid_lo;

endmodule
