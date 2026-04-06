.PHONY: lint sim gen clean

SHELL := /bin/bash

TB          ?= tb_dice_core
LINT_TOP    ?= $(TB)
DICE_HOME   ?= $(shell cd ../../.. && pwd)
BSG_HOME    ?= $(abspath $(DICE_HOME)/../basejump_stl)
TEST_VECTOR ?= kernel_simple
BUILD_DIR   := build

VERILATOR_FLAGS  = --lint-only
VERILATOR_FLAGS += --timing
VERILATOR_FLAGS += -Wall
VERILATOR_FLAGS += -Wno-TIMESCALEMOD
VERILATOR_FLAGS += -Wno-CASEINCOMPLETE
VERILATOR_FLAGS += -Wno-SYNCASYNCNET
VERILATOR_FLAGS += -Wno-PINMISSING
VERILATOR_FLAGS += -Wno-UNDRIVEN
VERILATOR_FLAGS += -Wno-UNUSEDSIGNAL
VERILATOR_FLAGS += -Wno-UNUSEDPARAM
VERILATOR_FLAGS += -Wno-WIDTHEXPAND
VERILATOR_FLAGS += -Wno-WIDTHTRUNC
VERILATOR_FLAGS += -Wno-ASCRANGE
VERILATOR_FLAGS += -Wno-DECLFILENAME
VERILATOR_FLAGS += -Wno-EOFNEWLINE
VERILATOR_FLAGS += -Wno-PINCONNECTEMPTY
VERILATOR_FLAGS += -Wno-GENUNNAMED
VERILATOR_FLAGS += -Wno-WIDTHCONCAT
VERILATOR_FLAGS += -Wno-LATCH

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

lint:
	@echo "Running Verilator lint on $(LINT_TOP)..."
	@DICE_HOME=$(DICE_HOME) BSG_HOME=$(BSG_HOME) \
		verilator $(VERILATOR_FLAGS) --top-module $(LINT_TOP) -f filelist.f
	@echo "Lint passed."

lint-dut:
	@$(MAKE) lint LINT_TOP=dice_core

gen: | $(BUILD_DIR)
	@echo "Generating .mem files from $(TEST_VECTOR).json"
	@python3 $(DICE_HOME)/tb/test_vectors/gen_memfile.py \
		$(DICE_HOME)/tb/test_vectors/$(TEST_VECTOR).json \
		--output-dir $(BUILD_DIR)

sim: gen | $(BUILD_DIR)
	@echo "Running VCS sim with TOP=$(TB)"
	@cd $(BUILD_DIR) && TB_TOP=$(TB) DICE_HOME=$(DICE_HOME) tclsh ../run_vcs.tcl

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) obj_dir
	@echo "Done."
