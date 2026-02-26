`timescale 1ns/1ps

module tb_bh_curr_meta;
  initial begin
    $display("tb_bh_curr_meta stub");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end
endmodule
