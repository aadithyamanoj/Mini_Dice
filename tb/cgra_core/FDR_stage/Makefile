.PHONY: lint clean

SHELL := /bin/bash

DICE_HOME  ?= $(shell cd ../../.. && pwd)
TOP_MODULE ?= fdr_top

VERILATOR_FLAGS = --lint-only \
                  -Wall \
                  -Wno-UNDRIVEN \
                  -Wno-UNUSEDSIGNAL \
                  -Wno-UNUSEDPARAM \
                  --top-module $(TOP_MODULE)

lint:
	@echo "Running Verilator lint on $(TOP_MODULE)..."
	@DICE_HOME=$(DICE_HOME) verilator $(VERILATOR_FLAGS) -f filelist.f
	@echo "Lint passed."

clean:
	@echo "Cleaning Verilator artifacts..."
	@rm -rf obj_dir
	@echo "Done."
