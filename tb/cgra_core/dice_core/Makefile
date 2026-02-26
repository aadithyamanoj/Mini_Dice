.PHONY: sim gen clean

SHELL := /bin/bash

TB         ?= tb_dice_core
DICE_HOME  ?= $(shell cd ../../.. && pwd)
TEST_VECTOR ?= kernel_simple
BUILD_DIR  := build

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

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
	@rm -rf $(BUILD_DIR)
	@echo "Done."
