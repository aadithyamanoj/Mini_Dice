// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Primary model header
//
// This header should be included by all source files instantiating the design.
// The class here is then constructed to instantiate the design.
// See the Verilator manual for examples.

#ifndef VERILATED_VVX_DEFINE_H_
#define VERILATED_VVX_DEFINE_H_  // guard

#include "verilated.h"

class VVX_define__Syms;
class VVX_define___024root;
class VVX_define_VX_mem_bus_if__D40_T30;
class VVX_define_cta_sched_if;
class VVX_define_fdr_if;
class VVX_define_simt_stack_status_if;


// This class is the main interface to the Verilated model
class alignas(VL_CACHE_LINE_BYTES) VVX_define VL_NOT_FINAL : public VerilatedModel {
  private:
    // Symbol table holding complete model state (owned by this class)
    VVX_define__Syms* const vlSymsp;

  public:

    // CONSTEXPR CAPABILITIES
    // Verilated with --trace?
    static constexpr bool traceCapable = false;

    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(&dice_ram_1w1r__02Eclk,0,0);
    VL_IN8(&dice_ram_1rw__02Eclk,0,0);
    VL_IN8(&wr_en,0,0);
    VL_IN8(&rd_en,0,0);
    VL_IN8(&en,0,0);
    VL_IN8(&we,0,0);
    VL_IN16(&wr_addr,9,0);
    VL_IN16(&rd_addr,9,0);
    VL_IN16(&addr,9,0);
    VL_IN(&wr_data,31,0);
    VL_OUT(&rd_data,31,0);
    VL_IN(&wdata,31,0);
    VL_OUT(&rdata,31,0);

    // CELLS
    // Public to allow access to /* verilator public */ items.
    // Otherwise the application code can consider these internals.
    VVX_define_VX_mem_bus_if__D40_T30* const __PVT__tb_fdr_top__DOT__metacache_mem_if;
    VVX_define_VX_mem_bus_if__D40_T30* const __PVT__tb_fdr_top__DOT__bitstream_cache_mem_if;
    VVX_define_cta_sched_if* const __PVT__tb_fdr_top__DOT__schedule_if;
    VVX_define_fdr_if* const __PVT__tb_fdr_top__DOT__fdr_if;
    VVX_define_simt_stack_status_if* const __PVT__tb_fdr_top__DOT__simt_status_if;

    // Root instance pointer to allow access to model internals,
    // including inlined /* verilator public_flat_* */ items.
    VVX_define___024root* const rootp;

    // CONSTRUCTORS
    /// Construct the model; called by application code
    /// If contextp is null, then the model will use the default global context
    /// If name is "", then makes a wrapper with a
    /// single model invisible with respect to DPI scope names.
    explicit VVX_define(VerilatedContext* contextp, const char* name = "TOP");
    explicit VVX_define(const char* name = "TOP");
    /// Destroy the model; called (often implicitly) by application code
    virtual ~VVX_define();
  private:
    VL_UNCOPYABLE(VVX_define);  ///< Copying not allowed

  public:
    // API METHODS
    /// Evaluate the model.  Application must call when inputs change.
    void eval() { eval_step(); }
    /// Evaluate when calling multiple units/models per time step.
    void eval_step();
    /// Evaluate at end of a timestep for tracing, when using eval_step().
    /// Application must call after all eval() and before time changes.
    void eval_end_step() {}
    /// Simulation complete, run final blocks.  Application must call on completion.
    void final();
    /// Are there scheduled events to handle?
    bool eventsPending();
    /// Returns time at next time slot. Aborts if !eventsPending()
    uint64_t nextTimeSlot();
    /// Trace signals in the model; called by application code
    void trace(VerilatedTraceBaseC* tfp, int levels, int options = 0) { contextp()->trace(tfp, levels, options); }
    /// Retrieve name of this model instance (as passed to constructor).
    const char* name() const;

    // Abstract methods from VerilatedModel
    const char* hierName() const override final;
    const char* modelName() const override final;
    unsigned threads() const override final;
    /// Prepare for cloning the model at the process level (e.g. fork in Linux)
    /// Release necessary resources. Called before cloning.
    void prepareClone() const;
    /// Re-init after cloning the model at the process level (e.g. fork in Linux)
    /// Re-allocate necessary resources. Called after cloning.
    void atClone() const;
  private:
    // Internal functions - trace registration
    void traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options);
};

#endif  // guard
