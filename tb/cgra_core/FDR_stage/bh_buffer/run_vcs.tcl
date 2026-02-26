# check top module 
if { [info exists ::env(TB_TOP)] } {
    set tb_top $::env(TB_TOP)
} else {
    set tb_top tb_bh_buffer
}

puts "using top: $tb_top"

exec vcs -full64 -sverilog -f filelist.f \
    +lint=TFIPC-L \
    -top $tb_top \
    -debug_access+pp+all -kdb -lca +vpi \
    +define+FSDB \
    +fsdb+struct=on \
    -o simv

exec ./simv >@stdout 2>@stderr
