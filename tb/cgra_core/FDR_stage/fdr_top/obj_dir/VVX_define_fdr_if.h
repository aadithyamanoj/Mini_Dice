// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VVX_define.h for the primary calling header

#ifndef VERILATED_VVX_DEFINE_FDR_IF_H_
#define VERILATED_VVX_DEFINE_FDR_IF_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class VVX_define__Syms;

class alignas(VL_CACHE_LINE_BYTES) VVX_define_fdr_if final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ valid;
    CData/*0:0*/ ready;
    VlWide<25>/*789:0*/ data;

    // INTERNAL VARIABLES
    VVX_define__Syms* const vlSymsp;

    // CONSTRUCTORS
    VVX_define_fdr_if(VVX_define__Syms* symsp, const char* v__name);
    ~VVX_define_fdr_if();
    VL_UNCOPYABLE(VVX_define_fdr_if);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const VVX_define_fdr_if* obj);

#endif  // guard
