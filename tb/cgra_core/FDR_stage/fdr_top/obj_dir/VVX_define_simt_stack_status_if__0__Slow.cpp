// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

VL_ATTR_COLD void VVX_define_simt_stack_status_if___ctor_var_reset(VVX_define_simt_stack_status_if* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          VVX_define_simt_stack_status_if___ctor_var_reset\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    VL_SCOPED_RAND_RESET_W(2316, vlSelf->status, __VscopeHash, 14822974759303984767ull);
}
