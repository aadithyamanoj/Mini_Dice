#vcs -full64 -sverilog -debug_all -f filelist.f -l compile.log -timescale=1ns/100ps
#./simv

vcs -full64 -sverilog -f filelist.f \
    -debug_access+pp+all -kdb -lca +vpi \
    +define+FSDB \
    -timescale=1ns/100ps \
    -o simv
./simv