// AXI-Lite slave agent for the DUT's LDST master port.
class axil_slave_agent extends uvm_agent;
  `uvm_component_utils(axil_slave_agent)

  axil_slave_driver  drv;
  axil_slave_monitor mon;
  uvm_sequencer #(axil_seq_item) seqr;

  uvm_analysis_port #(axil_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = axil_slave_monitor::type_id::create("mon", this);
    ap  = new("ap", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv  = axil_slave_driver::type_id::create("drv", this);
      seqr = uvm_sequencer #(axil_seq_item)::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
    mon.ap.connect(ap);
  endfunction

endclass
