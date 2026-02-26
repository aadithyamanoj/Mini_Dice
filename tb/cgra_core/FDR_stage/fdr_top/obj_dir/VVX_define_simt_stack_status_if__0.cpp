// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

std::string VL_TO_STRING(const VVX_define_simt_stack_status_if* obj) {
    VL_DEBUG_IF(VL_DBG_MSGF("+          VVX_define_simt_stack_status_if::VL_TO_STRING\n"); );
    // Body
    return (obj ? obj->name() : "null");
}
