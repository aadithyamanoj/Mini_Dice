vcs -full64 -sverilog -debug_all -timescale=1ns/100ps \
+incdir+$HW_HOME/rtl/cache +incdir+$HW_HOME/rtl/libs +incdir+$HW_HOME/rtl \
-y $HW_HOME/rtl/libs -y $HW_HOME/rtl/cache +libext+.sv+.v \
-top tb_vx_cache_with_temporal -f filelist.f +vcs+fsdb +lint=TFIPC-L \
-debug_access+pp+all -kdb -lca +vpi 

./simv