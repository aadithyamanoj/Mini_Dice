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
) (
      input logic clk_i
    , input logic reset_i

    // Read Interface
    , input  logic rd_tid_valid_i
    , output logic rd_tid_ready_o

    // , input logic                             rd_en_i
    , input  logic [                       TID_WIDTH-1:0]                          rd_tid_i
    , input  logic [                      TOTAL_REGS-1:0]                          rd_bitmap_i
    , input  logic [                      TOTAL_REGS-1:0]                          wr_bitmap_i
    , input  logic [           $clog2(NUM_MEM_PORTS-1):0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs_i
    , input  logic [           $clog2(NUM_MEM_PORTS-1):0]                          num_stores_i
    , output logic [(NUM_PORTS+NUM_CONST)*DATA_WIDTH-1:0]                          rd_data_o
    , output logic                                                                 rf_rd_valid_o
    , output logic [                       TID_WIDTH-1:0]                          tid_o
    , output logic [                      TOTAL_REGS-1:0]                          wr_bitmap_o
    , output logic [           $clog2(NUM_MEM_PORTS-1):0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs_o
    , output logic [           $clog2(NUM_MEM_PORTS-1):0]                          num_stores_o

    // Predicate outputs
    , output logic [NUM_PRED-1:0]         pred_o
    , output logic [NUM_TID*NUM_PRED-1:0] pred_all_o

    // Write Interface — CGRA
    , input logic [                          TID_WIDTH-1:0] cgra_tid_i
    , input logic [((NUM_PORTS+NUM_PRED+1)*DATA_WIDTH)-1:0] cgra_data_i
    , input logic [                         TOTAL_REGS-1:0] cgra_wr_bitmap_i
    , input logic                                           cgra_valid_i

    // Write Interface — LDST
    , input  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_i
    , input  logic                           ldst_valid_i
    , output logic                           ldst_ready_o
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

  // GPR portion of the bitmap (no swizzling)
  logic [NUM_PORTS-1:0] cgra_shifted_bitmap;
  assign cgra_shifted_bitmap = cgra_wr_bitmap_i[NUM_PORTS-1:0];

  genvar i;
  generate
    for (i = 0; i < NUM_PORTS; i++) begin
      assign cgra_wr_li[i].data = cgra_data_i[i*DATA_WIDTH+:DATA_WIDTH];
      assign cgra_wr_li[i].mask = cgra_shifted_bitmap[i];
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
  logic ldst_const_valid;
  logic ldst_pred_valid;
  logic ldst_special_valid;

  assign ldst_gpr_valid = ldst_valid_i && (|ldst_convert.wr_bitmap[NUM_PORTS-1:0]);
  assign ldst_const_valid = ldst_valid_i && (|ldst_convert.wr_bitmap[NUM_PORTS+:NUM_CONST]);
  assign ldst_pred_valid = ldst_valid_i && (|ldst_convert.wr_bitmap[NUM_PORTS+NUM_CONST+:NUM_PRED]);
  assign ldst_special_valid = ldst_const_valid || ldst_pred_valid;

  generate
    for (i = 0; i < NUM_PORTS; i++) begin
      dice_wr_ctrl_bank #(
          .WIDTH(DATA_WIDTH)
          , .DEPTH(DEPTH)
          , .ADDR_WIDTH(ADDR_WIDTH)
          , .BUF_DEPTH(BUF_DEPTH)
      ) u_wr_ctrl (
            .clk_i  (clk_i)
          , .reset_i(reset_i)

          , .cgra_wr_i(cgra_wr_li[i])
          , .cgra_valid_i(cgra_valid_i)
          , .cgra_ready_o()

          , .wr_ldst_i(ldst_wr_li[i])
          , .ldst_valid_i(ldst_gpr_valid)

          , .stall_o(stall_o[i])

          , .ws_o  (rf_wr_addr[i*ADDR_WIDTH+:ADDR_WIDTH])
          , .data_o(rf_wr_data[i*DATA_WIDTH+:DATA_WIDTH])
          , .we_o  (rf_wr_en[i])
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
      cgra_special.const_mask[j] = cgra_wr_bitmap_i[NUM_PORTS+j];
      cgra_special.const_data[j*DATA_WIDTH +: DATA_WIDTH] =
                cgra_data_i[NUM_PORTS*DATA_WIDTH +: DATA_WIDTH];
    end
    for (int j = 0; j < NUM_PRED; j++) begin
      cgra_special.pred_mask[j] = cgra_wr_bitmap_i[NUM_PORTS+NUM_CONST+j];
      cgra_special.pred_data[j] = cgra_data_i[(NUM_PORTS+1+j)*DATA_WIDTH];
    end
  end

  // LDST special regs command from cache response
  assign ldst_special_in = assemble_special_wr(ldst_convert);

  // Extract TID for per-TID pred writes (single coalesced command only)
  logic [TID_WIDTH-1:0] ldst_special_tid_in;

  assign ldst_special_tid_in = ldst_convert.tid;

  // FIFO buffer for LDST special writes (widened to include TID for pred)
  localparam int SPECIAL_ENTRY_WIDTH = $bits(special_regs_cmd) + TID_WIDTH;
  logic special_fifo_ready, special_fifo_valid;
  logic pop_special;
  logic [SPECIAL_ENTRY_WIDTH-1:0] special_fifo_data;

  bsg_fifo_1r1w_small #(
        .width_p(SPECIAL_ENTRY_WIDTH)
      , .els_p  (BUF_DEPTH)
  ) u_special_fifo (
        .clk_i  (clk_i)
      , .reset_i(reset_i)
      , .v_i    (ldst_special_valid)
      , .ready_o(special_fifo_ready)
      , .data_i ({ldst_special_in, ldst_special_tid_in})
      , .v_o    (special_fifo_valid)
      , .yumi_i (pop_special)
      , .data_o (special_fifo_data)
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
          const_regs[j] <= special_cmd.const_data[j*DATA_WIDTH+:DATA_WIDTH];
      end
    end
  end

  // Const read: registered to match 1-cycle GPR read latency
  logic [NUM_CONST-1:0][DATA_WIDTH-1:0] const_rd_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) const_rd_r <= '0;
    else if (rd_tid_valid_i) const_rd_r <= const_regs;
  end

  generate
    for (i = 0; i < NUM_CONST; i++) begin : gen_const_rd
      assign rd_data_o[(NUM_PORTS+i)*DATA_WIDTH+:DATA_WIDTH] = const_rd_r[i];
    end
  endgenerate

  // =========================================================================
  // Predicate registers — NUM_PRED banks × NUM_TID entries (1 bit each)
  // =========================================================================
  logic [NUM_TID-1:0][NUM_PRED-1:0] pred_regs;

  logic [TID_WIDTH-1:0] rd_tid_r;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      pred_regs <= '0;
    end else if (special_wr_valid) begin
      for (int j = 0; j < NUM_PRED; j++) begin
        if (special_cmd.pred_mask[j]) pred_regs[special_tid][j] <= special_cmd.pred_data[j];
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) rd_tid_r <= 0;
    else if (rd_tid_valid_i) rd_tid_r <= rd_tid_i;
  end

  // Predicate outputs. The flattened ordering is t0p0, t0p1, ..., t1p0, ...
  assign pred_o = pred_regs[rd_tid_r];
  assign pred_all_o = pred_regs;

  // =========================================================================
  // GPR read path — only pass GPR portion of bitmap to read_org
  // =========================================================================
  dice_read_org #(
      .NUM_PORTS(NUM_PORTS)
      , .DATA_WIDTH(DATA_WIDTH)
      , .NUM_TID(NUM_TID)
      , .TID_WIDTH(TID_WIDTH)
      , .DEPTH(DEPTH)
      , .ADDR_WIDTH(ADDR_WIDTH)
  ) read_org (
        .clk_i  (clk_i)
      , .reset_i(reset_i)

      , .rd_tid_valid_i(rd_tid_valid_i)
      , .rd_tid_ready_o(rd_tid_ready_o)

      // , .rd_en_i (rd_en_i)
      , .rd_tid_i(rd_tid_i)
      , .rd_bitmap_i(rd_bitmap_i[NUM_PORTS-1:0])

      , .rd_sel_o(rf_rd_addr)
      , .rd_en_o(rf_rd_en)
      , .rd_valid_o(rf_rd_valid_o)
  );

  dice_register_file gp_registers (
      .clk(clk_i)

      , .rd_en  (rf_rd_en)
      , .rd_addr(rf_rd_addr)
      , .rd_data(rd_data_o[NUM_PORTS*DATA_WIDTH-1:0])

      , .wr_en  (rf_wr_en)
      , .wr_addr(rf_wr_addr)
      , .wr_data(rf_wr_data)
  );

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      tid_o <= '0;
      wr_bitmap_o <= '0;
      ld_dest_regs_o <= '0;
      num_stores_o <= '0;
    end else if (rd_tid_valid_i) begin
      tid_o <= rd_tid_i;
      wr_bitmap_o <= wr_bitmap_i;
      ld_dest_regs_o <= ld_dest_regs_i;
      num_stores_o <= num_stores_i;
    end
  end




endmodule
