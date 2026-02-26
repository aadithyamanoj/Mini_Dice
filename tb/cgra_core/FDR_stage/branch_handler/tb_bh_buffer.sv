`timescale 1ns/1ps

module tb_bh_buffer;
  initial begin
    $display("tb_bh_buffer stub");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end
endmodule
