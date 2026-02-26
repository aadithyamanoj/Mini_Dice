// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VVX_define.h for the primary calling header

#ifndef VERILATED_VVX_DEFINE_VX_MEM_BUS_IF__D40_T30_H_
#define VERILATED_VVX_DEFINE_VX_MEM_BUS_IF__D40_T30_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class VVX_define__Syms;

class alignas(VL_CACHE_LINE_BYTES) VVX_define_VX_mem_bus_if__D40_T30 final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ req_ready;
    CData/*0:0*/ rsp_valid;
    VlWide<18>/*559:0*/ rsp_data;

    // INTERNAL VARIABLES
    VVX_define__Syms* const vlSymsp;

    // CONSTRUCTORS
    VVX_define_VX_mem_bus_if__D40_T30(VVX_define__Syms* symsp, const char* v__name);
    ~VVX_define_VX_mem_bus_if__D40_T30();
    VL_UNCOPYABLE(VVX_define_VX_mem_bus_if__D40_T30);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};

std::string VL_TO_STRING(const VVX_define_VX_mem_bus_if__D40_T30* obj);

#endif  // guard
