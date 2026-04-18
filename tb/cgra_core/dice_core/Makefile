.PHONY: sim sim-interface gen clean

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

# Default sim: end-to-end test with test vectors (tb_dice_core)
sim: gen | $(BUILD_DIR)
	@echo "Running VCS sim with TOP=$(TB)"
	@cd $(BUILD_DIR) && TB_TOP=$(TB) DICE_HOME=$(DICE_HOME) tclsh ../run_vcs.tcl

# Interface stress sim: valid-ready handshake / backpressure scenarios
# No test-vector generation needed — synthetic metadata is embedded in the TB.
# Usage: make sim-interface
sim-interface: | $(BUILD_DIR)
	@echo "Running VCS sim with TOP=tb_dice_core_interface"
	@cd $(BUILD_DIR) && TB_TOP=tb_dice_core_interface DICE_HOME=$(DICE_HOME) tclsh ../run_vcs.tcl

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@echo "Done."
