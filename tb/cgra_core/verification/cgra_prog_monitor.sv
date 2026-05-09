// Passive monitor for the CGRA scan-chain programming output.
// - bit_ap: one item per cgra_prog_we=1 cycle (raw per-bit stream).
// - bs_ap : one item per completed programming epoch
//   (every DICE_BITSTREAM_SIZE bits), carrying the full bit array.
class cgra_prog_monitor extends uvm_monitor;
  `uvm_component_utils(cgra_prog_monitor)

  virtual dice_core_vif vif;

  uvm_analysis_port #(cgra_prog_item)      bit_ap;
  uvm_analysis_port #(cgra_bitstream_item) bs_ap;

  // Accumulated bitstream for the current epoch (LSB-first)
  logic        bitstream [];
  int unsigned bit_count = 0;
  int unsigned epoch_count = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    bit_ap = new("bit_ap", this);
    bs_ap  = new("bs_ap",  this);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "cgra_prog_monitor: vif not found in config_db")
    bitstream = new[DICE_BITSTREAM_SIZE];
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      cgra_prog_item       bit_item;
      cgra_bitstream_item  bs_item;
      @(posedge vif.clk);
      if (vif.cgra_prog_we_in) begin
        bit_item      = cgra_prog_item::type_id::create("bit_item");
        bit_item.dout = vif.cgra_prog_din;
        bit_item.we   = vif.cgra_prog_we_in;
        bit_ap.write(bit_item);

        bitstream[bit_count] = vif.cgra_prog_din;
        bit_count++;

        if (bit_count == DICE_BITSTREAM_SIZE) begin
          bs_item           = cgra_bitstream_item::type_id::create("bs_item");
          bs_item.bit_count = bit_count;
          bs_item.bits      = new[DICE_BITSTREAM_SIZE](bitstream);
          bs_ap.write(bs_item);
          epoch_count++;
          `uvm_info("CGRA_MON",
                    $sformatf("epoch %0d complete: %0d bits", epoch_count, bit_count),
                    UVM_LOW)
          bit_count = 0;
        end
      end
    end
  endtask

endclass
