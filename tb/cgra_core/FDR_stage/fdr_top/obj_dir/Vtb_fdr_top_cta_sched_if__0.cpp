// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_fdr_top.h for the primary calling header

#include "Vtb_fdr_top__pch.h"

std::string VL_TO_STRING(const Vtb_fdr_top_cta_sched_if* obj) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          Vtb_fdr_top_cta_sched_if::VL_TO_STRING\n"); );
    // Body
    return (obj ? obj->name() : "null");
}
