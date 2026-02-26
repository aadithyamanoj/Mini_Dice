// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_fdr_top.h for the primary calling header

#ifndef VERILATED_VTB_FDR_TOP_VX_MEM_BUS_IF__D40_T30_H_
#define VERILATED_VTB_FDR_TOP_VX_MEM_BUS_IF__D40_T30_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_fdr_top__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_fdr_top_VX_mem_bus_if__D40_T30 final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ req_ready;
    CData/*0:0*/ rsp_valid;
    VlWide<18>/*559:0*/ rsp_data;

    // INTERNAL VARIABLES
    Vtb_fdr_top__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_fdr_top_VX_mem_bus_if__D40_T30(Vtb_fdr_top__Syms* symsp, const char* v__name);
    ~Vtb_fdr_top_VX_mem_bus_if__D40_T30();
    VL_UNCOPYABLE(Vtb_fdr_top_VX_mem_bus_if__D40_T30);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const Vtb_fdr_top_VX_mem_bus_if__D40_T30* obj);

#endif  // guard
