// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VVX_DEFINE__SYMS_H_
#define VERILATED_VVX_DEFINE__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "VVX_define.h"

// INCLUDE MODULE CLASSES
#include "VVX_define___024root.h"
#include "VVX_define_cta_sched_if.h"
#include "VVX_define_simt_stack_status_if.h"
#include "VVX_define_fdr_if.h"
#include "VVX_define_VX_mem_bus_if__D40_T30.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) VVX_define__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    VVX_define* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    VVX_define___024root           TOP;
    VVX_define_VX_mem_bus_if__D40_T30 TOP__tb_fdr_top__DOT__bitstream_cache_mem_if;
    VVX_define_fdr_if              TOP__tb_fdr_top__DOT__fdr_if;
    VVX_define_VX_mem_bus_if__D40_T30 TOP__tb_fdr_top__DOT__metacache_mem_if;
    VVX_define_cta_sched_if        TOP__tb_fdr_top__DOT__schedule_if;
    VVX_define_simt_stack_status_if TOP__tb_fdr_top__DOT__simt_status_if;

    // CONSTRUCTORS
    VVX_define__Syms(VerilatedContext* contextp, const char* namep, VVX_define* modelp);
    ~VVX_define__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
