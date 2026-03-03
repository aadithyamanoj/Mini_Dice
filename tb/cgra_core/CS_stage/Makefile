.PHONY: lint clean

SHELL := /bin/bash

DICE_HOME  ?= $(shell cd ../../.. && pwd)
TOP_MODULE ?= cta_schedule_stage

# Verilator lint configuration
VERILATOR_FLAGS  = --lint-only                # Run static lint only (no C++ sim generation)
VERILATOR_FLAGS += -Wall                      # Enable all standard warnings
VERILATOR_FLAGS += -Wno-UNDRIVEN              # Allow declared signals that are never driven
VERILATOR_FLAGS += -Wno-UNUSEDSIGNAL          # Allow driven signals that are never read
VERILATOR_FLAGS += -Wno-UNUSEDPARAM           # Allow unused parameters in parameterized modules
VERILATOR_FLAGS += -Wno-WIDTHEXPAND           # Suppress implicit width expansion warnings (zero/sign extend)
VERILATOR_FLAGS += -Wno-WIDTHTRUNC            # Suppress implicit truncation warnings (upper bits dropped)
VERILATOR_FLAGS += -Wno-ASCRANGE              # Allow ascending bit ranges (e.g., [0:31])
VERILATOR_FLAGS += --top-module $(TOP_MODULE) # Explicitly set design root module

lint:
	@echo "Running Verilator lint on $(TOP_MODULE)..."
	@DICE_HOME=$(DICE_HOME) verilator $(VERILATOR_FLAGS) -f filelist.f
	@echo "Lint passed."

clean:
	@echo "Cleaning Verilator artifacts..."
	@rm -rf obj_dir
	@echo "Done."
