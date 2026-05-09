// One CGRA scan-chain programming pulse (we=1 cycle with a data bit).
class cgra_prog_item extends uvm_sequence_item;
  `uvm_object_utils(cgra_prog_item)

  logic dout;   // serial bit shifted in
  logic we;     // write-enable pulse

  function new(string name = "cgra_prog_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("CGRA_PROG dout=%0b we=%0b", dout, we);
  endfunction

endclass
