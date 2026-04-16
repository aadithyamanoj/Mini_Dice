// mem_req_fifo.sv
//
// Depth-16 synchronous FIFO that serializes per-thread memory requests from
// the CGRA (via dice_backend shift-register outputs) onto an AXI-Lite master
// port, then drives the dice_backend mem_rsp_* writeback inputs.
//
// Flow:
//   LOAD  : enqueue → issue AR → wait RVALID → pulse rsp_valid_o → pop
//   STORE : enqueue → issue AW+W → wait BVALID → pop (no RF writeback)
//
// One transaction in flight at a time (AXI-Lite has no ID fields).
//
// The enqueue port stores the AXI address separately from the RF writeback
// destination. Loads issue enq_addr_i_* on AXI, then write the response back to
// enq_rsp_addr_i_*; stores ignore the response destination.

`include "dice_define.vh"

module mem_req_fifo
  import dice_pkg::*;
  import DE_pkg::*;
#(
    parameter int DEPTH = 64,
    localparam int ENQ_PORTS_LP = 4,
    localparam int AXI_AW = 16,
    localparam int AXI_DW = 16
) (
    input logic clk_i,
    input logic rst_i,

    // -------------------------------------------------------------------------
    // Enqueue port
    // -------------------------------------------------------------------------
    input  logic enq_valid_i_0,
    input  logic enq_valid_i_1,
    input  logic enq_valid_i_2,
    input  logic enq_valid_i_3,
    output logic enq_ready_o,    // FIFO not full

    input logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] enq_tid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] enq_e_block_id_i,
    input logic [AXI_AW-1:0] enq_addr_i_0,  // mem_addr_o → AXI address
    input logic [AXI_AW-1:0] enq_addr_i_1,
    input logic [AXI_AW-1:0] enq_addr_i_2,
    input logic [AXI_AW-1:0] enq_addr_i_3,
    input logic [AXI_DW-1:0] enq_data_i_0,
    input logic [AXI_DW-1:0] enq_data_i_1,
    input logic [AXI_DW-1:0] enq_data_i_2,
    input logic [AXI_DW-1:0] enq_data_i_3,
    input logic [DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_i_0,
    input logic [DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_i_1,
    input logic [DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_i_2,
    input logic [DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_i_3,
    input logic enq_op_i_0,  // 0 == ld 1 == st
    input logic enq_op_i_1,
    input logic enq_op_i_2,
    input logic enq_op_i_3,

    // -------------------------------------------------------------------------
    // AXI-Lite master — connect to cgra_mem_system_16bit crossbar
    // -------------------------------------------------------------------------
    output logic [AXI_AW-1:0] axi_awaddr_o,
    output logic              axi_awvalid_o,
    input  logic              axi_awready_i,

    output logic [AXI_DW-1:0] axi_wdata_o,
    output logic [       1:0] axi_wstrb_o,
    output logic              axi_wvalid_o,
    input  logic              axi_wready_i,

    input  logic [1:0] axi_bresp_i,
    input  logic       axi_bvalid_i,
    output logic       axi_bready_o,

    output logic [AXI_AW-1:0] axi_araddr_o,
    output logic              axi_arvalid_o,
    input  logic              axi_arready_i,

    input  logic [AXI_DW-1:0] axi_rdata_i,
    input  logic [       1:0] axi_rresp_i,
    input  logic              axi_rvalid_i,
    output logic              axi_rready_o,

    // -------------------------------------------------------------------------
    // Backend writeback — wire directly to dice_backend.sv mem_rsp_* inputs
    // -------------------------------------------------------------------------
    input  logic [                       DICE_NUM_BANKS-1:0] rsp_data_ready_i,
    input  logic                                             rsp_special_ready_i,
    output logic                                             pop_o,
    output logic                                             rsp_valid_o,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] rsp_tid_o,
    output logic [                 DICE_EBLOCK_ID_WIDTH-1:0] rsp_e_block_id_o,
    output logic [                  DICE_REG_ADDR_WIDTH-1:0] rsp_addr_o,
    output logic [                  DICE_REG_DATA_WIDTH-1:0] rsp_data_o,

    // Store completion retire — pulses when a store AXI write finishes
    output logic                                             store_pop_o,
    output logic [                 DICE_EBLOCK_ID_WIDTH-1:0] store_pop_e_block_id_o
);

  // -------------------------------------------------------------------------
  // Request payload stored in the FIFO
  // -------------------------------------------------------------------------
  typedef struct packed {
    logic                                             valid;
    logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic [DICE_EBLOCK_ID_WIDTH-1:0]                  e_block_id;
    logic [AXI_AW-1:0]                                addr;
    logic [AXI_DW-1:0]                                data;
    logic [DICE_REG_ADDR_WIDTH-1:0]                    rsp_addr;
    logic                                             op;
  } mem_req_s;

  mem_req_s [ENQ_PORTS_LP-1:0] enq_req_li;
  logic [ENQ_PORTS_LP-1:0] enq_valid_li;
  logic [ENQ_PORTS_LP-1:0][AXI_AW-1:0] enq_addr_li;
  logic [ENQ_PORTS_LP-1:0][AXI_DW-1:0] enq_data_li;
  logic [ENQ_PORTS_LP-1:0][DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_li;
  logic [ENQ_PORTS_LP-1:0] enq_op_li;
  mem_req_s serial_req_lo, head_req, active_req_q;
  logic [$bits(mem_req_s)-1:0] serial_req_bits_lo, head_req_lo;
  logic piso_v_lo, piso_yumi_li, piso_ready_lo;
  logic req_fifo_ready_lo;
  logic head_v_lo, head_yumi_li, req_fifo_yumi_li;

  assign enq_valid_li[0] = enq_valid_i_0;
  assign enq_valid_li[1] = enq_valid_i_1;
  assign enq_valid_li[2] = enq_valid_i_2;
  assign enq_valid_li[3] = enq_valid_i_3;

  assign enq_addr_li[0] = enq_addr_i_0;
  assign enq_addr_li[1] = enq_addr_i_1;
  assign enq_addr_li[2] = enq_addr_i_2;
  assign enq_addr_li[3] = enq_addr_i_3;

  assign enq_data_li[0] = enq_data_i_0;
  assign enq_data_li[1] = enq_data_i_1;
  assign enq_data_li[2] = enq_data_i_2;
  assign enq_data_li[3] = enq_data_i_3;

  assign enq_rsp_addr_li[0] = enq_rsp_addr_i_0;
  assign enq_rsp_addr_li[1] = enq_rsp_addr_i_1;
  assign enq_rsp_addr_li[2] = enq_rsp_addr_i_2;
  assign enq_rsp_addr_li[3] = enq_rsp_addr_i_3;

  assign enq_op_li[0] = enq_op_i_0;
  assign enq_op_li[1] = enq_op_i_1;
  assign enq_op_li[2] = enq_op_i_2;
  assign enq_op_li[3] = enq_op_i_3;

  always_comb begin
    for (int i = 0; i < ENQ_PORTS_LP; i++) begin
      enq_req_li[i] = '0;
      if (enq_valid_li[i]) begin
        enq_req_li[i].valid      = 1'b1;
        enq_req_li[i].tid        = enq_tid_i;
        enq_req_li[i].e_block_id = enq_e_block_id_i;
        enq_req_li[i].addr       = enq_addr_li[i];
        enq_req_li[i].data       = enq_data_li[i];
        enq_req_li[i].rsp_addr   = enq_rsp_addr_li[i];
        enq_req_li[i].op         = enq_op_li[i];
      end
    end
  end

  bsg_parallel_in_serial_out #(
      .width_p($bits(mem_req_s)),
      .els_p  (ENQ_PORTS_LP)
  ) enq_serializer (
      .clk_i(clk_i),
      .reset_i(rst_i),
      .valid_i(|enq_valid_li),
      .data_i(enq_req_li),
      .ready_and_o(piso_ready_lo),
      .valid_o(piso_v_lo),
      .data_o(serial_req_bits_lo),
      .yumi_i(piso_yumi_li)
  );

  assign serial_req_lo = piso_v_lo ? serial_req_bits_lo : '0;
  assign head_req      = head_v_lo ? head_req_lo : '0;
  assign enq_ready_o   = piso_ready_lo & (&rsp_data_ready_i) & rsp_special_ready_i;

  bsg_fifo_1r1w_small #(
      .width_p($bits(mem_req_s)),
      .els_p  (DEPTH)
  ) req_fifo (
      .clk_i(clk_i),
      .reset_i(rst_i),
      .v_i(piso_v_lo & serial_req_lo.valid),
      .ready_o(req_fifo_ready_lo),
      .data_i(serial_req_bits_lo),
      .v_o(head_v_lo),
      .data_o(head_req_lo),
      .yumi_i(req_fifo_yumi_li)
  );

  assign piso_yumi_li = piso_v_lo & (~serial_req_lo.valid | req_fifo_ready_lo);

  // Head-of-FIFO convenience wires
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] h_tid;
  logic [                 DICE_EBLOCK_ID_WIDTH-1:0] h_e_block_id;
  logic [                               AXI_AW-1:0] h_addr;
  logic [                               AXI_DW-1:0] h_data;
  logic [                  DICE_REG_ADDR_WIDTH-1:0] h_rsp_addr;
  logic                                             h_op;
  logic                                             rsp_is_gpr;
  logic                                             rsp_bank_ready;

  assign h_tid = active_req_q.tid;
  assign h_e_block_id = active_req_q.e_block_id;
  assign h_addr = active_req_q.addr;
  assign h_data = active_req_q.data;
  assign h_rsp_addr = active_req_q.rsp_addr;
  assign h_op = active_req_q.op;
  assign rsp_is_gpr = (h_rsp_addr < DICE_REG_ADDR_WIDTH'(DICE_NUM_BANKS));
  assign rsp_bank_ready = rsp_is_gpr ? rsp_data_ready_i[h_rsp_addr[$clog2(
      DICE_NUM_BANKS
  )-1:0]] : rsp_special_ready_i;

  // -------------------------------------------------------------------------
  // AXI-Lite transaction FSM
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_LATCH,    // latch FIFO head into active_req_q
    ST_ISSUE_W,  // asserting AW + W for a store
    ST_WAIT_B,   // waiting for BVALID (store complete)
    ST_ISSUE_R,  // asserting AR for a load
    ST_WAIT_R    // waiting for RVALID (load data arrives)
  } state_e;

  state_e state;
  logic aw_done, w_done;  // track per-channel handshake in ST_ISSUE_W

  // -------------------------------------------------------------------------
  // AXI-Lite output drive (combinational)
  // -------------------------------------------------------------------------
  always_comb begin
    axi_awaddr_o  = '0;
    axi_awvalid_o = 1'b0;
    axi_wdata_o   = '0;
    axi_wstrb_o   = 2'b01;  // byte lane 0
    axi_wvalid_o  = 1'b0;
    axi_bready_o  = 1'b0;
    axi_araddr_o  = '0;
    axi_arvalid_o = 1'b0;
    axi_rready_o  = 1'b0;

    unique case (state)
      ST_ISSUE_W: begin
        axi_awaddr_o  = AXI_AW'(h_addr);
        axi_awvalid_o = !aw_done;
        axi_wdata_o   = h_data;
        axi_wstrb_o   = 2'b11;
        axi_wvalid_o  = !w_done;
      end
      ST_WAIT_B: axi_bready_o = 1'b1;
      ST_ISSUE_R: begin
        axi_araddr_o  = AXI_AW'(h_addr);
        axi_arvalid_o = 1'b1;
      end
      ST_WAIT_R: axi_rready_o = axi_rvalid_i && rsp_bank_ready;
      default:   ;
    endcase
  end

  // -------------------------------------------------------------------------
  // Response output — AXI data returns with the stored RF destination register.
  // -------------------------------------------------------------------------
  assign rsp_valid_o = (state == ST_WAIT_R) && axi_rvalid_i && rsp_bank_ready;
  assign head_yumi_li = ((state == ST_WAIT_B) && axi_bvalid_i)
                     || ((state == ST_WAIT_R) && axi_rvalid_i && rsp_bank_ready);
  assign req_fifo_yumi_li = (state == ST_IDLE) && head_v_lo;
  assign pop_o = head_yumi_li;
  assign store_pop_o = head_yumi_li & h_op;
  assign store_pop_e_block_id_o = h_e_block_id;

  always_comb begin
    rsp_tid_o = h_tid;
    rsp_e_block_id_o = h_e_block_id;
    rsp_addr_o = h_rsp_addr;
    rsp_data_o = axi_rdata_i;
  end

  // -------------------------------------------------------------------------
  // Sequential: FIFO push/pop + FSM transitions
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state        <= ST_IDLE;
      aw_done      <= 1'b0;
      w_done       <= 1'b0;
      active_req_q <= '0;
    end else begin

      // --- FSM --------------------------------------------------------------
      unique case (state)

        ST_IDLE: begin
          aw_done <= 1'b0;
          w_done  <= 1'b0;
          if (head_v_lo) begin
            active_req_q <= head_req_lo;
            state <= ST_LATCH;
          end
        end

        ST_LATCH: begin
          state <= h_op ? ST_ISSUE_W : ST_ISSUE_R;
        end

        ST_ISSUE_W: begin
          // Track each channel's handshake independently (AXI-Lite allows
          // AW and W to be accepted in any order).
          if (!aw_done && axi_awready_i) aw_done <= 1'b1;
          if (!w_done && axi_wready_i) w_done <= 1'b1;

          // Both accepted this cycle or already done → move to wait
          if ((aw_done || axi_awready_i) && (w_done || axi_wready_i)) state <= ST_WAIT_B;
        end

        ST_WAIT_B: begin
          if (axi_bvalid_i) begin
            state <= ST_IDLE;
          end
        end

        ST_ISSUE_R: begin
          if (axi_arready_i) state <= ST_WAIT_R;
        end

        ST_WAIT_R: begin
          // Only consume the AXI read response when the RF writeback path can
          // accept it. Otherwise keep rready low and hold the request live.
          if (axi_rvalid_i && rsp_bank_ready) begin
            state <= ST_IDLE;
          end
        end

      endcase
    end
  end

endmodule
