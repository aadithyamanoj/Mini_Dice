.PHONY: sim clean

SHELL := /bin/bash

TB ?= tb_decode

sim:
	@echo "Running VCS sim with TOP=$(TB)"
	@TB_TOP=$(TB) tclsh run_vcs.tcl

clean:
	@echo "Cleaning VCS + Verdi artifacts (but keeping novas.conf / novas.rc)..."
	@rm -rf simv \
	        simv.daidir \
	        csrc \
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
