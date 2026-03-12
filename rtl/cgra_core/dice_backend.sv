
module dice_backend
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // FDR interface (from frontend)
    fdr_if.slave fdr_if_i,

    // North boundary outputs (row = 0, columns 0 / 2 / 4 / 6 / 8)
    output logic [DICE_REG_DATA_WIDTH-1:0] north_0_data_o,
    output logic                           north_0_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] north_2_data_o,
    output logic                           north_2_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] north_4_data_o,
    output logic                           north_4_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] north_6_data_o,
    output logic                           north_6_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] north_8_data_o,
    output logic                           north_8_pred_o,

    // South boundary outputs (row = 8, columns 0 / 2 / 4 / 6 / 8)
    output logic [DICE_REG_DATA_WIDTH-1:0] south_0_data_o,
    output logic                           south_0_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] south_2_data_o,
    output logic                           south_2_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] south_4_data_o,
    output logic                           south_4_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] south_6_data_o,
    output logic                           south_6_pred_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] south_8_data_o,
    output logic                           south_8_pred_o,

    // Memory Response Input (cache_wr_cmd fields)
    input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                            mem_rsp_base_tid_i,
    input  logic [TID_BITMAP_WIDTH-1:0]                                                 mem_rsp_tid_bitmap_i,
    input  logic [DICE_REG_ADDR_WIDTH-1:0]                                              mem_rsp_ld_dest_reg_i,
    input  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]        mem_rsp_address_map_i,
    input  logic [(CACHE_LINE_SIZE*8)-1:0]                                              mem_rsp_data_i,
    input  logic                                                                        mem_rsp_valid_i,

    // Block commit table outputs
    output logic                                    eblock_commit_valid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0]         eblock_commit_id_o,
    input  logic                                    eblock_commit_ready_i,
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     hw_cta_pending_o
);

  // Dispatcher
  logic dispatch_busy;
  logic dispatcher_done;
  logic dispatch_fifo_empty;
  logic [NUM_LANES*DICE_TID_WIDTH-1:0] rd_tid;
  logic [NUM_LANES-1:0] rd_tid_valid;
  logic [DICE_TOTAL_REGS-1:0] full_reg_bitmap_lo;

  // Register File Control
  logic rf_rd_valid_lo;
  logic rf_rd_ready_lo;

  logic [(DICE_NUM_BANKS+DICE_NUM_CONST)*DICE_REG_DATA_WIDTH-1:0] rd_data_lo;
  logic [DICE_NUM_PRED-1:0] pred_lo;

  // Crossbar parameters
  localparam int NUM_PE_PORTS          = 8;                  // number of data inputs and ourputs to CGRA PE array
  localparam int GPR_XBAR_NUM_INPUTS   = DICE_NUM_REGS + DICE_NUM_CONST; // GPRs + const regs
  localparam int GPR_XBAR_NUM_OUTPUTS  = NUM_PE_PORTS;       // PE data input count

  localparam int PRED_XBAR_NUM_INPUTS  = DICE_NUM_PRED;     // predicate regs = 2
  localparam int PRED_XBAR_NUM_OUTPUTS = NUM_PE_PORTS;      // PE pred input count

  // Crossbar -> feed into CGRA PE array inputs
  logic [GPR_XBAR_NUM_OUTPUTS-1:0][DICE_REG_DATA_WIDTH-1:0] gpr_rd_xbar_lo;
  logic [PRED_XBAR_NUM_OUTPUTS-1:0][0:0]                    pred_rd_xbar_lo;
  // CGRA PE array outputs -> write-back crossbar -> register file
  logic [GPR_XBAR_NUM_INPUTS-1:0][DICE_REG_DATA_WIDTH-1:0] gpr_wb_xbar_lo;   
  logic [PRED_XBAR_NUM_INPUTS-1:0][0:0]                    pred_wb_xbar_lo;  

  // Crossbar configuration — sourced from the CGRA bitstream.
  // TODO: drive from bitstream decoder once that path is implemented.
  //       cfg_sel_i layout: bits [(i+1)*SEL_WIDTH-1 : i*SEL_WIDTH] = selector for output i.
  //
  // Input  crossbar: NUM_INPUTS=GPR_XBAR_NUM_INPUTS(16), NUM_OUTPUTS=GPR_XBAR_NUM_OUTPUTS(8)
  //                  SEL_W = clog2(16) = 4  →  cfg_sel width = 8*4 = 32 bits
  // Output crossbar: NUM_INPUTS=GPR_XBAR_NUM_OUTPUTS(8),  NUM_OUTPUTS=GPR_XBAR_NUM_INPUTS(16)
  //                  SEL_W = clog2(8)  = 3  →  cfg_sel width = 16*3 = 48 bits
  logic [GPR_XBAR_NUM_OUTPUTS*($clog2(GPR_XBAR_NUM_INPUTS))-1:0]   gpr_rd_xbar_cfg_sel;
  logic [GPR_XBAR_NUM_INPUTS*($clog2(GPR_XBAR_NUM_OUTPUTS))-1:0]   gpr_wb_xbar_cfg_sel;
  logic [PRED_XBAR_NUM_OUTPUTS*($clog2(PRED_XBAR_NUM_INPUTS))-1:0] pred_rd_xbar_cfg_sel;
  logic [PRED_XBAR_NUM_INPUTS*($clog2(PRED_XBAR_NUM_OUTPUTS))-1:0] pred_wb_xbar_cfg_sel;
  logic                                                              xbar_cfg_load;

  assign gpr_rd_xbar_cfg_sel  = '0; // TODO: connect to bitstream decoder output
  assign pred_rd_xbar_cfg_sel = '0; // TODO: connect to bitstream decoder output
  assign gpr_wb_xbar_cfg_sel  = '0; // TODO: connect to bitstream decoder output
  assign pred_wb_xbar_cfg_sel = '0; // TODO: connect to bitstream decoder output
  assign xbar_cfg_load        = '0; // TODO: pulse when new p-graph bitstream config is ready


  // LDST write interface — pack module inputs into cache_wr_cmd
  cache_wr_cmd                    ldst_cmd;
  logic [$bits(cache_wr_cmd)-1:0] ldst_wr_lo;
  logic                           ldst_valid_lo;
  logic                           ldst_ready_lo;


  logic [DICE_TID_WIDTH-1:0] cgra_tid_li; // out of rf, in to shift reg and cgra

  logic [DICE_TOTAL_REGS-1:0] wb_map_li; // shifted form metadata, goes to rf


  // CGRA write-back wires
  logic                                          cgra_v_lo; // asserted lat cycles after RF read valid
  logic [NUM_PE_PORTS*DICE_REG_DATA_WIDTH-1:0] cgra_gpr_data_lo;
  logic [NUM_PE_PORTS-1:0]                     cgra_pred_data_lo;
  logic [DICE_TID_WIDTH-1:0]                     cgra_tid_lo;

  // Register file writeback from CGRA (after crossbar)
  logic [((DICE_NUM_REGS+DICE_NUM_CONST)+DICE_NUM_PRED)-1:0]  cgra_data_lo; // combined GPR and predicate data
  assign cgra_data_lo = {gpr_wb_xbar_lo, pred_wb_xbar_lo};

  // Block Commit Table
  logic                                    bct_insert_valid;
  logic [DICE_HW_CTA_ID_WIDTH-1:0]        bct_insert_hw_cta_id;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]         bct_insert_e_block_id;
  logic [13:0]                             bct_insert_pending_reads;
  logic [13:0]                             bct_insert_pending_writes;

  logic                                    bct_update_valid;
  logic [DICE_EBLOCK_ID_WIDTH-1:0]         bct_update_e_block_id;
  logic                                    bct_update_is_write;
  logic [2**DICE_HW_CTA_ID_WIDTH-1:0]     bct_update_reduce_count;

  assign fdr_if_i.ready = ~dispatch_busy;

  assign ldst_cmd.outcmd_base_tid    = mem_rsp_base_tid_i;
  assign ldst_cmd.outcmd_tid_bitmap  = mem_rsp_tid_bitmap_i;
  assign ldst_cmd.outcmd_ld_dest_reg = mem_rsp_ld_dest_reg_i;
  assign ldst_cmd.outcmd_address_map = mem_rsp_address_map_i;
  assign ldst_cmd.core_rsp_data      = mem_rsp_data_i;

  assign ldst_wr_lo    = ldst_cmd;
  assign ldst_valid_lo = mem_rsp_valid_i;

  // =========================================================================
  // Dispatcher
  // =========================================================================

  dispatcher u_dispatcher (
      .clk_i(clk_i),
      .rst(rst_i),
      .ld_dest_regs(fdr_if_i.data.metadata.ld_dest_regs),
      .input_register_bitmap(fdr_if_i.data.metadata.in_regs_bitmap),
      .active_mask(fdr_if_i.data.real_active_mask),
      .fetch_done(fdr_if_i.valid),
      .wb_valid(),              // comes from cgra
      .wb_tid_bitmap(),         // comes from cgra
      .dispatch_fifo_pop('1),   // cgra ready
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_tid_o(rd_tid),
      .dispatch_valid_o(rd_tid_valid),
      .full_reg_bitmap_o(full_reg_bitmap_lo),
      .dispatcher_busy(dispatch_busy),
      .dispatcher_done(dispatcher_done)
  );

  // =========================================================================
  // Register File Control
  // =========================================================================

  dice_rf_ctrl u_dice_rf_ctrl (
      .clk_i(clk_i),
      .reset_i(rst_i),

      // Read Interface
      .rd_tid_valid_i(rd_tid_valid),
      .rd_tid_ready_o(rf_rd_ready_lo),
      .rd_en_i(rd_tid_valid),
      .rd_tid_i(rd_tid),
      .rd_bitmap_i(full_reg_bitmap_lo),
      .rd_data_o(rd_data_lo),
      .rf_rd_valid_o(rf_rd_valid_lo),
      .tid_o        (cgra_tid_li),

      // Predicate output
      .pred_o(pred_lo),

      // Write Interface — CGRA
      .cgra_tid_i(cgra_tid_lo),
      .cgra_data_i(cgra_data_lo),
      .wr_bitmap_i(wb_map_li),
      .cgra_valid_i(cgra_v_lo),

      // Write Interface — LDST
      .ldst_wr_i(ldst_wr_lo),
      .ldst_valid_i(ldst_valid_lo),
      .ldst_ready_o(ldst_ready_lo)
  );

    shift_reg
        #(.WIDTH          (DICE_TID_WIDTH)
         ,.MAX_PIPE_STAGE (128) // 
        )
        TID_SHIFT
        (.clk_i(clk_i)
        ,.reset_i(rst_i)   
        
        ,.latency (fdr_if_i.data.metadata.lat) // 

        ,.in_data (cgra_tid_li) // as if it comes out of the cgra
        ,.out_data (cgra_tid_lo)
        );
    
    shift_reg
        #(.WIDTH          (DICE_TOTAL_REGS)
         ,.MAX_PIPE_STAGE (128+1) //
        )
        WB_MAP_SHIFT
        (.clk_i(clk_i)
        ,.reset_i(rst_i)

        ,.latency (fdr_if_i.data.metadata.lat+1) //

        ,.in_data (fdr_if_i.data.metadata.out_regs_bitmap) //straight from metadata
        ,.out_data (wb_map_li) //
        );

  // CGRA valid: asserted `lat` cycles after the RF read produces valid data.
  // Replaces a direct ready signal from mini_dice (which has no such output).
  shift_reg
      #(.WIDTH          (1)
       ,.MAX_PIPE_STAGE (128)
      )
      CGRA_V_SHIFT
      (.clk_i   (clk_i)
      ,.reset_i (rst_i)
      ,.latency (fdr_if_i.data.metadata.lat)
      ,.in_data (rf_rd_valid_lo)   // pulse when RF read data is presented to CGRA
      ,.out_data(cgra_v_lo)        // pulse to RF ctrl to trigger write-back
      );

  // =========================================================================
  // Input Crossbar: register file -> CGRA PE array inputs
  // =========================================================================
  cgra_crossbar #(
      .NUM_INPUTS  (GPR_XBAR_NUM_INPUTS),
      .NUM_OUTPUTS (GPR_XBAR_NUM_OUTPUTS),
      .DATA_WIDTH  (DICE_REG_DATA_WIDTH)
  ) u_gpr_xbar_in (
      .clk_i      (clk_i),
      .rst_i      (rst_i),
      .data_i     (rd_data_lo),       
      .cfg_load_i (xbar_cfg_load),
      .cfg_sel_i  (gpr_rd_xbar_cfg_sel),
      .data_o     (gpr_rd_xbar_lo)
  );

  cgra_crossbar #(
      .NUM_INPUTS  (PRED_XBAR_NUM_INPUTS),
      .NUM_OUTPUTS (PRED_XBAR_NUM_OUTPUTS),
      .DATA_WIDTH  (1)
  ) u_pred_xbar_in (
      .clk_i      (clk_i),
      .rst_i      (rst_i),
      .data_i     (pred_lo),           
      .cfg_load_i (xbar_cfg_load),
      .cfg_sel_i  (pred_rd_xbar_cfg_sel),
      .data_o     (pred_rd_xbar_lo)
  );

  // =========================================================================
  // Output Crossbar: CGRA PE array outputs -> register file
  // =========================================================================
  cgra_crossbar #(
      .NUM_INPUTS  (GPR_XBAR_NUM_OUTPUTS),
      .NUM_OUTPUTS (GPR_XBAR_NUM_INPUTS),
      .DATA_WIDTH  (DICE_REG_DATA_WIDTH)
  ) u_gpr_xbar_out (
      .clk_i      (clk_i),
      .rst_i      (rst_i),
      .data_i     (cgra_gpr_data_lo),
      .cfg_load_i (xbar_cfg_load),
      .cfg_sel_i  (gpr_wb_xbar_cfg_sel),
      .data_o     (gpr_wb_xbar_lo)
  );

  cgra_crossbar #(
      .NUM_INPUTS  (PRED_XBAR_NUM_OUTPUTS),
      .NUM_OUTPUTS (PRED_XBAR_NUM_INPUTS),
      .DATA_WIDTH  (1)
  ) u_pred_xbar_out (
      .clk_i      (clk_i),
      .rst_i      (rst_i),
      .data_i     (cgra_pred_data_lo),
      .cfg_load_i (xbar_cfg_load),
      .cfg_sel_i  (pred_wb_xbar_cfg_sel),
      .data_o     (pred_wb_xbar_lo)
  );

  // =========================================================================
  // CGRA: mini_dice
  // West boundary (sb_*_0 W ports): data input PEs 0-3 / write-back output PEs 4-7
  // East boundary (sb_*_8 E ports): data input PEs 4-7 / write-back output PEs 0-3
  // All diagonal, top, and bottom boundary ports are tied off.
  // =========================================================================
  mini_dice u_mini_dice (
      .clk_i   (clk_i),
      .reset_i (rst_i),
      .en_i    (1'b1),

      // -----------------------------------------------------------------------
      // Top-left corner (sb_0_0): West data in/out + top/diagonal tie-offs
      // -----------------------------------------------------------------------
      .sb_0_0_W_i      (gpr_rd_xbar_lo[0]),
      .sb_0_0_W_o      (cgra_gpr_data_lo[4*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_0_0_pred_W_i (pred_rd_xbar_lo[0]),
      .sb_0_0_pred_W_o (cgra_pred_data_lo[4]),
      .sb_0_0_N_i      ('0), .sb_0_0_N_o      (north_0_data_o),
      .sb_0_0_pred_N_i ('0), .sb_0_0_pred_N_o (north_0_pred_o),
      .sb_0_0_NE_i     ('0), .sb_0_0_NE_o     (),
      .sb_0_0_pred_NE_i('0), .sb_0_0_pred_NE_o(),
      .sb_0_0_NW_i     ('0), .sb_0_0_NW_o     (),
      .sb_0_0_pred_NW_i('0), .sb_0_0_pred_NW_o(),
      .sb_0_0_SW_i     ('0), .sb_0_0_SW_o     (),
      .sb_0_0_pred_SW_i('0), .sb_0_0_pred_SW_o(),

      // -----------------------------------------------------------------------
      // Top boundary (row = 0, col = 2, 4, 6) — tie off
      // -----------------------------------------------------------------------
      .sb_0_2_N_i      ('0), .sb_0_2_N_o      (north_2_data_o),
      .sb_0_2_pred_N_i ('0), .sb_0_2_pred_N_o (north_2_pred_o),
      .sb_0_2_NE_i     ('0), .sb_0_2_NE_o     (),
      .sb_0_2_pred_NE_i('0), .sb_0_2_pred_NE_o(),
      .sb_0_2_NW_i     ('0), .sb_0_2_NW_o     (),
      .sb_0_2_pred_NW_i('0), .sb_0_2_pred_NW_o(),

      .sb_0_4_N_i      ('0), .sb_0_4_N_o      (north_4_data_o),
      .sb_0_4_pred_N_i ('0), .sb_0_4_pred_N_o (north_4_pred_o),
      .sb_0_4_NE_i     ('0), .sb_0_4_NE_o     (),
      .sb_0_4_pred_NE_i('0), .sb_0_4_pred_NE_o(),
      .sb_0_4_NW_i     ('0), .sb_0_4_NW_o     (),
      .sb_0_4_pred_NW_i('0), .sb_0_4_pred_NW_o(),

      .sb_0_6_N_i      ('0), .sb_0_6_N_o      (north_6_data_o),
      .sb_0_6_pred_N_i ('0), .sb_0_6_pred_N_o (north_6_pred_o),
      .sb_0_6_NE_i     ('0), .sb_0_6_NE_o     (),
      .sb_0_6_pred_NE_i('0), .sb_0_6_pred_NE_o(),
      .sb_0_6_NW_i     ('0), .sb_0_6_NW_o     (),
      .sb_0_6_pred_NW_i('0), .sb_0_6_pred_NW_o(),

      // -----------------------------------------------------------------------
      // Top-right corner (sb_0_8): East data in/out + top/diagonal tie-offs
      // -----------------------------------------------------------------------
      .sb_0_8_E_i      (gpr_rd_xbar_lo[4]),
      .sb_0_8_E_o      (cgra_gpr_data_lo[0*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_0_8_pred_E_i (pred_rd_xbar_lo[4]),
      .sb_0_8_pred_E_o (cgra_pred_data_lo[0]),
      .sb_0_8_N_i      ('0), .sb_0_8_N_o      (north_8_data_o),
      .sb_0_8_pred_N_i ('0), .sb_0_8_pred_N_o (north_8_pred_o),
      .sb_0_8_NE_i     ('0), .sb_0_8_NE_o     (),
      .sb_0_8_pred_NE_i('0), .sb_0_8_pred_NE_o(),
      .sb_0_8_NW_i     ('0), .sb_0_8_NW_o     (),
      .sb_0_8_pred_NW_i('0), .sb_0_8_pred_NW_o(),
      .sb_0_8_SE_i     ('0), .sb_0_8_SE_o     (),
      .sb_0_8_pred_SE_i('0), .sb_0_8_pred_SE_o(),

      // -----------------------------------------------------------------------
      // West boundary (col = 0, row = 2, 4, 6): PEs 1-3 data in/out
      // -----------------------------------------------------------------------
      .sb_2_0_W_i      (gpr_rd_xbar_lo[1]),
      .sb_2_0_W_o      (cgra_gpr_data_lo[5*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_2_0_pred_W_i (pred_rd_xbar_lo[1]),
      .sb_2_0_pred_W_o (cgra_pred_data_lo[5]),
      .sb_2_0_NW_i     ('0), .sb_2_0_NW_o     (),
      .sb_2_0_pred_NW_i('0), .sb_2_0_pred_NW_o(),
      .sb_2_0_SW_i     ('0), .sb_2_0_SW_o     (),
      .sb_2_0_pred_SW_i('0), .sb_2_0_pred_SW_o(),

      .sb_4_0_W_i      (gpr_rd_xbar_lo[2]),
      .sb_4_0_W_o      (cgra_gpr_data_lo[6*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_4_0_pred_W_i (pred_rd_xbar_lo[2]),
      .sb_4_0_pred_W_o (cgra_pred_data_lo[6]),
      .sb_4_0_NW_i     ('0), .sb_4_0_NW_o     (),
      .sb_4_0_pred_NW_i('0), .sb_4_0_pred_NW_o(),
      .sb_4_0_SW_i     ('0), .sb_4_0_SW_o     (),
      .sb_4_0_pred_SW_i('0), .sb_4_0_pred_SW_o(),

      .sb_6_0_W_i      (gpr_rd_xbar_lo[3]),
      .sb_6_0_W_o      (cgra_gpr_data_lo[7*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_6_0_pred_W_i (pred_rd_xbar_lo[3]),
      .sb_6_0_pred_W_o (cgra_pred_data_lo[7]),
      .sb_6_0_NW_i     ('0), .sb_6_0_NW_o     (),
      .sb_6_0_pred_NW_i('0), .sb_6_0_pred_NW_o(),
      .sb_6_0_SW_i     ('0), .sb_6_0_SW_o     (),
      .sb_6_0_pred_SW_i('0), .sb_6_0_pred_SW_o(),

      // -----------------------------------------------------------------------
      // East boundary (col = 8, row = 2, 4, 6): PEs 5-7 data in/out
      // -----------------------------------------------------------------------
      .sb_2_8_E_i      (gpr_rd_xbar_lo[5]),
      .sb_2_8_E_o      (cgra_gpr_data_lo[1*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_2_8_pred_E_i (pred_rd_xbar_lo[5]),
      .sb_2_8_pred_E_o (cgra_pred_data_lo[1]),
      .sb_2_8_NE_i     ('0), .sb_2_8_NE_o     (),
      .sb_2_8_pred_NE_i('0), .sb_2_8_pred_NE_o(),
      .sb_2_8_SE_i     ('0), .sb_2_8_SE_o     (),
      .sb_2_8_pred_SE_i('0), .sb_2_8_pred_SE_o(),

      .sb_4_8_E_i      (gpr_rd_xbar_lo[6]),
      .sb_4_8_E_o      (cgra_gpr_data_lo[2*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_4_8_pred_E_i (pred_rd_xbar_lo[6]),
      .sb_4_8_pred_E_o (cgra_pred_data_lo[2]),
      .sb_4_8_NE_i     ('0), .sb_4_8_NE_o     (),
      .sb_4_8_pred_NE_i('0), .sb_4_8_pred_NE_o(),
      .sb_4_8_SE_i     ('0), .sb_4_8_SE_o     (),
      .sb_4_8_pred_SE_i('0), .sb_4_8_pred_SE_o(),

      .sb_6_8_E_i      (gpr_rd_xbar_lo[7]),
      .sb_6_8_E_o      (cgra_gpr_data_lo[3*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH]),
      .sb_6_8_pred_E_i (pred_rd_xbar_lo[7]),
      .sb_6_8_pred_E_o (cgra_pred_data_lo[3]),
      .sb_6_8_NE_i     ('0), .sb_6_8_NE_o     (),
      .sb_6_8_pred_NE_i('0), .sb_6_8_pred_NE_o(),
      .sb_6_8_SE_i     ('0), .sb_6_8_SE_o     (),
      .sb_6_8_pred_SE_i('0), .sb_6_8_pred_SE_o(),

      // -----------------------------------------------------------------------
      // Bottom-left corner (sb_8_0) — tie off
      // -----------------------------------------------------------------------
      .sb_8_0_S_i      ('0), .sb_8_0_S_o      (south_0_data_o),
      .sb_8_0_pred_S_i ('0), .sb_8_0_pred_S_o (south_0_pred_o),
      .sb_8_0_W_i      ('0), .sb_8_0_W_o      (),
      .sb_8_0_pred_W_i ('0), .sb_8_0_pred_W_o (),
      .sb_8_0_NW_i     ('0), .sb_8_0_NW_o     (),
      .sb_8_0_pred_NW_i('0), .sb_8_0_pred_NW_o(),
      .sb_8_0_SE_i     ('0), .sb_8_0_SE_o     (),
      .sb_8_0_pred_SE_i('0), .sb_8_0_pred_SE_o(),
      .sb_8_0_SW_i     ('0), .sb_8_0_SW_o     (),
      .sb_8_0_pred_SW_i('0), .sb_8_0_pred_SW_o(),

      // -----------------------------------------------------------------------
      // Bottom boundary (row = 8, col = 2, 4, 6) — tie off
      // -----------------------------------------------------------------------
      .sb_8_2_S_i      ('0), .sb_8_2_S_o      (south_2_data_o),
      .sb_8_2_pred_S_i ('0), .sb_8_2_pred_S_o (south_2_pred_o),
      .sb_8_2_SE_i     ('0), .sb_8_2_SE_o     (),
      .sb_8_2_pred_SE_i('0), .sb_8_2_pred_SE_o(),
      .sb_8_2_SW_i     ('0), .sb_8_2_SW_o     (),
      .sb_8_2_pred_SW_i('0), .sb_8_2_pred_SW_o(),

      .sb_8_4_S_i      ('0), .sb_8_4_S_o      (south_4_data_o),
      .sb_8_4_pred_S_i ('0), .sb_8_4_pred_S_o (south_4_pred_o),
      .sb_8_4_SE_i     ('0), .sb_8_4_SE_o     (),
      .sb_8_4_pred_SE_i('0), .sb_8_4_pred_SE_o(),
      .sb_8_4_SW_i     ('0), .sb_8_4_SW_o     (),
      .sb_8_4_pred_SW_i('0), .sb_8_4_pred_SW_o(),

      .sb_8_6_S_i      ('0), .sb_8_6_S_o      (south_6_data_o),
      .sb_8_6_pred_S_i ('0), .sb_8_6_pred_S_o (south_6_pred_o),
      .sb_8_6_SE_i     ('0), .sb_8_6_SE_o     (),
      .sb_8_6_pred_SE_i('0), .sb_8_6_pred_SE_o(),
      .sb_8_6_SW_i     ('0), .sb_8_6_SW_o     (),
      .sb_8_6_pred_SW_i('0), .sb_8_6_pred_SW_o(),

      // -----------------------------------------------------------------------
      // Bottom-right corner (sb_8_8) — tie off
      // -----------------------------------------------------------------------
      .sb_8_8_S_i      ('0), .sb_8_8_S_o      (south_8_data_o),
      .sb_8_8_pred_S_i ('0), .sb_8_8_pred_S_o (south_8_pred_o),
      .sb_8_8_E_i      ('0), .sb_8_8_E_o      (),
      .sb_8_8_pred_E_i ('0), .sb_8_8_pred_E_o (),
      .sb_8_8_NE_i     ('0), .sb_8_8_NE_o     (),
      .sb_8_8_pred_NE_i('0), .sb_8_8_pred_NE_o(),
      .sb_8_8_SE_i     ('0), .sb_8_8_SE_o     (),
      .sb_8_8_pred_SE_i('0), .sb_8_8_pred_SE_o(),
      .sb_8_8_SW_i     ('0), .sb_8_8_SW_o     (),
      .sb_8_8_pred_SW_i('0), .sb_8_8_pred_SW_o(),

      // -----------------------------------------------------------------------
      // Programming chain — tie off until bitstream loader is implemented
      // -----------------------------------------------------------------------
      .prog_clk_i  ('0),
      .prog_rst_i  ('0),
      .prog_done_i ('0),
      .prog_we_i   ('0),
      .prog_din_i  ('0),
      .prog_dout_o (),
      .prog_we_o   ()
  );

  // =========================================================================
  // Block Commit Table
  // =========================================================================

  block_commit_table u_block_commit_table (
      .clk                 (clk_i),
      .rst                 (rst_i),

      // Insert interface
      .insert_valid        (bct_insert_valid),
      .insert_hw_cta_id    (bct_insert_hw_cta_id),
      .insert_e_block_id   (bct_insert_e_block_id),
      .insert_pending_reads(bct_insert_pending_reads),
      .insert_pending_writes(bct_insert_pending_writes),

      // Update interface
      .update_valid        (bct_update_valid),
      .update_e_block_id   (bct_update_e_block_id),
      .update_is_write     (bct_update_is_write),
      .update_reduce_count (bct_update_reduce_count),

      // Commit interface
      .pop_valid           (eblock_commit_valid_o),
      .pop_e_block_id      (eblock_commit_id_o),
      .pop_ready           (eblock_commit_ready_i),

      // Status
      .hw_cta_pending      (hw_cta_pending_o)
  );

endmodule
