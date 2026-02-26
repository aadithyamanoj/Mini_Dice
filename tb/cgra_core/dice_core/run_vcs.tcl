# check top module
if { [info exists ::env(TB_TOP)] } {
    set tb_top $::env(TB_TOP)
} else {
    set tb_top addr_swizzle_tb
}

puts "using top: $tb_top"


exec vcs -full64 -sverilog -f ../filelist.f \
    -O0 \
    +lint=TFIPC-L \
    -top $tb_top \
    -debug_access+all -kdb -lca +vpi \
    +define+FSDB \
    +fsdb+struct=on \
    -o simv

exec ./simv >@stdout 2>@stderr
