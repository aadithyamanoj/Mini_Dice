// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VVX_define.h for the primary calling header

#include "VVX_define__pch.h"

void VVX_define_cta_sched_if___ctor_var_reset(VVX_define_cta_sched_if* vlSelf);

VVX_define_cta_sched_if::VVX_define_cta_sched_if(VVX_define__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , vlSymsp{symsp}
 {
    // Reset structure values
    VVX_define_cta_sched_if___ctor_var_reset(this);
}

void VVX_define_cta_sched_if::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

VVX_define_cta_sched_if::~VVX_define_cta_sched_if() {
}
