// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "VVX_define__pch.h"

//============================================================
// Constructors

VVX_define::VVX_define(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new VVX_define__Syms(contextp(), _vcname__, this)}
    , dice_ram_1w1r__02Eclk{vlSymsp->TOP.dice_ram_1w1r__02Eclk}
    , dice_ram_1rw__02Eclk{vlSymsp->TOP.dice_ram_1rw__02Eclk}
    , wr_en{vlSymsp->TOP.wr_en}
    , rd_en{vlSymsp->TOP.rd_en}
    , en{vlSymsp->TOP.en}
    , we{vlSymsp->TOP.we}
    , wr_addr{vlSymsp->TOP.wr_addr}
    , rd_addr{vlSymsp->TOP.rd_addr}
    , addr{vlSymsp->TOP.addr}
    , wr_data{vlSymsp->TOP.wr_data}
    , rd_data{vlSymsp->TOP.rd_data}
    , wdata{vlSymsp->TOP.wdata}
    , rdata{vlSymsp->TOP.rdata}
    , __PVT__tb_fdr_top__DOT__metacache_mem_if{vlSymsp->TOP.__PVT__tb_fdr_top__DOT__metacache_mem_if}
    , __PVT__tb_fdr_top__DOT__bitstream_cache_mem_if{vlSymsp->TOP.__PVT__tb_fdr_top__DOT__bitstream_cache_mem_if}
    , __PVT__tb_fdr_top__DOT__schedule_if{vlSymsp->TOP.__PVT__tb_fdr_top__DOT__schedule_if}
    , __PVT__tb_fdr_top__DOT__fdr_if{vlSymsp->TOP.__PVT__tb_fdr_top__DOT__fdr_if}
    , __PVT__tb_fdr_top__DOT__simt_status_if{vlSymsp->TOP.__PVT__tb_fdr_top__DOT__simt_status_if}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

VVX_define::VVX_define(const char* _vcname__)
    : VVX_define(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

VVX_define::~VVX_define() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void VVX_define___024root___eval_debug_assertions(VVX_define___024root* vlSelf);
#endif  // VL_DEBUG
void VVX_define___024root___eval_static(VVX_define___024root* vlSelf);
void VVX_define___024root___eval_initial(VVX_define___024root* vlSelf);
void VVX_define___024root___eval_settle(VVX_define___024root* vlSelf);
void VVX_define___024root___eval(VVX_define___024root* vlSelf);

void VVX_define::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate VVX_define::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    VVX_define___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        VVX_define___024root___eval_static(&(vlSymsp->TOP));
        VVX_define___024root___eval_initial(&(vlSymsp->TOP));
        VVX_define___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    VVX_define___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool VVX_define::eventsPending() { return !vlSymsp->TOP.__VdlySched.empty(); }

uint64_t VVX_define::nextTimeSlot() { return vlSymsp->TOP.__VdlySched.nextTimeSlot(); }

//============================================================
// Utilities

const char* VVX_define::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void VVX_define___024root___eval_final(VVX_define___024root* vlSelf);

VL_ATTR_COLD void VVX_define::final() {
    VVX_define___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* VVX_define::hierName() const { return vlSymsp->name(); }
const char* VVX_define::modelName() const { return "VVX_define"; }
unsigned VVX_define::threads() const { return 1; }
void VVX_define::prepareClone() const { contextp()->prepareClone(); }
void VVX_define::atClone() const {
    contextp()->threadPoolpOnClone();
}
