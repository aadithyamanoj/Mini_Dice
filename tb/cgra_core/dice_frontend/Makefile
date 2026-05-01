TB := tb_dice_frontend

.PHONY: sim clean

sim:
	vcs -full64 -sverilog -debug_all -f filelist.f \
	    -l compile.log -timescale=1ns/1ps \
	    +vcs+fsdb -DFSDB -kdb -lca \
	    -top $(TB) && ./simv

clean:
	rm -rf simv simv.daidir compile.log ucli.key vc_hdrs.h \
	       *.fsdb *.vpd csrc DVEfiles novas.rc novas.conf
