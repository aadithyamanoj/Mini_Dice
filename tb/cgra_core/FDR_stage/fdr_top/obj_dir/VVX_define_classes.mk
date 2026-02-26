# Verilated -*- Makefile -*-
# DESCRIPTION: Verilator output: Make include file with class lists
#
# This file lists generated Verilated files, for including in higher level makefiles.
# See VVX_define.mk for the caller.

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
  VVX_define \
  VVX_define___024root__0 \
  VVX_define_cta_sched_if__0 \
  VVX_define_simt_stack_status_if__0 \
  VVX_define_fdr_if__0 \
  VVX_define_VX_mem_bus_if__D40_T30__0 \
  VVX_define__main \

# Generated module classes, non-fast-path, compile with low/medium optimization
VM_CLASSES_SLOW += \
  VVX_define__ConstPool_0 \
  VVX_define___024root__Slow \
  VVX_define___024root__0__Slow \
  VVX_define_cta_sched_if__Slow \
  VVX_define_cta_sched_if__0__Slow \
  VVX_define_simt_stack_status_if__Slow \
  VVX_define_simt_stack_status_if__0__Slow \
  VVX_define_fdr_if__Slow \
  VVX_define_fdr_if__0__Slow \
  VVX_define_VX_mem_bus_if__D40_T30__Slow \
  VVX_define_VX_mem_bus_if__D40_T30__0__Slow \

# Generated support classes, fast-path, compile with highest optimization
VM_SUPPORT_FAST += \

# Generated support classes, non-fast-path, compile with low/medium optimization
VM_SUPPORT_SLOW += \
  VVX_define__Syms \

# Global classes, need linked once per executable, fast-path, compile with highest optimization
VM_GLOBAL_FAST += \
  verilated \
  verilated_timing \
  verilated_threads \

# Global classes, need linked once per executable, non-fast-path, compile with low/medium optimization
VM_GLOBAL_SLOW += \

# Verilated -*- Makefile -*-
