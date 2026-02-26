`timescale 1ns/1ps

module tb_bh_fifo;
  initial begin
    $display("tb_bh_fifo stub");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end
endmodule
