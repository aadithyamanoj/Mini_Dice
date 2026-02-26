// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_fdr_top.h for the primary calling header

#ifndef VERILATED_VTB_FDR_TOP___024ROOT_H_
#define VERILATED_VTB_FDR_TOP___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"
class Vtb_fdr_top_VX_mem_bus_if__D40_T30;
class Vtb_fdr_top_cta_sched_if;
class Vtb_fdr_top_fdr_if;
class Vtb_fdr_top_simt_stack_status_if;


class Vtb_fdr_top__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_fdr_top___024root final : public VerilatedModule {
  public:
    // CELLS
    Vtb_fdr_top_VX_mem_bus_if__D40_T30* __PVT__tb_fdr_top__DOT__metacache_mem_if;
    Vtb_fdr_top_VX_mem_bus_if__D40_T30* __PVT__tb_fdr_top__DOT__bitstream_cache_mem_if;
    Vtb_fdr_top_cta_sched_if* __PVT__tb_fdr_top__DOT__schedule_if;
    Vtb_fdr_top_fdr_if* __PVT__tb_fdr_top__DOT__fdr_if;
    Vtb_fdr_top_simt_stack_status_if* __PVT__tb_fdr_top__DOT__simt_status_if;

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ tb_fdr_top__DOT__clk;
    CData/*0:0*/ tb_fdr_top__DOT__rst;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q;
    CData/*1:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q;
    CData/*1:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o;
    CData/*1:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q;
    CData/*1:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d;
    CData/*2:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q;
    CData/*2:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required;
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__rst__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal__0;
    CData/*0:0*/ __Vtrigprevexpr_he86f48af__1;
    CData/*0:0*/ __Vtrigprevexpr_h0e98381b__1;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0;
    CData/*0:0*/ __VactDidInit;
    IData/*31:0*/ tb_fdr_top__DOT__cycle_count;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q;
    IData/*29:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_cache_req_addr_q;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q;
    IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d;
    IData/*31:0*/ __VactIterCount;
    VlWide<5>/*139:0*/ tb_fdr_top__DOT__cta_status_data_i;
    VlWide<5>/*156:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    VlDelayScheduler __VdlySched;
    VlTriggerScheduler __VtrigSched_h416eaf98__0;
    VlTriggerScheduler __VtrigSched_hda9fe986__0;
    VlTriggerScheduler __VtrigSched_h40580101__0;
    VlTriggerScheduler __VtrigSched_h969ff5c5__0;
    VlTriggerScheduler __VtrigSched_hd8d198eb__0;

    // INTERNAL VARIABLES
    Vtb_fdr_top__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_fdr_top___024root(Vtb_fdr_top__Syms* symsp, const char* v__name);
    ~Vtb_fdr_top___024root();
    VL_UNCOPYABLE(Vtb_fdr_top___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
