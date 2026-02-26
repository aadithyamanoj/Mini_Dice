// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VVX_define.h for the primary calling header

#ifndef VERILATED_VVX_DEFINE_SIMT_STACK_STATUS_IF_H_
#define VERILATED_VVX_DEFINE_SIMT_STACK_STATUS_IF_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class VVX_define__Syms;

class alignas(VL_CACHE_LINE_BYTES) VVX_define_simt_stack_status_if final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    VlWide<73>/*2315:0*/ status;

    // INTERNAL VARIABLES
    VVX_define__Syms* const vlSymsp;

    // CONSTRUCTORS
    VVX_define_simt_stack_status_if(VVX_define__Syms* symsp, const char* v__name);
    ~VVX_define_simt_stack_status_if();
    VL_UNCOPYABLE(VVX_define_simt_stack_status_if);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const VVX_define_simt_stack_status_if* obj);

#endif  // guard
