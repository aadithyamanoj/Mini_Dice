`ifndef MEM_REQ_FIFO_4PORT_SV
`define MEM_REQ_FIFO_4PORT_SV

`include "dice_define.vh"

module mem_req_fifo
  import dice_pkg::*;
  import DE_pkg::*;
#(
    parameter int BUNDLE_FIFO_DEPTH = MEM_REQ_BUNDLE_FIFO_DEPTH,
    parameter int DEPTH = BUNDLE_FIFO_DEPTH,
    parameter int AXI_UW = 12,
    parameter int AXI_RD_DW = 32,
    localparam int ENQ_PORTS_LP = 4,
    localparam int AXI_AW = 16,
    localparam int AXI_DW = 16
) (
    input logic clk_i,
    input logic rst_i,

    input  logic enq_valid_i_0,
    input  logic enq_valid_i_1,
    input  logic enq_valid_i_2,
    input  logic enq_valid_i_3,
    output logic enq_ready_o,

    input logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] enq_tid_i,
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] enq_e_block_id_i,
    input logic [AXI_AW-1:0] enq_addr_i_0,
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
    input logic enq_op_i_0,
    input logic enq_op_i_1,
    input logic enq_op_i_2,
    input logic enq_op_i_3,

    output logic [ENQ_PORTS_LP-1:0][AXI_AW-1:0] axi_awaddr_o,
    output logic [ENQ_PORTS_LP-1:0]             axi_awvalid_o,
    input  logic [ENQ_PORTS_LP-1:0]             axi_awready_i,
    output logic [ENQ_PORTS_LP-1:0][AXI_DW-1:0] axi_wdata_o,
    output logic [ENQ_PORTS_LP-1:0][1:0]        axi_wstrb_o,
    output logic [ENQ_PORTS_LP-1:0]             axi_wvalid_o,
    input  logic [ENQ_PORTS_LP-1:0]             axi_wready_i,
    input  logic [ENQ_PORTS_LP-1:0][1:0]        axi_bresp_i,
    input  logic [ENQ_PORTS_LP-1:0]             axi_bvalid_i,
    output logic [ENQ_PORTS_LP-1:0]             axi_bready_o,
    output logic [ENQ_PORTS_LP-1:0][AXI_AW-1:0] axi_araddr_o,
    output logic [ENQ_PORTS_LP-1:0][AXI_UW-1:0] axi_aruser_o,
    output logic [ENQ_PORTS_LP-1:0]             axi_arvalid_o,
    input  logic [ENQ_PORTS_LP-1:0]             axi_arready_i,
    input  logic [AXI_RD_DW-1:0] axi_rdata_i,
    input  logic [1:0]           axi_rresp_i,
    input  logic                 axi_rvalid_i,
    output logic                 axi_rready_o,

    input  logic [                       DICE_NUM_BANKS-1:0] rsp_data_ready_i,
    input  logic                                             rsp_special_ready_i,
    output logic                                             pop_o,
    output logic                                             rsp_valid_o,
    output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] rsp_tid_o,
    output logic [                 DICE_EBLOCK_ID_WIDTH-1:0] rsp_e_block_id_o,
    output logic [                  DICE_REG_ADDR_WIDTH-1:0] rsp_addr_o,
    output logic [                  DICE_REG_DATA_WIDTH-1:0] rsp_data_o,

    output logic [ENQ_PORTS_LP-1:0][1:0]    port_credit_return_o,
    output logic                            store_pop_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0] store_pop_e_block_id_o
);

  typedef struct packed {
    logic                                             valid;
    logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic [DICE_EBLOCK_ID_WIDTH-1:0]                  e_block_id;
    logic [AXI_AW-1:0]                                addr;
    logic [AXI_DW-1:0]                                data;
    logic [DICE_REG_ADDR_WIDTH-1:0]                   rsp_addr;
    logic                                             op;
  } mem_req_s;

  localparam int TID_W_LP = $clog2(DICE_NUM_MAX_THREADS_PER_CORE);
  localparam int LOAD_META_W_LP = TID_W_LP + DICE_EBLOCK_ID_WIDTH + DICE_REG_ADDR_WIDTH;
  localparam int LOAD_DATA_LSB_LP = 0;
  localparam int LOAD_META_LSB_LP = DICE_REG_DATA_WIDTH;
  localparam int ISSUE_SEL_W_LP = $clog2(ENQ_PORTS_LP);

  initial begin
    if (AXI_UW < LOAD_META_W_LP)
      $error("mem_req_fifo requires AXI_UW >= %0d for load metadata", LOAD_META_W_LP);
    if (AXI_RD_DW < DICE_REG_DATA_WIDTH + LOAD_META_W_LP)
      $error("mem_req_fifo requires AXI_RD_DW >= %0d for packed load response",
             DICE_REG_DATA_WIDTH + LOAD_META_W_LP);
  end

  function automatic logic [AXI_UW-1:0] pack_load_meta(
      input logic [TID_W_LP-1:0] tid,
      input logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_id,
      input logic [DICE_REG_ADDR_WIDTH-1:0] rsp_addr
  );
    logic [AXI_UW-1:0] meta;
    begin
      meta = '0;
      meta[0+:DICE_REG_ADDR_WIDTH] = rsp_addr;
      meta[DICE_REG_ADDR_WIDTH+:DICE_EBLOCK_ID_WIDTH] = e_block_id;
      meta[DICE_REG_ADDR_WIDTH+DICE_EBLOCK_ID_WIDTH+:TID_W_LP] = tid;
      return meta;
    end
  endfunction

  function automatic logic [DICE_REG_ADDR_WIDTH-1:0] rsp_meta_addr(
      input logic [AXI_RD_DW-1:0] rdata
  );
    return rdata[LOAD_META_LSB_LP+:DICE_REG_ADDR_WIDTH];
  endfunction

  function automatic logic [DICE_EBLOCK_ID_WIDTH-1:0] rsp_meta_e_block_id(
      input logic [AXI_RD_DW-1:0] rdata
  );
    return rdata[LOAD_META_LSB_LP+DICE_REG_ADDR_WIDTH+:DICE_EBLOCK_ID_WIDTH];
  endfunction

  function automatic logic [TID_W_LP-1:0] rsp_meta_tid(input logic [AXI_RD_DW-1:0] rdata);
    return rdata[LOAD_META_LSB_LP+DICE_REG_ADDR_WIDTH+DICE_EBLOCK_ID_WIDTH+:TID_W_LP];
  endfunction

  function automatic logic [ISSUE_SEL_W_LP-1:0] next_issue_rr(input int port);
    logic [ISSUE_SEL_W_LP-1:0] next_port;
    next_port = ISSUE_SEL_W_LP'(port + 1);
    if (port == ENQ_PORTS_LP - 1) return '0;
    else return next_port;
  endfunction

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ISSUE_W,
    ST_ISSUE_R
  } state_e;

  logic [ENQ_PORTS_LP-1:0] enq_valid_li;
  logic [ENQ_PORTS_LP-1:0][AXI_AW-1:0] enq_addr_li;
  logic [ENQ_PORTS_LP-1:0][AXI_DW-1:0] enq_data_li;
  logic [ENQ_PORTS_LP-1:0][DICE_REG_ADDR_WIDTH-1:0] enq_rsp_addr_li;
  logic [ENQ_PORTS_LP-1:0] enq_op_li;
  mem_req_s [ENQ_PORTS_LP-1:0] fifo_push_data_li;
  logic [ENQ_PORTS_LP-1:0] fifo_push_v_li, fifo_ready_lo, fifo_v_lo, fifo_yumi_li;
  logic [ENQ_PORTS_LP-1:0][$bits(mem_req_s)-1:0] fifo_data_lo;
  mem_req_s [ENQ_PORTS_LP-1:0] fifo_head, active_req_q;
  state_e [ENQ_PORTS_LP-1:0] state_q;
  logic [ENQ_PORTS_LP-1:0] aw_done_q, w_done_q;
  logic [ENQ_PORTS_LP-1:0] store_retire_set_li;
  logic [ENQ_PORTS_LP-1:0] issue_req_li, issue_grant_li;
  logic [ENQ_PORTS_LP-1:0] ar_done_li;
  logic [ISSUE_SEL_W_LP-1:0] issue_rr_q;
  logic rsp_ready_li;
  logic enq_any_valid_li;

  assign enq_valid_li = {enq_valid_i_3, enq_valid_i_2, enq_valid_i_1, enq_valid_i_0};
  assign enq_addr_li = {enq_addr_i_3, enq_addr_i_2, enq_addr_i_1, enq_addr_i_0};
  assign enq_data_li = {enq_data_i_3, enq_data_i_2, enq_data_i_1, enq_data_i_0};
  assign enq_rsp_addr_li = {
    enq_rsp_addr_i_3, enq_rsp_addr_i_2, enq_rsp_addr_i_1, enq_rsp_addr_i_0
  };
  assign enq_op_li = {enq_op_i_3, enq_op_i_2, enq_op_i_1, enq_op_i_0};
  assign enq_ready_o = &fifo_ready_lo;
  assign enq_any_valid_li = |enq_valid_li;

  always_comb begin
    port_credit_return_o = '0;
    for (int p = 0; p < ENQ_PORTS_LP; p++) begin
      port_credit_return_o[p] = {1'b0, fifo_yumi_li[p]}
                              + {1'b0, enq_any_valid_li && !enq_valid_li[p]};
    end
  end

  for (genvar p = 0; p < ENQ_PORTS_LP; p++) begin : gen_port_fifo
    always_comb begin
      fifo_push_data_li[p] = '0;
      fifo_push_data_li[p].valid = enq_valid_li[p];
      fifo_push_data_li[p].tid = enq_tid_i;
      fifo_push_data_li[p].e_block_id = enq_e_block_id_i;
      fifo_push_data_li[p].addr = enq_addr_li[p];
      fifo_push_data_li[p].data = enq_data_li[p];
      fifo_push_data_li[p].rsp_addr = enq_rsp_addr_li[p];
      fifo_push_data_li[p].op = enq_op_li[p];
    end

    assign fifo_push_v_li[p] = enq_valid_li[p];
    assign fifo_head[p] = fifo_v_lo[p] ? mem_req_s'(fifo_data_lo[p]) : '0;

    bsg_fifo_1r1w_small #(
        .width_p($bits(mem_req_s)),
        .els_p  (DEPTH)
    ) port_fifo (
        .clk_i  (clk_i),
        .reset_i(rst_i),
        .v_i    (fifo_push_v_li[p]),
        .ready_o(fifo_ready_lo[p]),
        .data_i (fifo_push_data_li[p]),
        .v_o    (fifo_v_lo[p]),
        .data_o (fifo_data_lo[p]),
        .yumi_i (fifo_yumi_li[p])
    );

  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!rst_i && enq_any_valid_li && !enq_ready_o)
      $error("mem_req_fifo_4port: CGRA memory output arrived without all port FIFO credits");
  end
`endif

  always_comb begin
    issue_req_li = '0;
    for (int p = 0; p < ENQ_PORTS_LP; p++) begin
      issue_req_li[p] = (state_q[p] != ST_IDLE);
    end
  end

  // The four CGRA ports are skid-buffered independently, but the downstream IO
  // path is a single service point. Only one active port may drive AXI valid.
  always_comb begin
    issue_grant_li = '0;
    for (int offset = 0; offset < ENQ_PORTS_LP; offset++) begin
      int idx;
      idx = (int'(issue_rr_q) + offset) % ENQ_PORTS_LP;
      if ((issue_grant_li == '0) && issue_req_li[idx]) issue_grant_li[idx] = 1'b1;
    end
  end

  always_comb begin
    axi_awaddr_o = '0;
    axi_awvalid_o = '0;
    axi_wdata_o = '0;
    axi_wstrb_o = '0;
    axi_wvalid_o = '0;
    // Stores retire when AW/W leave the core. B is not part of core-side
    // retirement; keep it drained in case the downstream AXI fabric produces it.
    axi_bready_o = '1;
    axi_araddr_o = '0;
    axi_aruser_o = '0;
    axi_arvalid_o = '0;
    axi_rready_o = axi_rvalid_i && rsp_ready_li;
    fifo_yumi_li = '0;

    for (int p = 0; p < ENQ_PORTS_LP; p++) begin
      fifo_yumi_li[p] = (state_q[p] == ST_IDLE) && fifo_v_lo[p];
      unique case (state_q[p])
        ST_ISSUE_W: begin
          axi_awaddr_o[p] = active_req_q[p].addr;
          axi_awvalid_o[p] = issue_grant_li[p] && !aw_done_q[p];
          axi_wdata_o[p] = active_req_q[p].data;
          axi_wstrb_o[p] = 2'b11;
          axi_wvalid_o[p] = issue_grant_li[p] && !w_done_q[p];
        end
        ST_ISSUE_R: begin
          axi_araddr_o[p] = active_req_q[p].addr;
          axi_aruser_o[p] = pack_load_meta(
              active_req_q[p].tid, active_req_q[p].e_block_id, active_req_q[p].rsp_addr
          );
          axi_arvalid_o[p] = issue_grant_li[p];
        end
        default: ;
      endcase
    end
  end

  always_comb begin
    store_retire_set_li = '0;
    ar_done_li = '0;
    for (int p = 0; p < ENQ_PORTS_LP; p++) begin
      store_retire_set_li[p] = (state_q[p] == ST_ISSUE_W)
                            && issue_grant_li[p]
                            && (aw_done_q[p] || axi_awready_i[p])
                            && (w_done_q[p] || axi_wready_i[p]);
      ar_done_li[p] = (state_q[p] == ST_ISSUE_R) && issue_grant_li[p] && axi_arready_i[p];
    end
  end

  always_comb begin
    logic [DICE_REG_ADDR_WIDTH-1:0] meta_addr;
    logic meta_is_gpr;
    meta_addr = rsp_meta_addr(axi_rdata_i);
    meta_is_gpr = (meta_addr < DICE_REG_ADDR_WIDTH'(DICE_NUM_BANKS));
    rsp_ready_li = axi_rvalid_i
        && (meta_is_gpr ? rsp_data_ready_i[meta_addr[$clog2(DICE_NUM_BANKS)-1:0]]
                        : rsp_special_ready_i);
  end

  always_comb begin
    rsp_valid_o = axi_rvalid_i && rsp_ready_li;
    rsp_tid_o = rsp_meta_tid(axi_rdata_i);
    rsp_e_block_id_o = rsp_meta_e_block_id(axi_rdata_i);
    rsp_addr_o = rsp_meta_addr(axi_rdata_i);
    rsp_data_o = axi_rdata_i[LOAD_DATA_LSB_LP+:DICE_REG_DATA_WIDTH];
  end

  always_comb begin
    store_pop_o = |store_retire_set_li;
    store_pop_e_block_id_o = '0;
    for (int p = 0; p < ENQ_PORTS_LP; p++)
      if (store_retire_set_li[p]) store_pop_e_block_id_o = active_req_q[p].e_block_id;
  end

  assign pop_o = rsp_valid_o | store_pop_o;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      state_q <= '{default: ST_IDLE};
      active_req_q <= '{default: '0};
      aw_done_q <= '0;
      w_done_q <= '0;
      issue_rr_q <= '0;
    end
    else begin
      for (int p = 0; p < ENQ_PORTS_LP; p++) begin
        unique case (state_q[p])
          ST_IDLE: begin
            aw_done_q[p] <= 1'b0;
            w_done_q[p] <= 1'b0;
            if (fifo_v_lo[p]) begin
              active_req_q[p] <= fifo_head[p];
              state_q[p] <= fifo_head[p].op ? ST_ISSUE_W : ST_ISSUE_R;
            end
          end
          ST_ISSUE_W: begin
            if (issue_grant_li[p] && !aw_done_q[p] && axi_awready_i[p]) aw_done_q[p] <= 1'b1;
            if (issue_grant_li[p] && !w_done_q[p] && axi_wready_i[p]) w_done_q[p] <= 1'b1;
            if (store_retire_set_li[p]) begin
              state_q[p] <= ST_IDLE;
            end
          end
          ST_ISSUE_R: if (ar_done_li[p]) state_q[p] <= ST_IDLE;
        endcase
      end

      for (int p = 0; p < ENQ_PORTS_LP; p++) begin
        if (store_retire_set_li[p] || ar_done_li[p])
          issue_rr_q <= next_issue_rr(p);
      end

    end
  end

endmodule

`endif
