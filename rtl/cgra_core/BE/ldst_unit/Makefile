# ================================
# User configuration
# ================================
TOP        ?= temporal_coalescing_unit
FILELIST   ?= filelist.f
SDC        ?= chip.sdc
MMMC_TCL   ?= freepdk45_mmmc.tcl
BUILD_DIR  := build
OUTPUT_DIR := outputs
REPORT_DIR := reports
LOG_DIR    := logs

RUN_TCL        := $(BUILD_DIR)/run_syn.tcl
TEMPLATE_TCL   := run_syn_template.tcl

# copied inputs in build
BUILD_FILELIST := $(BUILD_DIR)/$(notdir $(FILELIST))
BUILD_SDC      := $(BUILD_DIR)/$(notdir $(SDC))
BUILD_MMMC     := $(BUILD_DIR)/$(notdir $(MMMC_TCL))

.PHONY: syn clean $(RUN_TCL)

syn: $(RUN_TCL) $(BUILD_FILELIST) $(BUILD_SDC) $(BUILD_MMMC)
	@echo "====================================="
	@echo "  Launching Genus Synthesis"
	@echo "  Top      : $(TOP)"
	@echo "  Filelist : $(FILELIST)"
	@echo "  SDC      : $(SDC)"
	@echo "====================================="
	cd $(BUILD_DIR) && genus -no_gui -overwrite -f run_syn.tcl

# Generate run_syn.tcl from template
$(RUN_TCL):
	@mkdir -p $(BUILD_DIR) $(BUILD_DIR)/$(OUTPUT_DIR) $(BUILD_DIR)/$(REPORT_DIR) $(BUILD_DIR)/$(LOG_DIR)
	@echo "Generating $@ from template"
	@sed \
		-e 's|__TOP__|$(TOP)|g' \
		-e 's|__FILELIST__|$(notdir $(FILELIST))|g' \
		-e 's|__SDC__|$(notdir $(SDC))|g' \
		-e 's|__MMMC__|$(notdir $(MMMC_TCL))|g' \
		-e 's|__OUTPUT_DIR__|$(OUTPUT_DIR)|g' \
		-e 's|__REPORT_DIR__|$(REPORT_DIR)|g' \
		-e 's|__LOG_DIR__|$(LOG_DIR)|g' \
		$(TEMPLATE_TCL) > $(RUN_TCL)
# --------------------------------------------
# Copy input files into build/
# --------------------------------------------
$(BUILD_FILELIST): $(FILELIST)
	@mkdir -p $(BUILD_DIR)
	cp $< $@

$(BUILD_SDC): $(SDC)
	@mkdir -p $(BUILD_DIR)
	cp $< $@

$(BUILD_MMMC): $(MMMC_TCL)
	@mkdir -p $(BUILD_DIR)
	cp $< $@

# --------------------------------------------
# Cleanup
# --------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
	rm -rf *.log* *.cmd*
