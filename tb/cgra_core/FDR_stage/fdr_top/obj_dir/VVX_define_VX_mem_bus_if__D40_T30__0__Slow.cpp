// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

VL_ATTR_COLD void VVX_define_VX_mem_bus_if__D40_T30___ctor_var_reset(VVX_define_VX_mem_bus_if__D40_T30* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+            VVX_define_VX_mem_bus_if__D40_T30___ctor_var_reset\n"); );
    VVX_define__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    vlSelf->req_ready = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 16539944981316001420ull);
    vlSelf->rsp_valid = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1421612161635894276ull);
    VL_SCOPED_RAND_RESET_W(560, vlSelf->rsp_data, __VscopeHash, 3559817494807160352ull);
}
