// Passive monitor for the CGRA scan-chain programming output.
// Collects each we=1 pulse and publishes it on the analysis port.
// Also reconstructs the full bitstream as a packed bit array for the scoreboard.
class cgra_prog_monitor extends uvm_monitor;
  `uvm_component_utils(cgra_prog_monitor)

  virtual dice_core_vif vif;

  uvm_analysis_port #(cgra_prog_item) ap;

  // Accumulated bitstream (LSB first, index 0 = first bit received)
  logic bitstream [];
  int   bit_count = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "cgra_prog_monitor: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      cgra_prog_item item;
      @(posedge vif.clk);
      if (vif.cgra_prog_we) begin
        item      = cgra_prog_item::type_id::create("item");
        item.dout = vif.cgra_prog_dout;
        item.we   = vif.cgra_prog_we;
        ap.write(item);

        // Accumulate bitstream
        bitstream = new [bit_count + 1] (bitstream);
        bitstream[bit_count] = vif.cgra_prog_dout;
        bit_count++;
        `uvm_info("CGRA_MON", $sformatf("bit[%0d]=%0b", bit_count-1, item.dout), UVM_DEBUG)
      end
    end
  endtask

  function void reset_bitstream();
    bitstream  = {};
    bit_count  = 0;
  endfunction

endclass
