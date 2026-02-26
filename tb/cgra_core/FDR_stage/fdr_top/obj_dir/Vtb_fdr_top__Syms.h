// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VTB_FDR_TOP__SYMS_H_
#define VERILATED_VTB_FDR_TOP__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vtb_fdr_top.h"

// INCLUDE MODULE CLASSES
#include "Vtb_fdr_top___024root.h"
#include "Vtb_fdr_top_cta_sched_if.h"
#include "Vtb_fdr_top_simt_stack_status_if.h"
#include "Vtb_fdr_top_fdr_if.h"
#include "Vtb_fdr_top_VX_mem_bus_if__D40_T30.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) Vtb_fdr_top__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vtb_fdr_top* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vtb_fdr_top___024root          TOP;
    Vtb_fdr_top_VX_mem_bus_if__D40_T30 TOP__tb_fdr_top__DOT__bitstream_cache_mem_if;
    Vtb_fdr_top_fdr_if             TOP__tb_fdr_top__DOT__fdr_if;
    Vtb_fdr_top_VX_mem_bus_if__D40_T30 TOP__tb_fdr_top__DOT__metacache_mem_if;
    Vtb_fdr_top_cta_sched_if       TOP__tb_fdr_top__DOT__schedule_if;
    Vtb_fdr_top_simt_stack_status_if TOP__tb_fdr_top__DOT__simt_status_if;

    // CONSTRUCTORS
    Vtb_fdr_top__Syms(VerilatedContext* contextp, const char* namep, Vtb_fdr_top* modelp);
    ~Vtb_fdr_top__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
