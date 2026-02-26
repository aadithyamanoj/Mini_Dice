# Verilated -*- Makefile -*-
# DESCRIPTION: Verilator output: Make include file with class lists
#
# This file lists generated Verilated files, for including in higher level makefiles.
# See Vtb_fdr_top.mk for the caller.

### Switches...
# C11 constructs required?  0/1 (always on now)
VM_C11 = 1
# Timing enabled?  0/1
VM_TIMING = 1
# Coverage output mode?  0/1 (from --coverage)
VM_COVERAGE = 0
# Parallel builds?  0/1 (from --output-split)
VM_PARALLEL_BUILDS = 0
# Tracing output mode?  0/1 (from --trace-fst/--trace-saif/--trace-vcd)
VM_TRACE = 0
# Tracing output mode in FST format?  0/1 (from --trace-fst)
VM_TRACE_FST = 0
# Tracing output mode in SAIF format?  0/1 (from --trace-saif)
VM_TRACE_SAIF = 0
# Tracing output mode in VCD format?  0/1 (from --trace-vcd)
VM_TRACE_VCD = 0

### Object file lists...
# Generated module classes, fast-path, compile with highest optimization
VM_CLASSES_FAST += \
  Vtb_fdr_top \
  Vtb_fdr_top___024root__0 \
  Vtb_fdr_top_cta_sched_if__0 \
  Vtb_fdr_top_simt_stack_status_if__0 \
  Vtb_fdr_top_fdr_if__0 \
  Vtb_fdr_top_VX_mem_bus_if__D40_T30__0 \
  Vtb_fdr_top__main \

# Generated module classes, non-fast-path, compile with low/medium optimization
VM_CLASSES_SLOW += \
  Vtb_fdr_top__ConstPool_0 \
  Vtb_fdr_top___024root__Slow \
  Vtb_fdr_top___024root__0__Slow \
  Vtb_fdr_top_cta_sched_if__Slow \
  Vtb_fdr_top_cta_sched_if__0__Slow \
  Vtb_fdr_top_simt_stack_status_if__Slow \
  Vtb_fdr_top_simt_stack_status_if__0__Slow \
  Vtb_fdr_top_fdr_if__Slow \
  Vtb_fdr_top_fdr_if__0__Slow \
  Vtb_fdr_top_VX_mem_bus_if__D40_T30__Slow \
  Vtb_fdr_top_VX_mem_bus_if__D40_T30__0__Slow \

# Generated support classes, fast-path, compile with highest optimization
VM_SUPPORT_FAST += \

# Generated support classes, non-fast-path, compile with low/medium optimization
VM_SUPPORT_SLOW += \
  Vtb_fdr_top__Syms \

# Global classes, need linked once per executable, fast-path, compile with highest optimization
VM_GLOBAL_FAST += \
  verilated \
  verilated_timing \
  verilated_threads \

# Global classes, need linked once per executable, non-fast-path, compile with low/medium optimization
VM_GLOBAL_SLOW += \

# Verilated -*- Makefile -*-
