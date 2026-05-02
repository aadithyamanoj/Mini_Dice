`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

package axi4_xbar_pkg;

  import axi_pkg::*;

  localparam int unsigned AxiAddrWidth = 16;
  localparam int unsigned AxiDataWidth = 32;
  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;  // 4
  localparam int unsigned AxiUserWidth = 1;

  localparam int unsigned NoMasters   = 4;
  localparam int unsigned NoSlaves    = 2;
  localparam int unsigned NoAddrRules = 2;

  localparam int unsigned SlvIdWidth = 4;
  localparam int unsigned MstIdWidth = SlvIdWidth + $clog2(NoMasters); // = 6

  localparam int unsigned IDX_FPGAMEM = 0;
  localparam int unsigned IDX_CSR     = 1;

  localparam logic [AxiAddrWidth-1:0] FPGAMEM_BASE = 16'h0000;
  localparam logic [AxiAddrWidth-1:0] FPGAMEM_END  = 16'hFF00;
  localparam logic [AxiAddrWidth-1:0] CSR_BASE      = 16'hFF00;
  localparam logic [AxiAddrWidth-1:0] CSR_END       = 16'h0000;

  typedef struct packed {
    int unsigned             idx;
    logic [AxiAddrWidth-1:0] start_addr;
    logic [AxiAddrWidth-1:0] end_addr;
  } xbar_rule_16_t;

  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         NoMasters,
    NoMstPorts:         NoSlaves,
    MaxMstTrans:        8,
    MaxSlvTrans:        8,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    PipelineStages:     0,
    AxiIdWidthSlvPorts: SlvIdWidth,
    AxiIdUsedSlvPorts:  SlvIdWidth,
    UniqueIds:          1'b0,
    AxiAddrWidth:       AxiAddrWidth,
    AxiDataWidth:       AxiDataWidth,
    NoAddrRules:        NoAddrRules
  };

  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiStrbWidth-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  typedef logic [SlvIdWidth-1:0]   slv_id_t;
  typedef logic [MstIdWidth-1:0]   mst_id_t;

  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_t,  axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T (w_t,        axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T (slv_b_t,   slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_t,  axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T (slv_r_t,   axi_data_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T    (slv_req_t, slv_aw_t, w_t, slv_ar_t)
  `AXI_TYPEDEF_RESP_T   (slv_resp_t, slv_b_t, slv_r_t)

  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_t,  axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T (mst_b_t,   mst_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_t,  axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T (mst_r_t,   axi_data_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T    (mst_req_t, mst_aw_t, w_t, mst_ar_t)
  `AXI_TYPEDEF_RESP_T   (mst_resp_t, mst_b_t, mst_r_t)

endpackage : axi4_xbar_pkg
