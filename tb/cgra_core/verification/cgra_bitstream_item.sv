// One full CGRA scan-chain programming epoch (DICE_BITSTREAM_SIZE bits).
// Emitted by cgra_prog_monitor each time the chain completes a programming.
class cgra_bitstream_item extends uvm_sequence_item;
  `uvm_object_utils(cgra_bitstream_item)

  logic        bits [];     // [0] = first bit shifted in
  int unsigned bit_count;

  function new(string name = "cgra_bitstream_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("CGRA_BITSTREAM bit_count=%0d", bit_count);
  endfunction

endclass
