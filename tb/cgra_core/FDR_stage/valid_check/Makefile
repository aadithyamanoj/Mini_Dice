.PHONY: sim lint clean

SHELL := /bin/bash

TB         ?= tb_valid_check
DICE_HOME  ?= $(shell cd ../../../.. && pwd)
TOP_MODULE ?= valid_check

# Verilator lint configuration
VERILATOR_FLAGS  = --lint-only                # Run static lint only (no C++ sim generation)
VERILATOR_FLAGS += -Wall                      # Enable all standard warnings
VERILATOR_FLAGS += -Wno-UNDRIVEN              # Allow declared signals that are never driven
VERILATOR_FLAGS += -Wno-UNUSEDSIGNAL          # Allow driven signals that are never read
VERILATOR_FLAGS += -Wno-UNUSEDPARAM           # Allow unused parameters in parameterized modules
VERILATOR_FLAGS += -Wno-WIDTHEXPAND           # Suppress implicit width expansion warnings
VERILATOR_FLAGS += -Wno-WIDTHTRUNC            # Suppress implicit truncation warnings
VERILATOR_FLAGS += -Wno-ASCRANGE              # Allow ascending bit ranges (e.g., [0:31])
VERILATOR_FLAGS += -Wno-DECLFILENAME          # Allow package/file naming mismatches in shared RTL
VERILATOR_FLAGS += --top-module $(TOP_MODULE) # Explicitly set design root module

sim:
	@echo "Running VCS sim with TOP=$(TB)"
	@TB_TOP=$(TB) tclsh run_vcs.tcl

lint:
	@echo "Running Verilator lint on $(TOP_MODULE)..."
	@DICE_HOME=$(DICE_HOME) verilator $(VERILATOR_FLAGS) -f filelist_lint.f
	@echo "Lint passed."

clean:
	@echo "Cleaning VCS, Verdi, and Verilator artifacts (but keeping novas.conf / novas.rc)..."
	@rm -rf simv \
	        simv.daidir \
	        csrc \
	        obj_dir \
	        DVEfiles \
	        AN.DB \
	        ucli.key \
	        verdiLog \
	        *.fsdb \
	        *.fsdb.* \
	        *.vpd \
	        *.log \
	        *.key
	@echo "Done."
