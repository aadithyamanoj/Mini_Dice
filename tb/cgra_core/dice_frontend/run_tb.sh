#!/bin/bash
vcs -full64 -sverilog -debug_all -f filelist.f \
    -l compile.log -timescale=1ns/1ps \
    +vcs+fsdb -DFSDB -kdb -lca -debug_access+pp+all +vpi \
    -top tb_dice_frontend
./simv
