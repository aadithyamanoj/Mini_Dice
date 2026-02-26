// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

void VVX_define___024root___ctor_var_reset(VVX_define___024root* vlSelf);

VVX_define___024root::VVX_define___024root(VVX_define__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    VVX_define___024root___ctor_var_reset(this);
}

void VVX_define___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

VVX_define___024root::~VVX_define___024root() {
}
