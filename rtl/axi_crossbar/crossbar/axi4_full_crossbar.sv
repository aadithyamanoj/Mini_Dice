// =============================================================================
// axi4_full_crossbar.sv
//
// Full AXI4 (burst / ID support) crossbar for the FPGA–CGRA system.
// Replaces / extends the existing AXI-Lite cgra_mem_system_16bit with full
// AXI4 capability while keeping the same 16-bit address / data widths and
// address map.
//
// Topology
// --------
//   Slave ports (masters driving the bus):
//     [0] fpga_mst  – FPGA host: writes CGRA CSRs; may also stage data in
//                     FPGA SRAM for DMA kick-off.
//     [1:4] dfetch  – CGRA data-fetch ports: read/write payload in FPGA SRAM.
//     [5] mfetch    – CGRA metadata-fetch unit: reads metadata from FPGA SRAM.
//     [6] bsfetch   – CGRA bitstream-fetch unit: reads bitstream from FPGA SRAM.
//
//   Master ports (slaves driven by the bus):
//     [0] fpga_mem  – FPGA-side SRAM   0x0800 – 0x0FFF (2 KB, 1024×16-bit)
//     [1] cgra_csr  – CGRA CSR bank    0x0000 – 0x00FF (8×16-bit registers)
//
// AXI4 bus parameters  (matched to existing 16-bit CGRA subsystem)
// -------------------
//   Address width : 16 b
//   Data width    : 16 b
//   Strobe width  :  2 b
//   ID width      :  4 b per master; 6 b at every slave port
//                    (crossbar appends log2(4)=2 b for global uniqueness)
//   User width    : 14 b
//   Reset polarity: active-high (rst_i)  — inverted internally for AXI IP
// =============================================================================

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

// =============================================================================
// Package: axi4_xbar_pkg
// =============================================================================
package axi4_xbar_pkg;

  import axi_pkg::*;

  // ---------------------------------------------------------------------------
  // Bus parameters
  // ---------------------------------------------------------------------------
  localparam int unsigned AxiAddrWidth = 16;
  localparam int unsigned AxiDataWidth = 32;
  localparam int unsigned AxiStrbWidth = AxiDataWidth / 8;  // 4
  localparam int unsigned AxiUserWidth = 14;

  // ---------------------------------------------------------------------------
  // Crossbar topology
  // ---------------------------------------------------------------------------
  localparam int unsigned NoMasters   = 7;  // slave ports on the xbar
  localparam int unsigned NoSlaves    = 2;  // master ports on the xbar
  localparam int unsigned NoAddrRules = 2;

  // ---------------------------------------------------------------------------
  // ID widths
  // Each master generates SlvIdWidth-bit IDs.  axi_xbar prepends
  // $clog2(NoMasters) bits so every slave sees globally unique IDs.
  // ---------------------------------------------------------------------------
  localparam int unsigned SlvIdWidth = 4;
  localparam int unsigned MstIdWidth = SlvIdWidth + $clog2(NoMasters); // = 7

  // ---------------------------------------------------------------------------
  // Slave-port index constants
  // ---------------------------------------------------------------------------
  localparam int unsigned IDX_FPGAMEM = 0;
  localparam int unsigned IDX_CSR     = 1;

  // ---------------------------------------------------------------------------
  // Address map
  //   [0] fpga_mem : 0x0000 – 0xFEFF  (covers all CGRA fetch/data addresses)
  //   [1] cgra_csr : 0xFF00 – 0xFFFF  (16 × 16-bit regs, word-stride = 2)
  // cgra_io_csr decodes only the low-order bits of the address, so it works at
  // any high base.  end_addr is exclusive per common_cells/addr_decode.sv, so
  // FPGAMEM_END = 16'hFF00 excludes the CSR region and CSR_END = 16'h0000 is
  // the sentinel for end-of-address-space.
  // ---------------------------------------------------------------------------
  localparam logic [AxiAddrWidth-1:0] FPGAMEM_BASE = 16'h0000;
  localparam logic [AxiAddrWidth-1:0] FPGAMEM_END  = 16'hFF00;
  localparam logic [AxiAddrWidth-1:0] CSR_BASE      = 16'hFF00;
  localparam logic [AxiAddrWidth-1:0] CSR_END       = 16'h0000;

  // ---------------------------------------------------------------------------
  // 16-bit address rule type
  // (axi_pkg only provides xbar_rule_32_t / xbar_rule_64_t)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    int unsigned             idx;
    logic [AxiAddrWidth-1:0] start_addr;
    logic [AxiAddrWidth-1:0] end_addr;
  } xbar_rule_16_t;

  // ---------------------------------------------------------------------------
  // Crossbar configuration struct
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Scalar types
  // ---------------------------------------------------------------------------
  typedef logic [AxiAddrWidth-1:0] axi_addr_t;
  typedef logic [AxiDataWidth-1:0] axi_data_t;
  typedef logic [AxiStrbWidth-1:0] axi_strb_t;
  typedef logic [AxiUserWidth-1:0] axi_user_t;
  typedef logic [SlvIdWidth-1:0]   slv_id_t;
  typedef logic [MstIdWidth-1:0]   mst_id_t;

  // ---------------------------------------------------------------------------
  // Slave-port types  (master→xbar, narrow SlvIdWidth-bit IDs)
  // ---------------------------------------------------------------------------
  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_t,  axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_W_CHAN_T (w_t,        axi_data_t, axi_strb_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T (slv_b_t,   slv_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_t,  axi_addr_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T (slv_r_t,   axi_data_t, slv_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T    (slv_req_t, slv_aw_t, w_t, slv_ar_t)
  `AXI_TYPEDEF_RESP_T   (slv_resp_t, slv_b_t, slv_r_t)

  // ---------------------------------------------------------------------------
  // Master-port types  (xbar→slave, wide MstIdWidth-bit IDs)
  // ---------------------------------------------------------------------------
  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_t,  axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_B_CHAN_T (mst_b_t,   mst_id_t, axi_user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_t,  axi_addr_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_R_CHAN_T (mst_r_t,   axi_data_t, mst_id_t, axi_user_t)
  `AXI_TYPEDEF_REQ_T    (mst_req_t, mst_aw_t, w_t, mst_ar_t)
  `AXI_TYPEDEF_RESP_T   (mst_resp_t, mst_b_t, mst_r_t)

endpackage : axi4_xbar_pkg


// =============================================================================
// Module: axi4_full_crossbar
// =============================================================================
module axi4_full_crossbar
  import axi4_xbar_pkg::*;
(
  input  logic clk_i,
  input  logic rst_i,   // active-high synchronous reset
  input  logic test_i,

  // --------------------------------------------------------------------------
  // Slave ports – one per master driving the crossbar
  // --------------------------------------------------------------------------

  // [0] FPGA host
  input  slv_req_t  fpga_mst_req_i,
  output slv_resp_t fpga_mst_resp_o,

  // [1:4] CGRA data-fetch
  input  slv_req_t  dfetch0_req_i,
  output slv_resp_t dfetch0_resp_o,
  input  slv_req_t  dfetch1_req_i,
  output slv_resp_t dfetch1_resp_o,
  input  slv_req_t  dfetch2_req_i,
  output slv_resp_t dfetch2_resp_o,
  input  slv_req_t  dfetch3_req_i,
  output slv_resp_t dfetch3_resp_o,

  // [5] CGRA metadata-fetch
  input  slv_req_t  mfetch_req_i,
  output slv_resp_t mfetch_resp_o,

  // [6] CGRA bitstream-fetch
  input  slv_req_t  bsfetch_req_i,
  output slv_resp_t bsfetch_resp_o,

  // --------------------------------------------------------------------------
  // Master ports – one per slave reachable through the crossbar
  // --------------------------------------------------------------------------

  // [0] FPGA-side SRAM   0x0800 – 0x0FFF
  output mst_req_t  fpga_mem_req_o,
  input  mst_resp_t fpga_mem_resp_i,

  // [1] CGRA CSR bank    0x0000 – 0x00FF
  output mst_req_t  cgra_csr_req_o,
  input  mst_resp_t cgra_csr_resp_i
);

  // Active-low reset required by pulp-platform AXI IP
  logic rst_n;
  assign rst_n = ~rst_i;

  // --------------------------------------------------------------------------
  // Pack master requests/responses into arrays for axi_xbar
  // --------------------------------------------------------------------------
  slv_req_t  [NoMasters-1:0] slv_ports_req;
  slv_resp_t [NoMasters-1:0] slv_ports_resp;

  assign slv_ports_req[0] = fpga_mst_req_i;
  assign slv_ports_req[1] = dfetch0_req_i;
  assign slv_ports_req[2] = dfetch1_req_i;
  assign slv_ports_req[3] = dfetch2_req_i;
  assign slv_ports_req[4] = dfetch3_req_i;
  assign slv_ports_req[5] = mfetch_req_i;
  assign slv_ports_req[6] = bsfetch_req_i;

  assign fpga_mst_resp_o = slv_ports_resp[0];
  assign dfetch0_resp_o  = slv_ports_resp[1];
  assign dfetch1_resp_o  = slv_ports_resp[2];
  assign dfetch2_resp_o  = slv_ports_resp[3];
  assign dfetch3_resp_o  = slv_ports_resp[4];
  assign mfetch_resp_o   = slv_ports_resp[5];
  assign bsfetch_resp_o  = slv_ports_resp[6];

  // --------------------------------------------------------------------------
  // Pack slave requests/responses into arrays for axi_xbar
  // --------------------------------------------------------------------------
  mst_req_t  [NoSlaves-1:0] mst_ports_req;
  mst_resp_t [NoSlaves-1:0] mst_ports_resp;

  assign fpga_mem_req_o = mst_ports_req[IDX_FPGAMEM];
  assign cgra_csr_req_o = mst_ports_req[IDX_CSR];

  assign mst_ports_resp[IDX_FPGAMEM] = fpga_mem_resp_i;
  assign mst_ports_resp[IDX_CSR]     = cgra_csr_resp_i;

  // --------------------------------------------------------------------------
  // Static address map
  // --------------------------------------------------------------------------
  localparam xbar_rule_16_t [NoAddrRules-1:0] AddrMap = '{
    '{idx: IDX_FPGAMEM, start_addr: FPGAMEM_BASE, end_addr: FPGAMEM_END},
    '{idx: IDX_CSR,     start_addr: CSR_BASE,     end_addr: CSR_END    }
  };

  // Transactions hitting no rule get a DECERR from the internal error slave.
  logic [NoMasters-1:0]                       en_default_mst;
  logic [NoMasters-1:0][$clog2(NoSlaves)-1:0] default_mst;
  assign en_default_mst = '0;
  assign default_mst    = '0;

  // --------------------------------------------------------------------------
  // Full AXI4 crossbar (pulp-platform axi_xbar)
  // --------------------------------------------------------------------------
  axi_xbar #(
    .Cfg           ( XbarCfg        ),
    .ATOPs         ( 1'b0           ),  // no atomic ops in this design; avoids axi_atop_filter dep
    .slv_aw_chan_t ( slv_aw_t       ),
    .mst_aw_chan_t ( mst_aw_t       ),
    .w_chan_t      ( w_t            ),
    .slv_b_chan_t  ( slv_b_t        ),
    .mst_b_chan_t  ( mst_b_t        ),
    .slv_ar_chan_t ( slv_ar_t       ),
    .mst_ar_chan_t ( mst_ar_t       ),
    .slv_r_chan_t  ( slv_r_t        ),
    .mst_r_chan_t  ( mst_r_t        ),
    .slv_req_t     ( slv_req_t      ),
    .slv_resp_t    ( slv_resp_t     ),
    .mst_req_t     ( mst_req_t      ),
    .mst_resp_t    ( mst_resp_t     ),
    .rule_t        ( xbar_rule_16_t )
  ) i_xbar (
    .clk_i                 ( clk_i           ),
    .rst_ni                ( rst_n           ),
    .test_i                ( test_i          ),
    .slv_ports_req_i       ( slv_ports_req   ),
    .slv_ports_resp_o      ( slv_ports_resp  ),
    .mst_ports_req_o       ( mst_ports_req   ),
    .mst_ports_resp_i      ( mst_ports_resp  ),
    .addr_map_i            ( AddrMap         ),
    .en_default_mst_port_i ( en_default_mst  ),
    .default_mst_port_i    ( default_mst     )
  );

endmodule : axi4_full_crossbar
