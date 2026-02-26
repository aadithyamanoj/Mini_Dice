// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_fdr_top.h for the primary calling header

#ifndef VERILATED_VTB_FDR_TOP_CTA_SCHED_IF_H_
#define VERILATED_VTB_FDR_TOP_CTA_SCHED_IF_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_fdr_top__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_fdr_top_cta_sched_if final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ valid;
    VlWide<23>/*720:0*/ data;

    // INTERNAL VARIABLES
    Vtb_fdr_top__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_fdr_top_cta_sched_if(Vtb_fdr_top__Syms* symsp, const char* v__name);
    ~Vtb_fdr_top_cta_sched_if();
    VL_UNCOPYABLE(Vtb_fdr_top_cta_sched_if);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const Vtb_fdr_top_cta_sched_if* obj);

#endif  // guard
