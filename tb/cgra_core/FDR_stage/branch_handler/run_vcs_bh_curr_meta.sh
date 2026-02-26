#!/bin/bash
vcs -full64 -sverilog -dd -debug_access+all -kdb -lca -f filelist_bh_curr_meta.lst \
    +vcs+initreg+random \
    +define+NO_SRAM \
    -timescale=1ns/1ps \
    -o simv_bh_curr_meta

if [ $? -eq 0 ]; then
    ./simv_bh_curr_meta -gui=verdi &
fi
