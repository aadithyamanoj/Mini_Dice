// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

VL_ATTR_COLD void VVX_define___024root___eval_static(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_static\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
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
    vlSelfRef.__Vtrigprevexpr_he86f48af__1 = (1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q));
    vlSelfRef.__Vtrigprevexpr_h0e98381b__1 = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q)) 
                                              & (1U 
                                                 == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q)));
    vlSelfRef.__Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0 
        = vlSymsp->TOP__tb_fdr_top__DOT__fdr_if.valid;
}

VL_ATTR_COLD void VVX_define___024root___eval_initial__TOP(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_initial__TOP\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ dice_ram_1rw__DOT__unnamedblk1__DOT__i;
    dice_ram_1rw__DOT__unnamedblk1__DOT__i = 0;
    // Body
    dice_ram_1rw__DOT__unnamedblk1__DOT__i = 0U;
    while (VL_GTS_III(32, 0x00000400U, dice_ram_1rw__DOT__unnamedblk1__DOT__i)) {
        vlSelfRef.dice_ram_1rw__DOT__ram_array[(0x000003ffU 
                                                & dice_ram_1rw__DOT__unnamedblk1__DOT__i)] = 0U;
        dice_ram_1rw__DOT__unnamedblk1__DOT__i = ((IData)(1U) 
                                                  + dice_ram_1rw__DOT__unnamedblk1__DOT__i);
    }
}

VL_ATTR_COLD void VVX_define___024root___eval_final(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_final\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void VVX_define___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool VVX_define___024root___eval_phase__stl(VVX_define___024root* vlSelf);

VL_ATTR_COLD void VVX_define___024root___eval_settle(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_settle\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            VVX_define___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("/Users/elliotn/Code/vortex4dice/dice_new/rtl/dice_ram/dice_ram_1w1r.sv", 2, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (VVX_define___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void VVX_define___024root___eval_triggers__stl(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_triggers__stl\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        VVX_define___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool VVX_define___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void VVX_define___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(VVX_define___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool VVX_define___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD void VVX_define___024root___stl_sequent__TOP__0(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___stl_sequent__TOP__0\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0;
    tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT____VdfgExtracted_hbf0755a6__0 = 0;
    CData/*6:0*/ __Vtableidx1;
    __Vtableidx1 = 0;
    // Body
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
    vlSelfRef.rd_data = vlSelfRef.dice_ram_1w1r__DOT__rd_data_reg;
    vlSelfRef.rdata = vlSelfRef.dice_ram_1rw__DOT__rdata_reg;
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
    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal 
        = ((~ (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q)) 
           & (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q));
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
        vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = 0U;
    } else {
        if ((1U != (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
            if ((2U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
                if (vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q) {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d = 1U;
                } else {
                    vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d = 1U;
                }
            }
        }
        if ((1U == (IData)(vlSelfRef.tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q))) {
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
}

void VVX_define_fdr_if___nba_comb__TOP__tb_fdr_top__DOT__fdr_if__0(VVX_define_fdr_if* vlSelf);

VL_ATTR_COLD void VVX_define___024root___eval_stl(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_stl\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        VVX_define___024root___stl_sequent__TOP__0(vlSelf);
        VVX_define_fdr_if___nba_comb__TOP__tb_fdr_top__DOT__fdr_if__0((&vlSymsp->TOP__tb_fdr_top__DOT__fdr_if));
    }
}

VL_ATTR_COLD bool VVX_define___024root___eval_phase__stl(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___eval_phase__stl\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    VVX_define___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = VVX_define___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        VVX_define___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool VVX_define___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void VVX_define___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(VVX_define___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge dice_ram_1w1r.clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @(posedge dice_ram_1rw.clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 2U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 2 is active: @(posedge tb_fdr_top.clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 3U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 3 is active: @(posedge tb_fdr_top.rst)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 4U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 4 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
    if ((1U & (IData)((triggers[0U] >> 5U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 5 is active: @( tb_fdr_top.u_dut.schedule_ready_internal)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 6U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 6 is active: @( (2'h1 == tb_fdr_top.u_dut.u_meta_fetch.state_q))\n");
    }
    if ((1U & (IData)((triggers[0U] >> 7U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 7 is active: @( ((~ tb_fdr_top.u_dut.u_bitstream_fetch_load.req_sent_q) & (2'h1 == tb_fdr_top.u_dut.u_bitstream_fetch_load.state_q)))\n");
    }
    if ((1U & (IData)((triggers[0U] >> 8U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 8 is active: @( tb_fdr_top.fdr_if.valid)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void VVX_define___024root___ctor_var_reset(VVX_define___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VVX_define___024root___ctor_var_reset\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    vlSelf->dice_ram_1w1r__02Eclk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 329068416978429427ull);
    vlSelf->wr_en = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7710928637576349896ull);
    vlSelf->wr_addr = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 10458723662394441575ull);
    vlSelf->wr_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12812822527505751231ull);
    vlSelf->rd_en = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3814484142505630662ull);
    vlSelf->rd_addr = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 7950012703377089919ull);
    vlSelf->rd_data = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 17824471296722538975ull);
    vlSelf->dice_ram_1rw__02Eclk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7841024367486650138ull);
    vlSelf->en = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7710216835639188562ull);
    vlSelf->we = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10105644630884274164ull);
    vlSelf->addr = VL_SCOPED_RAND_RESET_I(10, __VscopeHash, 14934084843038794831ull);
    vlSelf->wdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12890271867161903902ull);
    vlSelf->rdata = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 10065165116613087284ull);
    for (int __Vi0 = 0; __Vi0 < 1024; ++__Vi0) {
        vlSelf->dice_ram_1w1r__DOT__ram_array[__Vi0] = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16576323376764965833ull);
    }
    vlSelf->dice_ram_1w1r__DOT__rd_data_reg = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 8431546040512513707ull);
    for (int __Vi0 = 0; __Vi0 < 1024; ++__Vi0) {
        vlSelf->dice_ram_1rw__DOT__ram_array[__Vi0] = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16509150614219935539ull);
    }
    vlSelf->dice_ram_1rw__DOT__rdata_reg = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 16127862338097756060ull);
    vlSelf->tb_fdr_top__DOT__clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 7136130349770244067ull);
    vlSelf->tb_fdr_top__DOT__rst = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 921936286839347694ull);
    vlSelf->tb_fdr_top__DOT__cycle_count = 0;
    VL_SCOPED_RAND_RESET_W(140, vlSelf->tb_fdr_top__DOT__cta_status_data_i, __VscopeHash, 9006310314967709380ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 12955908057352711062ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__fire_eblock_internal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 8740520424315037483ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13899240702669886630ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__predict_miss_internal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 4057314477400865081ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2649328021112361292ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_q = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 11014472200244412617ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__state_d = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 3469984613455759575ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_valid_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2889329357858638248ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__flushed_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 8066508293290297656ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__fdr_next_pc_q = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 327987341328967596ull);
    VL_SCOPED_RAND_RESET_W(157, vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q, __VscopeHash, 14111095929444615769ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__meta_cache_req_addr_q = VL_SCOPED_RAND_RESET_I(30, __VscopeHash, 3898182759475021662ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__rsp_fire = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 123059509000875317ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__done_streaming_o = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17631580739720557802ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_q = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 1023359655929096741ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__state_d = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 11074528739622483773ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_q = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 14876143623234489421ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_q = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2563119784120812565ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_addr_d = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 15352225838272166478ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_addr_d = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2369010918914618595ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15288385447100141467ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm_select_d = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5666833193001072971ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_q = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 9597905237432599185ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__chunk_count_d = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 10785673965503251186ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_q = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 7651603637417816525ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__addr_d = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 6381082270158462408ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_d = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15882123417308848273ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_d = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15538126633831478764ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm0_valid_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3024234509465360862ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__cm1_valid_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14769465985874867366ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1351482853972368329ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_bitstream_fetch_load__DOT__req_sent_d = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10658117485596912438ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16987801954679001394ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT__pc_match_required = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10398313084390517660ull);
    vlSelf->tb_fdr_top__DOT__u_dut__DOT__u_valid_check__DOT____VdfgRegularize_hf22c5ed9_0_0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 15011827331263883028ull);
    vlSelf->__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_branch_handler__DOT__u_branch_meta_valid_rise__DOT__sig_prev_q = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13780281984450847402ull);
    vlSelf->__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__meta_valid_internal = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 12817969138889296079ull);
    VL_SCOPED_RAND_RESET_W(157, vlSelf->__Vsampled_TOP__tb_fdr_top__DOT__u_dut__DOT__u_meta_fetch__DOT__outgoing_meta_q, __VscopeHash, 5771635270223513951ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__dice_ram_1w1r__02Eclk__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 18423190424815658251ull);
    vlSelf->__Vtrigprevexpr___TOP__dice_ram_1rw__02Eclk__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14292730404222336253ull);
    vlSelf->__Vtrigprevexpr___TOP__tb_fdr_top__DOT__clk__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5518724708756826378ull);
    vlSelf->__Vtrigprevexpr___TOP__tb_fdr_top__DOT__rst__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 10749377769250704293ull);
    vlSelf->__Vtrigprevexpr___TOP__tb_fdr_top__DOT__u_dut__DOT__schedule_ready_internal__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6735697444426230805ull);
    vlSelf->__Vtrigprevexpr_he86f48af__1 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 12376986547902119628ull);
    vlSelf->__Vtrigprevexpr_h0e98381b__1 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16268465094906818371ull);
    vlSelf->__Vtrigprevexpr___TOP__tb_fdr_top__DOT__fdr_if__valid__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16186672261551166104ull);
    vlSelf->__VactDidInit = 0;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
}
