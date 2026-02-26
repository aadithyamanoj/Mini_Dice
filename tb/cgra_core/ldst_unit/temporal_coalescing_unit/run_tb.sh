    vcs -full64 -sverilog -debug_all -f filelist.f -l compile.log -timescale=1ns/10ps +vcs+fsdb +lint=TFIPC-L \
-debug_access+pp+all -kdb -lca +vpi 

    ./simv

