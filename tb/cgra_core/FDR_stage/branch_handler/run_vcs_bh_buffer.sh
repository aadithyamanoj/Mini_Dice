#!/bin/bash
vcs -full64 -sverilog -dd -debug_access+all -kdb -lca -f filelist_bh_buffer.lst \
    +vcs+initreg+random \
    +define+NO_SRAM \
    -timescale=1ns/1ps \
    -o simv_bh_buffer

if [ $? -eq 0 ]; then
    ./simv_bh_buffer -gui=verdi &
fi
