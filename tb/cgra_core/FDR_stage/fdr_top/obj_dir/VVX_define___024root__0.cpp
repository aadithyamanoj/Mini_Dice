// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

VL_ATTR_COLD void VVX_define___024root___eval_initial__TOP(VVX_define___024root* vlSelf);
VlCoroutine VVX_define___024root___eval_initial__TOP__Vtiming__0(VVX_define___024root* vlSelf);
VlCoroutine VVX_define___024root___eval_initial__TOP__Vtiming__1(VVX_define___024root* vlSelf);

void VVX_define___024root___eval_initial(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_initial\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    VVX_define___024root___eval_initial__TOP(vlSelf);
    VVX_define___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    VVX_define___024root___eval_initial__TOP__Vtiming__1(vlSelf);
}

VlCoroutine VVX_define___024root___eval_initial__TOP__Vtiming__0(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_initial__TOP__Vtiming__0\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.tb_fdr_top__DOT__clk = 0U;
    while (true) {
        co_await vlSelfRef.__VdlySched.delay(0x0000000000001388ULL, 
                                             nullptr, 
                                             "tb_fdr_top.sv", 
                                             77);
        vlSelfRef.tb_fdr_top__DOT__clk = (1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__clk)));
    }
}

extern const VlWide<23>/*735:0*/ VVX_define__ConstPool__CONST_haa6c2484_0;
extern const VlWide<73>/*2335:0*/ VVX_define__ConstPool__CONST_h7ecf2001_0;
extern const VlWide<18>/*575:0*/ VVX_define__ConstPool__CONST_h775a3ab6_0;
extern const VlWide<22>/*703:0*/ VVX_define__ConstPool__CONST_h22442289_0;
extern const VlWide<17>/*543:0*/ VVX_define__ConstPool__CONST_h81900e86_0;
extern const VlWide<19>/*607:0*/ VVX_define__ConstPool__CONST_h53b58f1b_0;

VlCoroutine VVX_define___024root___eval_initial__TOP__Vtiming__1(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_initial__TOP__Vtiming__1\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    VlWide<23>/*720:0*/ tb_fdr_top__DOT__unnamedblk1__DOT__sched;
    VL_ZERO_W(721, tb_fdr_top__DOT__unnamedblk1__DOT__sched);
    VlWide<5>/*156:0*/ tb_fdr_top__DOT__unnamedblk1__DOT__meta;
    VL_ZERO_W(157, tb_fdr_top__DOT__unnamedblk1__DOT__meta);
    IData/*31:0*/ tb_fdr_top__DOT__unnamedblk1__DOT__start_pc;
    tb_fdr_top__DOT__unnamedblk1__DOT__start_pc = 0;
    IData/*31:0*/ tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i;
    tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i = 0;
    IData/*31:0*/ __Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0;
    __Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0 = 0;
    // Body
    VL_WRITEF_NX("tb_fdr_top (happy-path)\n",0);
    vlSelfRef.tb_fdr_top__DOT__rst = 1U;
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[1U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[1U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[2U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[2U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[3U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[3U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[4U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[4U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[5U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[6U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[6U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[7U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[7U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[8U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[8U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[9U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[9U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000aU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000aU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000bU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000bU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000cU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000cU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000dU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000dU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000eU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000eU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000fU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000fU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000010U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000010U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000011U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000011U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000012U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000012U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000013U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000013U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000014U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000014U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000015U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000016U];
    vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.ready = 1U;
    IData/*31:0*/ __Vilp1;
    __Vilp1 = 0U;
    while ((__Vilp1 <= 0x00000048U)) {
        vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[__Vilp1] 
            = VVX_define__ConstPool__CONST_h7ecf2001_0[__Vilp1];
        __Vilp1 = ((IData)(1U) + __Vilp1);
    }
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.req_ready = 1U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_valid = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[1U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[1U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[2U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[2U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[3U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[3U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[4U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[4U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[5U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[5U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[6U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[6U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[7U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[7U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[8U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[8U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[9U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[9U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000aU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000aU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000bU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000bU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000cU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000cU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000dU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000dU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000eU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000eU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000fU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000fU];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x00000010U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x00000010U];
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x00000011U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x00000011U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.req_ready = 1U;
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_valid = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[1U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[1U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[2U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[2U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[3U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[3U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[4U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[4U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[5U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[5U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[6U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[6U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[7U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[7U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[8U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[8U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[9U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[9U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000aU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000aU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000bU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000bU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000cU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000cU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000dU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000dU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000eU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000eU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000fU] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x0000000fU];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x00000010U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x00000010U];
    vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x00000011U] 
        = VVX_define__ConstPool__CONST_h775a3ab6_0[0x00000011U];
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[0U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[1U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[2U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[3U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[4U] = 0U;
    __Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0 = 5U;
    while (VL_LTS_III(32, 0U, __Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0)) {
        co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_fdr_top.clk)", 
                                                             "tb_fdr_top.sv", 
                                                             109);
        __Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0 
            = (__Vtask_tb_fdr_top__DOT__reset_dut__0__tb_fdr_top__DOT__unnamedblk1_1__DOT____Vrepeat0 
               - (IData)(1U));
    }
    vlSelfRef.tb_fdr_top__DOT__rst = 0U;
    co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_fdr_top.clk)", 
                                                         "tb_fdr_top.sv", 
                                                         111);
    tb_fdr_top__DOT__unnamedblk1__DOT__start_pc = 0x00001000U;
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[0U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[1U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[1U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[2U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[2U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[3U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[3U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[4U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[4U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[5U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[5U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[6U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[6U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[7U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[7U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[8U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[8U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[9U] = 
        VVX_define__ConstPool__CONST_haa6c2484_0[9U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000aU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000aU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000bU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000bU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000cU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000cU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000dU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000dU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000eU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000eU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000fU] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x0000000fU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000010U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000010U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000011U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000011U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000012U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000012U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000013U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000013U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000014U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000014U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000015U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000015U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000016U] 
        = VVX_define__ConstPool__CONST_haa6c2484_0[0x00000016U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0U] = 
        VVX_define__ConstPool__CONST_h22442289_0[0U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[1U] = 
        VVX_define__ConstPool__CONST_h22442289_0[1U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[2U] = 
        VVX_define__ConstPool__CONST_h22442289_0[2U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[3U] = 
        VVX_define__ConstPool__CONST_h22442289_0[3U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[4U] = 
        VVX_define__ConstPool__CONST_h22442289_0[4U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[5U] = 
        VVX_define__ConstPool__CONST_h22442289_0[5U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[6U] = 
        VVX_define__ConstPool__CONST_h22442289_0[6U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[7U] = 
        VVX_define__ConstPool__CONST_h22442289_0[7U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[8U] = 
        VVX_define__ConstPool__CONST_h22442289_0[8U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[9U] = 
        VVX_define__ConstPool__CONST_h22442289_0[9U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000aU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000aU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000bU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000bU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000cU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000cU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000dU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000dU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000eU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000eU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000fU] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x0000000fU];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000010U] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x00000010U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000011U] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x00000011U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000012U] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x00000012U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000013U] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x00000013U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000014U] 
        = VVX_define__ConstPool__CONST_h22442289_0[0x00000014U];
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000015U] 
        = (((IData)((QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc))) 
            << 0x0000000fU) | VVX_define__ConstPool__CONST_h22442289_0[0x00000015U]);
    tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000016U] 
        = (((IData)((QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc))) 
            >> 0x00000011U) | ((IData)(((QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc)) 
                                        >> 0x00000020U)) 
                               << 0x0000000fU));
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000011U] 
        = ((3U & vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000011U]) 
           | ((IData)((0x0000000100000000ULL | (QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc)))) 
              << 2U));
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000012U] 
        = ((0xfffffff8U & vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000012U]) 
           | (((IData)((0x0000000100000000ULL | (QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc)))) 
               >> 0x0000001eU) | ((IData)(((0x0000000100000000ULL 
                                            | (QData)((IData)(tb_fdr_top__DOT__unnamedblk1__DOT__start_pc))) 
                                           >> 0x00000020U)) 
                                  << 2U)));
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[1U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[1U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[2U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[2U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[3U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[3U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[4U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[4U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[5U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[5U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[6U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[6U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[7U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[7U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[8U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[8U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[9U] 
        = VVX_define__ConstPool__CONST_h81900e86_0[9U];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000aU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000aU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000bU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000bU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000cU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000cU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000dU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000dU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000eU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000eU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x0000000fU] 
        = VVX_define__ConstPool__CONST_h81900e86_0[0x0000000fU];
    vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000010U] 
        = ((0xfffffffcU & vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[0x00000010U]) 
           | VVX_define__ConstPool__CONST_h81900e86_0[0x00000010U]);
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[0U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[1U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[2U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[3U] = 0U;
    vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[4U] = 0U;
    while ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal)))) {
        co_await vlSelfRef.__VtrigSched_hda9fe986__0.trigger(1U, 
                                                             nullptr, 
                                                             "@( tb_fdr_top.u_dut.schedule_ready_internal)", 
                                                             "tb_fdr_top.sv", 
                                                             151);
    }
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[1U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[1U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[2U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[2U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[3U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[3U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[4U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[4U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[5U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[6U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[6U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[7U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[7U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[8U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[8U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[9U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[9U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000aU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000aU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000bU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000bU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000cU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000cU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000dU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000dU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000eU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000eU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x0000000fU] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x0000000fU];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000010U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000010U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000011U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000011U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000012U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000012U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000013U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000013U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000014U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000014U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000015U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
        = tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000016U];
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid = 1U;
    co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_fdr_top.clk)", 
                                                         "tb_fdr_top.sv", 
                                                         154);
    vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U] = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[1U] = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[2U] = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U] = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[4U] = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U] = (0x00800000U 
                                                   | (0x001fffffU 
                                                      & tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U]));
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[4U] = 0x00000400U;
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U] = (0xfeffffffU 
                                                   & tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U]);
    tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U] = (0xfffffffdU 
                                                   & tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U]);
    while ((1U != (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q))) {
        co_await vlSelfRef.__VtrigSched_h40580101__0.trigger(1U, 
                                                             nullptr, 
                                                             "@( (2'h1 == tb_fdr_top.u_dut.u_meta_fetch.state_q))", 
                                                             "tb_fdr_top.sv", 
                                                             164);
    }
    co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_fdr_top.clk)", 
                                                         "tb_fdr_top.sv", 
                                                         165);
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_valid = 1U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0U] 
        = (IData)((0x0000ffffffffffffULL & (((QData)((IData)(
                                                             VVX_define__ConstPool__CONST_h53b58f1b_0[0U])) 
                                             << 0x00000020U) 
                                            | (QData)((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q)))));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[1U] 
        = (IData)(((0x0000ffffffffffffULL & (((QData)((IData)(
                                                              VVX_define__ConstPool__CONST_h53b58f1b_0[0U])) 
                                              << 0x00000020U) 
                                             | (QData)((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q)))) 
                   >> 0x00000020U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[2U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[3U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[4U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[5U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[6U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[7U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[8U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[9U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000aU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000bU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000cU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000dU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000eU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x0000000fU] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x00000010U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0x00000011U] = 0U;
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[1U] 
        = ((0x0000ffffU & vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[1U]) 
           | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U] 
              << 0x00000010U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[2U] 
        = ((tb_fdr_top__DOT__unnamedblk1__DOT__meta[0U] 
            >> 0x00000010U) | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[1U] 
                               << 0x00000010U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[3U] 
        = ((tb_fdr_top__DOT__unnamedblk1__DOT__meta[1U] 
            >> 0x00000010U) | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[2U] 
                               << 0x00000010U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[4U] 
        = ((tb_fdr_top__DOT__unnamedblk1__DOT__meta[2U] 
            >> 0x00000010U) | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U] 
                               << 0x00000010U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[5U] 
        = ((tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U] 
            >> 0x00000010U) | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[4U] 
                               << 0x00000010U));
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[6U] 
        = ((0xffffe000U & vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[6U]) 
           | (tb_fdr_top__DOT__unnamedblk1__DOT__meta[4U] 
              >> 0x00000010U));
    co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_fdr_top.clk)", 
                                                         "tb_fdr_top.sv", 
                                                         170);
    vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_valid = 0U;
    tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i = 0U;
    while (VL_GTS_III(32, 4U, tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i)) {
        while ((1U & (~ ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q)) 
                         & (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)))))) {
            co_await vlSelfRef.__VtrigSched_h969ff5c5__0.trigger(1U, 
                                                                 nullptr, 
                                                                 "@( ((~ tb_fdr_top.u_dut.u_bitstream_fetch_load.req_sent_q) & (2'h1 == tb_fdr_top.u_dut.u_bitstream_fetch_load.state_q)))", 
                                                                 "tb_fdr_top.sv", 
                                                                 175);
        }
        co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_fdr_top.clk)", 
                                                             "tb_fdr_top.sv", 
                                                             176);
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_valid = 1U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0U] 
            = (IData)((0x0000ffffffffffffULL & (((QData)((IData)(
                                                                 VVX_define__ConstPool__CONST_h53b58f1b_0[0U])) 
                                                 << 0x00000020U) 
                                                | (QData)((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q)))));
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[1U] 
            = (IData)(((0x0000ffffffffffffULL & (((QData)((IData)(
                                                                  VVX_define__ConstPool__CONST_h53b58f1b_0[0U])) 
                                                  << 0x00000020U) 
                                                 | (QData)((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q)))) 
                       >> 0x00000020U));
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[2U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[3U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[4U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[5U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[6U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[7U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[8U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[9U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000aU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000bU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000cU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000dU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000eU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x0000000fU] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x00000010U] = 0U;
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0x00000011U] = 0U;
        co_await vlSelfRef.__VtrigSched_h416eaf98__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_fdr_top.clk)", 
                                                             "tb_fdr_top.sv", 
                                                             180);
        vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_valid = 0U;
        tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i 
            = ((IData)(1U) + tb_fdr_top__DOT__unnamedblk1__DOT__unnamedblk2__DOT__i);
    }
    while ((1U & (~ (IData)(vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.valid)))) {
        co_await vlSelfRef.__VtrigSched_hd8d198eb__0.trigger(1U, 
                                                             nullptr, 
                                                             "@( tb_fdr_top.fdr_if.valid)", 
                                                             "tb_fdr_top.sv", 
                                                             184);
    }
    if (vlSymsp->_vm_contextp__->assertOnGet(2, 1)) {
        if (VL_UNLIKELY((((3U & (vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.data[0x00000018U] 
                                 >> 0x00000014U)) != 
                          (3U & (tb_fdr_top__DOT__unnamedblk1__DOT__sched[0x00000016U] 
                                 >> 0x0000000fU)))))) {
            VL_WRITEF_NX("[%0t] %%Fatal: tb_fdr_top.sv:186: Assertion failed in %Ntb_fdr_top.unnamedblk1: schedule_hw_cta_id mismatch\n",0,
                         64,VL_TIME_UNITED_Q(1000),
                         -9,vlSymsp->name());
            VL_STOP_MT("tb_fdr_top.sv", 186, "", false);
        }
    }
    if (vlSymsp->_vm_contextp__->assertOnGet(2, 1)) {
        if (VL_UNLIKELY((((0x000000ffU & ((vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.data[3U] 
                                           << 2U) | 
                                          (vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.data[2U] 
                                           >> 0x0000001eU))) 
                          != (0x000000ffU & (tb_fdr_top__DOT__unnamedblk1__DOT__meta[3U] 
                                             >> 0x00000015U)))))) {
            VL_WRITEF_NX("[%0t] %%Fatal: tb_fdr_top.sv:188: Assertion failed in %Ntb_fdr_top.unnamedblk1: metadata.bitstream_length mismatch\n",0,
                         64,VL_TIME_UNITED_Q(1000),
                         -9,vlSymsp->name());
            VL_STOP_MT("tb_fdr_top.sv", 188, "", false);
        }
    }
    VL_WRITEF_NX("PASS: fdr_top produced valid output\n",0);
    VL_FINISH_MT("tb_fdr_top.sv", 194, "");
}

#ifdef VL_DEBUG
VL_ATTR_COLD void VVX_define___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void VVX_define___024root___eval_triggers__act(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_triggers__act\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __Vtrigprevexpr_he86f48af__0;
    __Vtrigprevexpr_he86f48af__0 = 0;
    CData/*0:0*/ __Vtrigprevexpr_h0e98381b__0;
    __Vtrigprevexpr_h0e98381b__0 = 0;
    // Body
    __Vtrigprevexpr_he86f48af__0 = (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q));
    __Vtrigprevexpr_h0e98381b__0 = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q)) 
                                    & (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)));
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((((IData)(vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.valid) 
                                                       != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0)) 
                                                      << 8U) 
                                                     | (((((((IData)(__Vtrigprevexpr_h0e98381b__0) 
                                                             != (IData)(vlSelfRef.__Vtrigprevexpr_h0e98381b__1)) 
                                                            << 3U) 
                                                           | (((IData)(__Vtrigprevexpr_he86f48af__0) 
                                                               != (IData)(vlSelfRef.__Vtrigprevexpr_he86f48af__1)) 
                                                              << 2U)) 
                                                          | ((((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal) 
                                                               != (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal__0)) 
                                                              << 1U) 
                                                             | vlSelfRef.__VdlySched.awaitingCurrentTime())) 
                                                         << 4U) 
                                                        | (((((IData)(vlSelfRef.tb_fdr_top__DOT__rst) 
                                                              & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__rst__0))) 
                                                             << 3U) 
                                                            | (((IData)(vlSelfRef.tb_fdr_top__DOT__clk) 
                                                                & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__clk__0))) 
                                                               << 2U)) 
                                                           | ((((IData)(vlSelfRef.dice_ram_1rw__02Eclk) 
                                                                & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__dice_ram_1rw__02Eclk__0))) 
                                                               << 1U) 
                                                              | ((IData)(vlSelfRef.dice_ram_1w1r__02Eclk) 
                                                                 & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__dice_ram_1w1r__02Eclk__0)))))))));
    vlSelfRef.__Vtrigprevexpr___TOP__dice_ram_1w1r__02Eclk__0 
        = vlSelfRef.dice_ram_1w1r__02Eclk;
    vlSelfRef.__Vtrigprevexpr___TOP__dice_ram_1rw__02Eclk__0 
        = vlSelfRef.dice_ram_1rw__02Eclk;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__clk__0 
        = vlSelfRef.tb_fdr_top__DOT__clk;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__rst__0 
        = vlSelfRef.tb_fdr_top__DOT__rst;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal__0 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal;
    vlSelfRef.__Vtrigprevexpr_he86f48af__1 = __Vtrigprevexpr_he86f48af__0;
    vlSelfRef.__Vtrigprevexpr_h0e98381b__1 = __Vtrigprevexpr_h0e98381b__0;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0 
        = vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.valid;
    if (VL_UNLIKELY(((1U & (~ (IData)(vlSelfRef.__VactDidInit)))))) {
        vlSelfRef.__VactDidInit = 1U;
        vlSelfRef.__VactTriggered[0U] = (0x0000000000000020ULL 
                                         | vlSelfRef.__VactTriggered
                                         [0U]);
        vlSelfRef.__VactTriggered[0U] = (0x0000000000000040ULL 
                                         | vlSelfRef.__VactTriggered
                                         [0U]);
        vlSelfRef.__VactTriggered[0U] = (0x0000000000000080ULL 
                                         | vlSelfRef.__VactTriggered
                                         [0U]);
        vlSelfRef.__VactTriggered[0U] = (0x0000000000000100ULL 
                                         | vlSelfRef.__VactTriggered
                                         [0U]);
    }
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        VVX_define___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool VVX_define___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

extern const VlUnpacked<CData/*0:0*/, 128> VVX_define__ConstPool__TABLE_hab3087f5_0;
extern const VlUnpacked<CData/*1:0*/, 128> VVX_define__ConstPool__TABLE_h0e3ac2b6_0;

void VVX_define___024root___act_comb__TOP__0(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___act_comb__TOP__0\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0;
    tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0 = 0;
    CData/*6:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    // Body
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire 
        = ((IData)(vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_valid) 
           & ((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)) 
              & (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0U] 
                 == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q)));
    tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0 
        = (((IData)(vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_valid) 
            & ((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
               & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q))) 
           & (vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0U] 
              == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match 
        = (((vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
             << 0x00000011U) | (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
                                >> 0x0000000fU)) == 
           (((0U == (0x0000001fU & ((IData)(0x00000222U) 
                                    + (0x00000fffU 
                                       & ((IData)(0x00000243U) 
                                          * (3U & (
                                                   vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                   >> 0x0000000fU)))))))
              ? 0U : (vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[
                      (((IData)(0x00000241U) + (0x00000fffU 
                                                & ((IData)(0x00000243U) 
                                                   * 
                                                   (3U 
                                                    & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                       >> 0x0000000fU))))) 
                       >> 5U)] << ((IData)(0x00000020U) 
                                   - (0x0000001fU & 
                                      ((IData)(0x00000222U) 
                                       + (0x00000fffU 
                                          & ((IData)(0x00000243U) 
                                             * (3U 
                                                & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                   >> 0x0000000fU))))))))) 
            | (vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[
               (((IData)(0x00000222U) + (0x00000fffU 
                                         & ((IData)(0x00000243U) 
                                            * (3U & 
                                               (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                >> 0x0000000fU))))) 
                >> 5U)] >> (0x0000001fU & ((IData)(0x00000222U) 
                                           + (0x00000fffU 
                                              & ((IData)(0x00000243U) 
                                                 * 
                                                 (3U 
                                                  & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                     >> 0x0000000fU)))))))));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0 
        = (1U & (~ (vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[
                    (((IData)(0x00000022U) + (0x000000ffU 
                                              & ((IData)(0x00000023U) 
                                                 * 
                                                 (3U 
                                                  & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                     >> 0x0000000fU))))) 
                     >> 5U)] >> (0x0000001fU & ((IData)(0x00000022U) 
                                                + (0x000000ffU 
                                                   & ((IData)(0x00000023U) 
                                                      * 
                                                      (3U 
                                                       & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                          >> 0x0000000fU)))))))));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required 
        = ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0) 
           & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
              >> 0x0000000bU));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal 
        = (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o) 
            & ((~ (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
                   >> 0x0000000bU)) & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal) 
                                       & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0) 
                                          & ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required)) 
                                             | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match)))))) 
           & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.ready));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal 
        = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match)) 
           & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q;
    __Vtableidx1 = ((((((IData)(vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid) 
                        << 3U) | (((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)) 
                                   & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.req_ready)) 
                                  << 2U)) | (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire) 
                                              << 1U) 
                                             | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal))) 
                     << 3U) | (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal) 
                                << 2U) | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal 
        = VVX_define__ConstPool__TABLE_hab3087f5_0[__Vtableidx1];
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_d 
        = VVX_define__ConstPool__TABLE_h0e3ac2b6_0[__Vtableidx1];
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q;
    if ((0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal) {
            if ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o)))) {
                if ((1U & (~ (((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q)) 
                               & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q)) 
                              & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q 
                                 == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                      << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                                >> 0x0000001dU))))))) {
                    if ((1U & (~ (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) 
                                   & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q)) 
                                  & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q 
                                     == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                          << 3U) | 
                                         (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU))))))) {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 1U;
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d = 0U;
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
                            = ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU));
                    }
                }
            }
        }
    } else if ((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 0U;
        } else if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q) {
            if (tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0) {
                vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
                if ((3U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q))) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 2U;
                }
            }
        } else if ((((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q)) 
                     & (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) 
                    & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.req_ready))) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 1U;
        }
        if ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal)))) {
            if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q) {
                if (tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d 
                        = (7U & ((IData)(1U) + (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q)));
                    if ((3U != (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q))) {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
                            = ((IData)(0x00000040U) 
                               + vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q);
                    }
                }
            }
        }
    } else {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 0U;
    }
}

void VVX_define_fdr_if___act_comb__TOP__tb_fdr_top__DOT__fdr_if__0(VVX_define_fdr_if* vlSelf);
void VVX_define_fdr_if___act_comb__TOP__tb_fdr_top__DOT__fdr_if__1(VVX_define_fdr_if* vlSelf);

void VVX_define___024root___eval_act(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_act\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((0x00000000000001e4ULL & vlSelfRef.__VactTriggered
         [0U])) {
        VVX_define_fdr_if___act_comb__TOP__tb_fdr_top__DOT__fdr_if__0((&vlSymsp->TOP__tb_fdr_top__DOT__fdr_if));
        VVX_define___024root___act_comb__TOP__0(vlSelf);
        VVX_define_fdr_if___act_comb__TOP__tb_fdr_top__DOT__fdr_if__1((&vlSymsp->TOP__tb_fdr_top__DOT__fdr_if));
    }
}

void VVX_define___024root___nba_sequent__TOP__0(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___nba_sequent__TOP__0\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (vlSymsp->_vm_contextp__->assertOnGet(1, 1)) {
        if (VL_UNLIKELY(((1U & (~ ((~ ((~ (IData)(vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q)) 
                                       & (IData)(vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal))) 
                                   | (~ (vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[0U] 
                                         >> 0x00000018U)))))))) {
            VL_WRITEF_NX("[%0t] %%Error: branch_handler_no_branches.sv:127: Assertion failed in %Ntb_fdr_top.u_dut.u_branch_handler: 'assert' failed.\n",0,
                         64,VL_TIME_UNITED_Q(1000),
                         -9,vlSymsp->name());
            VL_STOP_MT("/Users/elliotn/Code/vortex4dice/dice_new/rtl/cgra_core/fetch_stage/branch_handler_no_branches.sv", 127, "");
        }
    }
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q 
        = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__rst)) 
           & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q 
        = ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__rst))) 
           && (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q 
        = ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__rst))) 
           && (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q 
        = ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__rst))) 
           && (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q 
        = ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__rst))) 
           && (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d));
    if (vlSelfRef.tb_fdr_top__DOT__rst) {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[0U] = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[1U] = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[2U] = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_cache_req_addr_q = 0U;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q = 0U;
    } else {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q 
            = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q 
            = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q 
            = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d;
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q = 0U;
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q = 1U;
        }
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q = 1U;
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[0U] 
                = ((vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[2U] 
                    << 0x00000010U) | (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[1U] 
                                       >> 0x00000010U));
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[1U] 
                = ((vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[3U] 
                    << 0x00000010U) | (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[2U] 
                                       >> 0x00000010U));
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[2U] 
                = ((vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[4U] 
                    << 0x00000010U) | (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[3U] 
                                       >> 0x00000010U));
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                = ((vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[5U] 
                    << 0x00000010U) | (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[4U] 
                                       >> 0x00000010U));
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                = (0x1fffffffU & ((vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[6U] 
                                   << 0x00000010U) 
                                  | (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[5U] 
                                     >> 0x00000010U)));
        }
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q = 0U;
        }
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q 
            = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d;
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q 
            = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d;
        if ((((0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)) 
              & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid)) 
             & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal))) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q = 0U;
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_cache_req_addr_q 
                = (0x3fffffffU & VL_SHIFTR_III(30,32,32, 
                                               ((vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                 << 0x00000011U) 
                                                | (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
                                                   >> 0x0000000fU)), 6U));
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q 
                = ((vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                    << 0x00000011U) | (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
                                       >> 0x0000000fU));
        }
    }
    if ((1U & (~ VL_ONEHOT_I((((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
                               << 2U) | (((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
                                          << 1U) | 
                                         (0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)))))))) {
        if ((0U != (((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
                     << 2U) | (((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
                                << 1U) | (0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)))))) {
            if (VL_UNLIKELY((vlSymsp->_vm_contextp__->assertOn()))) {
                VL_WRITEF_NX("[%0t] %%Error: bitstream_fetch_load.sv:132: Assertion failed in %Ntb_fdr_top.u_dut.u_bitstream_fetch_load: unique case, but multiple matches found for '2'h%x'\n",0,
                             64,VL_TIME_UNITED_Q(1000),
                             -9,vlSymsp->name(),2,(IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q));
                VL_STOP_MT("/Users/elliotn/Code/vortex4dice/dice_new/rtl/cgra_core/fetch_stage/bitstream_fetch_load.sv", 132, "");
            }
        }
    }
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q 
        = ((IData)(vlSelfRef.tb_fdr_top__DOT__rst) ? 0U
            : (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_d));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o 
        = (((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q)) 
            & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q) 
               & (((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                    << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                              >> 0x0000001dU)) == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q))) 
           | ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) 
              & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q) 
                 & (((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                      << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                >> 0x0000001dU)) == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q))));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal 
        = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q)) 
           & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q;
    if ((0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal) {
            if ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o)))) {
                if ((((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q)) 
                      & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q)) 
                     & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q 
                        == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                             << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                       >> 0x0000001dU))))) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d = 1U;
                } else if ((((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) 
                             & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q)) 
                            & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q 
                               == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                    << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                              >> 0x0000001dU))))) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d = 0U;
                } else {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d 
                        = (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q) 
                            | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q)) 
                           & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q)));
                    if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d) {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d 
                            = ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU));
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d = 0U;
                    } else {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d 
                            = ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU));
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d = 0U;
                    }
                }
            }
        }
    } else if ((1U != (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        if ((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
            if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) {
                vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d = 1U;
            } else {
                vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d = 1U;
            }
        }
    }
}

void VVX_define___024root___nba_sequent__TOP__1(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___nba_sequent__TOP__1\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VdlyVal__dice_ram_1w1r__DOT__ram_array__v0;
    __VdlyVal__dice_ram_1w1r__DOT__ram_array__v0 = 0;
    SData/*9:0*/ __VdlyDim0__dice_ram_1w1r__DOT__ram_array__v0;
    __VdlyDim0__dice_ram_1w1r__DOT__ram_array__v0 = 0;
    CData/*0:0*/ __VdlySet__dice_ram_1w1r__DOT__ram_array__v0;
    __VdlySet__dice_ram_1w1r__DOT__ram_array__v0 = 0;
    // Body
    __VdlySet__dice_ram_1w1r__DOT__ram_array__v0 = 0U;
    if (vlSelfRef.wr_en) {
        __VdlyVal__dice_ram_1w1r__DOT__ram_array__v0 
            = vlSelfRef.wr_data;
        __VdlyDim0__dice_ram_1w1r__DOT__ram_array__v0 
            = vlSelfRef.wr_addr;
        __VdlySet__dice_ram_1w1r__DOT__ram_array__v0 = 1U;
    }
    if (vlSelfRef.rd_en) {
        vlSelfRef.dice_ram_1w1r__DOT__rd_data_reg = 
            vlSelfRef.dice_ram_1w1r__DOT__ram_array
            [vlSelfRef.rd_addr];
    }
    if (__VdlySet__dice_ram_1w1r__DOT__ram_array__v0) {
        vlSelfRef.dice_ram_1w1r__DOT__ram_array[__VdlyDim0__dice_ram_1w1r__DOT__ram_array__v0] 
            = __VdlyVal__dice_ram_1w1r__DOT__ram_array__v0;
    }
    vlSelfRef.rd_data = vlSelfRef.dice_ram_1w1r__DOT__rd_data_reg;
}

void VVX_define___024root___nba_sequent__TOP__2(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___nba_sequent__TOP__2\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VdlyVal__dice_ram_1rw__DOT__ram_array__v0;
    __VdlyVal__dice_ram_1rw__DOT__ram_array__v0 = 0;
    SData/*9:0*/ __VdlyDim0__dice_ram_1rw__DOT__ram_array__v0;
    __VdlyDim0__dice_ram_1rw__DOT__ram_array__v0 = 0;
    CData/*0:0*/ __VdlySet__dice_ram_1rw__DOT__ram_array__v0;
    __VdlySet__dice_ram_1rw__DOT__ram_array__v0 = 0;
    // Body
    __VdlySet__dice_ram_1rw__DOT__ram_array__v0 = 0U;
    if (((IData)(vlSelfRef.en) & (IData)(vlSelfRef.we))) {
        __VdlyVal__dice_ram_1rw__DOT__ram_array__v0 
            = vlSelfRef.wdata;
        __VdlyDim0__dice_ram_1rw__DOT__ram_array__v0 
            = vlSelfRef.addr;
        __VdlySet__dice_ram_1rw__DOT__ram_array__v0 = 1U;
    }
    if (((IData)(vlSelfRef.en) & (~ (IData)(vlSelfRef.we)))) {
        vlSelfRef.dice_ram_1rw__DOT__rdata_reg = vlSelfRef.dice_ram_1rw__DOT__ram_array
            [vlSelfRef.addr];
    }
    if (__VdlySet__dice_ram_1rw__DOT__ram_array__v0) {
        vlSelfRef.dice_ram_1rw__DOT__ram_array[__VdlyDim0__dice_ram_1rw__DOT__ram_array__v0] 
            = __VdlyVal__dice_ram_1rw__DOT__ram_array__v0;
    }
    vlSelfRef.rdata = vlSelfRef.dice_ram_1rw__DOT__rdata_reg;
}

void VVX_define___024root___nba_sequent__TOP__3(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___nba_sequent__TOP__3\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __Vdly__tb_fdr_top__DOT__cycle_count;
    __Vdly__tb_fdr_top__DOT__cycle_count = 0;
    // Body
    __Vdly__tb_fdr_top__DOT__cycle_count = vlSelfRef.tb_fdr_top__DOT__cycle_count;
    if (vlSelfRef.tb_fdr_top__DOT__rst) {
        __Vdly__tb_fdr_top__DOT__cycle_count = 0U;
    } else {
        __Vdly__tb_fdr_top__DOT__cycle_count = ((IData)(1U) 
                                                + vlSelfRef.tb_fdr_top__DOT__cycle_count);
        if (VL_UNLIKELY((VL_LTES_III(32, 0x00001388U, vlSelfRef.tb_fdr_top__DOT__cycle_count)))) {
            VL_WRITEF_NX("[%0t] %%Fatal: tb_fdr_top.sv:84: Assertion failed in %Ntb_fdr_top: TIMEOUT\n",0,
                         64,VL_TIME_UNITED_Q(1000),
                         -9,vlSymsp->name());
            VL_STOP_MT("tb_fdr_top.sv", 84, "", false);
        }
    }
    vlSelfRef.tb_fdr_top__DOT__cycle_count = __Vdly__tb_fdr_top__DOT__cycle_count;
}

void VVX_define___024root___nba_comb__TOP__0(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___nba_comb__TOP__0\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0;
    tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0 = 0;
    CData/*6:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    // Body
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match 
        = (((vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
             << 0x00000011U) | (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000015U] 
                                >> 0x0000000fU)) == 
           (((0U == (0x0000001fU & ((IData)(0x00000222U) 
                                    + (0x00000fffU 
                                       & ((IData)(0x00000243U) 
                                          * (3U & (
                                                   vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                   >> 0x0000000fU)))))))
              ? 0U : (vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[
                      (((IData)(0x00000241U) + (0x00000fffU 
                                                & ((IData)(0x00000243U) 
                                                   * 
                                                   (3U 
                                                    & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                       >> 0x0000000fU))))) 
                       >> 5U)] << ((IData)(0x00000020U) 
                                   - (0x0000001fU & 
                                      ((IData)(0x00000222U) 
                                       + (0x00000fffU 
                                          & ((IData)(0x00000243U) 
                                             * (3U 
                                                & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                   >> 0x0000000fU))))))))) 
            | (vlSymsp->TOP__tb_fdr_top__DOT__simt_status_if.status[
               (((IData)(0x00000222U) + (0x00000fffU 
                                         & ((IData)(0x00000243U) 
                                            * (3U & 
                                               (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                >> 0x0000000fU))))) 
                >> 5U)] >> (0x0000001fU & ((IData)(0x00000222U) 
                                           + (0x00000fffU 
                                              & ((IData)(0x00000243U) 
                                                 * 
                                                 (3U 
                                                  & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                     >> 0x0000000fU)))))))));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0 
        = (1U & (~ (vlSelfRef.tb_fdr_top__DOT__cta_status_data_i[
                    (((IData)(0x00000022U) + (0x000000ffU 
                                              & ((IData)(0x00000023U) 
                                                 * 
                                                 (3U 
                                                  & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                     >> 0x0000000fU))))) 
                     >> 5U)] >> (0x0000001fU & ((IData)(0x00000022U) 
                                                + (0x000000ffU 
                                                   & ((IData)(0x00000023U) 
                                                      * 
                                                      (3U 
                                                       & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[0x00000016U] 
                                                          >> 0x0000000fU)))))))));
    tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0 
        = (((IData)(vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_valid) 
            & ((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)) 
               & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q))) 
           & (vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.rsp_data[0U] 
              == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire 
        = ((IData)(vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_valid) 
           & ((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)) 
              & (vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.rsp_data[0U] 
                 == vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q)));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required 
        = ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0) 
           & (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
              >> 0x0000000bU));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal 
        = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match)) 
           & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal 
        = (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o) 
            & ((~ (vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.data[5U] 
                   >> 0x0000000bU)) & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal) 
                                       & ((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0) 
                                          & ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required)) 
                                             | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match)))))) 
           & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.ready));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q;
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q;
    if ((0U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal) {
            if ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o)))) {
                if ((1U & (~ (((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q)) 
                               & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q)) 
                              & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q 
                                 == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                      << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                                >> 0x0000001dU))))))) {
                    if ((1U & (~ (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) 
                                   & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q)) 
                                  & (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q 
                                     == ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                          << 3U) | 
                                         (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU))))))) {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 1U;
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d = 0U;
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
                            = ((vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
                                << 3U) | (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
                                          >> 0x0000001dU));
                    }
                }
            }
        }
    } else if ((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
        if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 0U;
        } else if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q) {
            if (tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0) {
                vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
                if ((3U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q))) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 2U;
                }
            }
        } else if ((((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q)) 
                     & (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) 
                    & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__bitstream_cache_mem_if.req_ready))) {
            vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 1U;
        }
        if ((1U & (~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal)))) {
            if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q) {
                if (tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d 
                        = (7U & ((IData)(1U) + (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q)));
                    if ((3U != (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q))) {
                        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d 
                            = ((IData)(0x00000040U) 
                               + vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q);
                    }
                }
            }
        }
    } else {
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = 0U;
    }
    __Vtableidx1 = ((((((IData)(vlSymsp->TOP__tb_fdr_top__DOT__schedule_if.valid) 
                        << 3U) | (((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)) 
                                   & (IData)(vlSymsp->TOP__tb_fdr_top__DOT__metacache_mem_if.req_ready)) 
                                  << 2U)) | (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire) 
                                              << 1U) 
                                             | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal))) 
                     << 3U) | (((IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal) 
                                << 2U) | (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q)));
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal 
        = VVX_define__ConstPool__TABLE_hab3087f5_0[__Vtableidx1];
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_d 
        = VVX_define__ConstPool__TABLE_h0e3ac2b6_0[__Vtableidx1];
}

void VVX_define_fdr_if___nba_comb__TOP__tb_fdr_top__DOT__fdr_if__0(VVX_define_fdr_if* vlSelf);

void VVX_define___024root___eval_nba(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_nba\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((4ULL & vlSelfRef.__VnbaTriggered[0U])) {
        VVX_define___024root___nba_sequent__TOP__0(vlSelf);
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
        VVX_define___024root___nba_sequent__TOP__1(vlSelf);
    }
    if ((2ULL & vlSelfRef.__VnbaTriggered[0U])) {
        VVX_define___024root___nba_sequent__TOP__2(vlSelf);
    }
    if ((0x000000000000000cULL & vlSelfRef.__VnbaTriggered
         [0U])) {
        VVX_define___024root___nba_sequent__TOP__3(vlSelf);
    }
    if ((0x00000000000001e4ULL & vlSelfRef.__VnbaTriggered
         [0U])) {
        VVX_define___024root___nba_comb__TOP__0(vlSelf);
        VVX_define_fdr_if___nba_comb__TOP__tb_fdr_top__DOT__fdr_if__0((&vlSymsp->TOP__tb_fdr_top__DOT__fdr_if));
    }
}

void VVX_define___024root___timing_commit(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___timing_commit\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((! (4ULL & vlSelfRef.__VactTriggered[0U]))) {
        vlSelfRef.__VtrigSched_h416eaf98__0.commit(
                                                   "@(posedge tb_fdr_top.clk)");
    }
    if ((! (0x0000000000000020ULL & vlSelfRef.__VactTriggered
            [0U]))) {
        vlSelfRef.__VtrigSched_hda9fe986__0.commit(
                                                   "@( tb_fdr_top.u_dut.schedule_ready_internal)");
    }
    if ((! (0x0000000000000040ULL & vlSelfRef.__VactTriggered
            [0U]))) {
        vlSelfRef.__VtrigSched_h40580101__0.commit(
                                                   "@( (2'h1 == tb_fdr_top.u_dut.u_meta_fetch.state_q))");
    }
    if ((! (0x0000000000000080ULL & vlSelfRef.__VactTriggered
            [0U]))) {
        vlSelfRef.__VtrigSched_h969ff5c5__0.commit(
                                                   "@( ((~ tb_fdr_top.u_dut.u_bitstream_fetch_load.req_sent_q) & (2'h1 == tb_fdr_top.u_dut.u_bitstream_fetch_load.state_q)))");
    }
    if ((! (0x0000000000000100ULL & vlSelfRef.__VactTriggered
            [0U]))) {
        vlSelfRef.__VtrigSched_hd8d198eb__0.commit(
                                                   "@( tb_fdr_top.fdr_if.valid)");
    }
}

void VVX_define___024root___timing_resume(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___timing_resume\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((4ULL & vlSelfRef.__VactTriggered[0U])) {
        vlSelfRef.__VtrigSched_h416eaf98__0.resume(
                                                   "@(posedge tb_fdr_top.clk)");
    }
    if ((0x0000000000000020ULL & vlSelfRef.__VactTriggered
         [0U])) {
        vlSelfRef.__VtrigSched_hda9fe986__0.resume(
                                                   "@( tb_fdr_top.u_dut.schedule_ready_internal)");
    }
    if ((0x0000000000000040ULL & vlSelfRef.__VactTriggered
         [0U])) {
        vlSelfRef.__VtrigSched_h40580101__0.resume(
                                                   "@( (2'h1 == tb_fdr_top.u_dut.u_meta_fetch.state_q))");
    }
    if ((0x0000000000000080ULL & vlSelfRef.__VactTriggered
         [0U])) {
        vlSelfRef.__VtrigSched_h969ff5c5__0.resume(
                                                   "@( ((~ tb_fdr_top.u_dut.u_bitstream_fetch_load.req_sent_q) & (2'h1 == tb_fdr_top.u_dut.u_bitstream_fetch_load.state_q)))");
    }
    if ((0x0000000000000100ULL & vlSelfRef.__VactTriggered
         [0U])) {
        vlSelfRef.__VtrigSched_hd8d198eb__0.resume(
                                                   "@( tb_fdr_top.fdr_if.valid)");
    }
    if ((0x0000000000000010ULL & vlSelfRef.__VactTriggered
         [0U])) {
        vlSelfRef.__VdlySched.resume();
    }
}

void VVX_define___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool VVX_define___024root___eval_phase__act(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_phase__act\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VactExecute;
    // Body
    VVX_define___024root___eval_triggers__act(vlSelf);
    VVX_define___024root___timing_commit(vlSelf);
    VVX_define___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    __VactExecute = VVX_define___024root___trigger_anySet__act(vlSelfRef.__VactTriggered);
    if (__VactExecute) {
        VVX_define___024root___timing_resume(vlSelf);
        VVX_define___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

void VVX_define___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool VVX_define___024root___eval_phase__nba(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_phase__nba\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = VVX_define___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        VVX_define___024root___eval_nba(vlSelf);
        VVX_define___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void VVX_define___024root___eval(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VnbaIterCount;
    // Body
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[0U] 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[0U];
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[1U] 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[1U];
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[2U] 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[2U];
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U] 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[3U];
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U] 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q[4U];
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal;
    vlSelfRef.__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q 
        = vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q;
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            VVX_define___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("/Users/elliotn/Code/vortex4dice/dice_new/rtl/dice_ram/dice_ram_1w1r.sv", 2, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                VVX_define___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("/Users/elliotn/Code/vortex4dice/dice_new/rtl/dice_ram/dice_ram_1w1r.sv", 2, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (VVX_define___024root___eval_phase__act(vlSelf));
    } while (VVX_define___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void VVX_define___024root___eval_debug_assertions(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_debug_assertions\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.dice_ram_1w1r__02Eclk 
                      & 0xfeU)))) {
        Verilated::overWidthError("dice_ram_1w1r.clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.wr_en & 0xfeU)))) {
        Verilated::overWidthError("wr_en");
    }
    if (VL_UNLIKELY(((vlSelfRef.wr_addr & 0xfc00U)))) {
        Verilated::overWidthError("wr_addr");
    }
    if (VL_UNLIKELY(((vlSelfRef.rd_en & 0xfeU)))) {
        Verilated::overWidthError("rd_en");
    }
    if (VL_UNLIKELY(((vlSelfRef.rd_addr & 0xfc00U)))) {
        Verilated::overWidthError("rd_addr");
    }
    if (VL_UNLIKELY(((vlSelfRef.dice_ram_1rw__02Eclk 
                      & 0xfeU)))) {
        Verilated::overWidthError("dice_ram_1rw.clk");
    }
    if (VL_UNLIKELY(((vlSelfRef.en & 0xfeU)))) {
        Verilated::overWidthError("en");
    }
    if (VL_UNLIKELY(((vlSelfRef.we & 0xfeU)))) {
        Verilated::overWidthError("we");
    }
    if (VL_UNLIKELY(((vlSelfRef.addr & 0xfc00U)))) {
        Verilated::overWidthError("addr");
    }
}
#endif  // VL_DEBUG
