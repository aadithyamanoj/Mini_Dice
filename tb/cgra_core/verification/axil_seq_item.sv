// One AXI-Lite transaction (write or read) on the LDST master port.
class axil_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axil_seq_item)

  typedef enum bit { WRITE, READ } txn_type_e;
  txn_type_e txn_type;

  // Address / data captured from DUT outputs
  logic [15:0] addr;
  logic [15:0] data;   // wdata for writes, rdata for reads
  logic [1:0]  strb;   // wstrb for writes
  logic [1:0]  resp;   // bresp / rresp

  function new(string name = "axil_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    if (txn_type == WRITE)
      return $sformatf("AXIL WRITE addr=0x%04x data=0x%04x strb=%02b resp=%02b",
                       addr, data, strb, resp);
    else
      return $sformatf("AXIL READ  addr=0x%04x data=0x%04x resp=%02b",
                       addr, data, resp);
  endfunction

endclass