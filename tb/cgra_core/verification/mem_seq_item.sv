// One AXI4 read transaction seen on a fetch memory port.
// The driver uses this to know what data to return for a given address.
class mem_seq_item extends uvm_sequence_item;
  `uvm_object_utils(mem_seq_item)

  // Request fields (captured from DUT AR channel by the driver)
  logic [15:0] addr;
  logic [3:0]  id;
  logic [7:0]  len;   // burst length - 1
  logic [2:0]  size;  // beat size exponent (bytes = 2^size)

  // Response fields (driven back on R channel)
  rand logic [15:0] data [];   // one entry per beat
  rand logic [1:0]  resp;      // 2'b00 = OKAY

  constraint c_resp_okay { resp == 2'b00; }

  function new(string name = "mem_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("MEM ar addr=0x%04x id=%0d len=%0d resp=%02b",
                     addr, id, len, resp);
  endfunction

endclass
