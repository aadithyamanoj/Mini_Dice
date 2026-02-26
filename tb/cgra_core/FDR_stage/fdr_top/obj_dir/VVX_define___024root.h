// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VVX_define.h for the primary calling header

#ifndef VERILATED_VVX_DEFINE___024ROOT_H_
#define VERILATED_VVX_DEFINE___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"
class VVX_define_VX_mem_bus_if__D40_T30;
class VVX_define_cta_sched_if;
class VVX_define_fdr_if;
class VVX_define_simt_stack_status_if;


class VVX_define__Syms;

class alignas(VL_CACHE_LINE_BYTES) VVX_define___024root final : public VerilatedModule {
  public:
    // CELLS
    VVX_define_VX_mem_bus_if__D40_T30* __PVT__tb_fdr_top__DOT__metacache_mem_if;
    VVX_define_VX_mem_bus_if__D40_T30* __PVT__tb_fdr_top__DOT__bitstream_cache_mem_if;
    VVX_define_cta_sched_if* __PVT__tb_fdr_top__DOT__schedule_if;
    VVX_define_fdr_if* __PVT__tb_fdr_top__DOT__fdr_if;
    VVX_define_simt_stack_status_if* __PVT__tb_fdr_top__DOT__simt_status_if;

    // DESIGN SPECIFIC STATE
    // Anonymous structures to workaround compiler member-count bugs
    struct {
        VL_IN8(dice_ram_1w1r__02Eclk,0,0);
        VL_IN8(dice_ram_1rw__02Eclk,0,0);
        VL_IN8(wr_en,0,0);
        VL_IN8(rd_en,0,0);
        VL_IN8(en,0,0);
        VL_IN8(we,0,0);
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
        CData/*0:0*/ __Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q;
        CData/*0:0*/ __Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal;
        CData/*0:0*/ __VstlFirstIteration;
        CData/*0:0*/ __Vtrigprevexpr___TOP__dice_ram_1w1r__02Eclk__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__dice_ram_1rw__02Eclk__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__clk__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__rst__0;
        CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal__0;
        CData/*0:0*/ __Vtrigprevexpr_he86f48af__1;
        CData/*0:0*/ __Vtrigprevexpr_h0e98381b__1;
        CData/*0:0*/ __Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0;
        CData/*0:0*/ __VactDidInit;
        VL_IN16(wr_addr,9,0);
        VL_IN16(rd_addr,9,0);
        VL_IN16(addr,9,0);
        VL_IN(wr_data,31,0);
        VL_OUT(rd_data,31,0);
        VL_IN(wdata,31,0);
        VL_OUT(rdata,31,0);
        IData/*31:0*/ dice_ram_1w1r__DOT__rd_data_reg;
        IData/*31:0*/ dice_ram_1rw__DOT__rdata_reg;
        IData/*31:0*/ tb_fdr_top__DOT__cycle_count;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q;
        IData/*29:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_cache_req_addr_q;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q;
        IData/*31:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d;
    };
    struct {
        IData/*31:0*/ __VactIterCount;
        VlWide<5>/*139:0*/ tb_fdr_top__DOT__cta_status_data_i;
        VlWide<5>/*156:0*/ tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q;
        VlWide<5>/*156:0*/ __Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q;
        VlUnpacked<IData/*31:0*/, 1024> dice_ram_1w1r__DOT__ram_array;
        VlUnpacked<IData/*31:0*/, 1024> dice_ram_1rw__DOT__ram_array;
        VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
        VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    };
    VlDelayScheduler __VdlySched;
    VlTriggerScheduler __VtrigSched_h416eaf98__0;
    VlTriggerScheduler __VtrigSched_hda9fe986__0;
    VlTriggerScheduler __VtrigSched_h40580101__0;
    VlTriggerScheduler __VtrigSched_h969ff5c5__0;
    VlTriggerScheduler __VtrigSched_hd8d198eb__0;

    // INTERNAL VARIABLES
    VVX_define__Syms* const vlSymsp;

    // CONSTRUCTORS
    VVX_define___024root(VVX_define__Syms* symsp, const char* v__name);
    ~VVX_define___024root();
    VL_UNCOPYABLE(VVX_define___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
