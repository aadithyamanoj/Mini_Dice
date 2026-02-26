// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_fdr_top.h for the primary calling header

#include "Vtb_fdr_top__pch.h"

VL_ATTR_COLD void Vtb_fdr_top_simt_stack_status_if___ctor_var_reset(Vtb_fdr_top_simt_stack_status_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtb_fdr_top_simt_stack_status_if___ctor_var_reset\n"); );
    Vtb_fdr_top__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    VL_SCOPED_RAND_RESET_W(2316, vlSelf->status, __VscopeHash, 14822974759303984767ull);
}
