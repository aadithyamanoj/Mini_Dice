module dice_cgra_rf
  import dice_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic reset_i,
    input logic en_i,

    input logic [DICE_MEM_DATA_WIDTH-1:0] cm0_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm0_chunk_en_i,
    input logic [DICE_MEM_DATA_WIDTH-1:0] cm1_data_i,
    input  logic [((DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                    / DICE_MEM_DATA_WIDTH)-1:0] cm1_chunk_en_i,
    input logic v_i,
    input logic bank_i,
    output logic ready_o,
    output logic busy_o,
    output logic [1:0] bank_valid_o,
    output logic prog_dout_o,
    output logic prog_we_o,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX1_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX2_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX3_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX5_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX6_i,
    input logic [DICE_REG_DATA_WIDTH-1:0] csrX7_i,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_data_o_0,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_addr_o_0,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_data_o_1,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_addr_o_1,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_data_o_2,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_addr_o_2,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_data_o_3,
    output logic [DICE_REG_DATA_WIDTH-1:0] mem_addr_o_3,
    output logic mem_valid_o,
    output logic [DICE_TID_WIDTH-1:0] cgra_tid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0] cgra_e_block_id_o,
    output logic [DICE_NUM_MAX_THREADS_PER_CORE*DICE_NUM_PRED-1:0] pred_all_o,
    output logic [DICE_NUM_BANKS-1:0] ldst_pop_o,
    output logic [DICE_NUM_BANKS-1:0][DICE_EBLOCK_ID_WIDTH-1:0] ldst_pop_e_block_id_o,
    output logic ldst_special_pop_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0] ldst_special_pop_e_block_id_o,
    output logic ldst_special_ready_o,
    output logic [NUM_MEM_PORTS-1:0] mem_port_valid_o,
    output logic [NUM_MEM_PORTS-1:0] mem_port_op_o,
    input logic [NUM_MEM_PORTS-1:0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs_i,
    input logic [$clog2(NUM_MEM_PORTS+1)-1:0] num_stores_i,
    input logic [7:0] latency_i,

    input  logic                                             rd_tid_valid_i,
    output logic                                             rd_tid_ready_o,
    // input  logic                                                 rd_en_i,
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] rd_tid_i,
    input  logic [                 DICE_EBLOCK_ID_WIDTH-1:0] e_block_id_i,
    input  logic [                      DICE_TOTAL_REGS-1:0] rd_bitmap_i,
    input  logic [                      DICE_TOTAL_REGS-1:0] wr_bitmap_i,
    // output logic                                                 rf_rd_valid_o,

    input  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i,
    input  logic                           ldst_valid_i,
    output logic [     DICE_NUM_BANKS-1:0] ldst_ready_o
);

  logic rf_rd_valid_lo;

  localparam int NUM_BANKS = DICE_NUM_BANKS;
  localparam int NUM_CONST = DICE_NUM_CONST;
  localparam int NUM_PRED = DICE_NUM_PRED;
  localparam int TOTAL_REGS = DICE_TOTAL_REGS;
  localparam int DATA_WIDTH = DICE_REG_DATA_WIDTH;
  localparam int SHIFT_LAT_W = $clog2(128);

  logic [(NUM_BANKS+NUM_CONST)*DATA_WIDTH-1:0] rf_rd_data_lo;
  logic [NUM_PRED-1:0] pred_lo;
  logic [DICE_NUM_MAX_THREADS_PER_CORE*NUM_PRED-1:0] pred_all_lo;
  logic [NUM_BANKS-1:0] ldst_pop_lo;
  logic [NUM_BANKS-1:0][DICE_EBLOCK_ID_WIDTH-1:0] ldst_pop_e_block_id_lo;
  logic ldst_special_pop_lo;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] ldst_special_pop_e_block_id_lo;
  logic [NUM_BANKS-1:0] ldst_ready_lo;
  logic ldst_special_ready_lo;
  logic [(NUM_BANKS+NUM_CONST)*DATA_WIDTH-1:0] rf_launch_data_lo;
  logic [NUM_PRED-1:0] pred_launch_lo;

  logic [DATA_WIDTH-1:0] cgra_ext_data_o[0:15];
  logic cgra_ext_pred_o[0:1];
  logic [((NUM_BANKS+NUM_PRED+1)*DATA_WIDTH)-1:0] cgra_data_li;
  logic [TOTAL_REGS-1:0] cgra_wr_bitmap_li;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] cgra_tid_li;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] cgra_tid_lo;
  logic [DATA_WIDTH-1:0] regS_i_0_li;
  logic [TOTAL_REGS-1:0] wr_bitmap_reg_li;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_id_li;
  logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_id_lo;
  logic [NUM_MEM_PORTS-1:0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs_lo;
  logic [$clog2(NUM_MEM_PORTS+1)-1:0] num_stores_lo;
  logic [NUM_MEM_PORTS-1:0] mem_port_valid_li;
  logic [NUM_MEM_PORTS-1:0] mem_port_valid_lo;
  logic [NUM_MEM_PORTS-1:0] mem_port_op_li;
  logic [NUM_MEM_PORTS-1:0] mem_port_op_lo;
  logic cgra_valid_lo;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      rf_launch_data_lo <= '0;
      pred_launch_lo <= '0;
    end else if (rf_rd_valid_lo) begin
      rf_launch_data_lo <= rf_rd_data_lo;
      pred_launch_lo <= pred_lo;
    end
  end

  always_comb begin
    cgra_data_li = '0;

    for (int j = 0; j < NUM_BANKS; j++) begin
      cgra_data_li[j*DATA_WIDTH+:DATA_WIDTH] = cgra_ext_data_o[j];
    end

    cgra_data_li[NUM_BANKS*DATA_WIDTH+:DATA_WIDTH] = cgra_ext_data_o[8];
    cgra_data_li[(NUM_BANKS+1)*DATA_WIDTH+:DATA_WIDTH] = {
      {(DATA_WIDTH - 1) {1'b0}}, cgra_ext_pred_o[0]
    };
    cgra_data_li[(NUM_BANKS+2)*DATA_WIDTH+:DATA_WIDTH] = {
      {(DATA_WIDTH - 1) {1'b0}}, cgra_ext_pred_o[1]
    };
  end

  assign regS_i_0_li = {{(DATA_WIDTH - DICE_TID_WIDTH) {1'b0}}, cgra_tid_li};

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
      .ext_data_i_0(rf_launch_data_lo[0*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_1(rf_launch_data_lo[1*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_2(rf_launch_data_lo[2*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_3(rf_launch_data_lo[3*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_4(rf_launch_data_lo[4*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_5(rf_launch_data_lo[5*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_6(rf_launch_data_lo[6*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_7(rf_launch_data_lo[7*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_8(rf_launch_data_lo[8*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_9(rf_launch_data_lo[9*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_10(rf_launch_data_lo[10*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_11(rf_launch_data_lo[11*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_12(rf_launch_data_lo[12*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_13(rf_launch_data_lo[13*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_14(rf_launch_data_lo[14*DATA_WIDTH+:DATA_WIDTH]),
      .ext_data_i_15(rf_launch_data_lo[15*DATA_WIDTH+:DATA_WIDTH]),
      .csrX_i_0(csrX0_i),
      .csrX_i_1(csrX1_i),
      .csrX_i_2(csrX2_i),
      .csrX_i_3(csrX3_i),
      .csrX_i_4(csrX4_i),
      .csrX_i_5(csrX5_i),
      .csrX_i_6(csrX6_i),
      .csrX_i_7(csrX7_i),
      .regS_i_0(regS_i_0_li),
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
      .ext_pred_i_0(pred_launch_lo[0]),
      .ext_pred_i_1(pred_launch_lo[1]),
      .ext_pred_o_0(cgra_ext_pred_o[0]),
      .ext_pred_o_1(cgra_ext_pred_o[1]),
      .mem_data_o_0(mem_data_o_0),
      .mem_addr_o_0(mem_addr_o_0),
      .mem_data_o_1(mem_data_o_1),
      .mem_addr_o_1(mem_addr_o_1),
      .mem_data_o_2(mem_data_o_2),
      .mem_addr_o_2(mem_addr_o_2),
      .mem_data_o_3(mem_data_o_3),
      .mem_addr_o_3(mem_addr_o_3)
  );

  wire [SHIFT_LAT_W-1:0] cgra_lat = latency_i + 1;
  assign mem_port_valid_li = gen_mem_port_valid(ld_dest_regs_lo, num_stores_lo);
  assign mem_port_op_li    = gen_mem_port_op(ld_dest_regs_lo, num_stores_lo);

  shift_reg #(
        .WIDTH         (DICE_TID_WIDTH)
      , .MAX_PIPE_STAGE(128)
  ) TID_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(cgra_tid_li)
      , .out_data(cgra_tid_lo)
  );

  shift_reg #(
        .WIDTH         (DICE_TOTAL_REGS)
      , .MAX_PIPE_STAGE(128)
  ) WB_MAP_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(wr_bitmap_reg_li)
      , .out_data(cgra_wr_bitmap_li)
  );

  shift_reg #(
        .WIDTH         (DICE_EBLOCK_ID_WIDTH)
      , .MAX_PIPE_STAGE(128)
  ) EBLOCK_ID_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(e_block_id_li)
      , .out_data(e_block_id_lo)
  );

  shift_reg #(
        .WIDTH         (NUM_MEM_PORTS)
      , .MAX_PIPE_STAGE(128)
  ) LDST_PORT_VALID_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(rf_rd_valid_lo ? mem_port_valid_li : '0)
      , .out_data(mem_port_valid_lo)
  );

  shift_reg #(
        .WIDTH         (NUM_MEM_PORTS)
      , .MAX_PIPE_STAGE(128)
  ) LDST_PORT_OP_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(rf_rd_valid_lo ? mem_port_op_li : '0)
      , .out_data(mem_port_op_lo)
  );

  shift_reg #(
        .WIDTH         (1)
      , .MAX_PIPE_STAGE(128)
  ) VALID_SHIFT (
      .clk_i(clk_i)
      , .reset_i(reset_i)
      , .latency(cgra_lat)
      , .in_data(rf_rd_valid_lo)
      , .out_data(cgra_valid_lo)
  );

  dice_rf_ctrl rf_ctrl_inst (
      .clk_i(clk_i),
      .reset_i(reset_i),
      .rd_tid_valid_i(rd_tid_valid_i),
      .rd_tid_ready_o(rd_tid_ready_o),
      // .rd_en_i(rd_en_i),
      .rd_tid_i(rd_tid_i),
      .e_block_id_i(e_block_id_i),
      .rd_bitmap_i(rd_bitmap_i),
      .wr_bitmap_i(wr_bitmap_i),
      .ld_dest_regs_i(ld_dest_regs_i),
      .num_stores_i(num_stores_i),
      .rd_data_o(rf_rd_data_lo),
      .rf_rd_valid_o(rf_rd_valid_lo),
      .tid_o(cgra_tid_li),
      .e_block_id_o(e_block_id_li),
      .wr_bitmap_o(wr_bitmap_reg_li),
      .ld_dest_regs_o(ld_dest_regs_lo),
      .num_stores_o(num_stores_lo),
      .pred_o(pred_lo),
      .pred_all_o(pred_all_lo),
      .ldst_pop_o(ldst_pop_lo),
      .ldst_pop_e_block_id_o(ldst_pop_e_block_id_lo),
      .ldst_special_pop_o(ldst_special_pop_lo),
      .ldst_special_pop_e_block_id_o(ldst_special_pop_e_block_id_lo),
      .ldst_special_ready_o(ldst_special_ready_lo),
      .cgra_tid_i(cgra_tid_lo),
      .cgra_data_i(cgra_data_li),
      .cgra_wr_bitmap_i(cgra_wr_bitmap_li),
      .cgra_valid_i(cgra_valid_lo),
      .ldst_wr_i(ldst_wr_i),
      .ldst_valid_i(ldst_valid_i),
      .ldst_ready_o(ldst_ready_lo)
  );
  assign mem_valid_o = cgra_valid_lo;
  assign cgra_tid_o = cgra_tid_lo;
  assign cgra_e_block_id_o = e_block_id_lo;
  assign pred_all_o = pred_all_lo;
  assign ldst_pop_o = ldst_pop_lo;
  assign ldst_pop_e_block_id_o = ldst_pop_e_block_id_lo;
  assign ldst_special_pop_o = ldst_special_pop_lo;
  assign ldst_special_pop_e_block_id_o = ldst_special_pop_e_block_id_lo;
  assign ldst_ready_o = ldst_ready_lo;
  assign ldst_special_ready_o = ldst_special_ready_lo;
  assign mem_port_valid_o = mem_port_valid_lo & {NUM_MEM_PORTS{cgra_valid_lo}};
  assign mem_port_op_o    = mem_port_op_lo & {NUM_MEM_PORTS{cgra_valid_lo}};


endmodule
