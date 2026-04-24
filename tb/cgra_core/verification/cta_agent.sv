// CTA agent: driver + monitor for the CTA dispatch interface.
// Set is_active = UVM_PASSIVE to disable the driver (monitor-only mode).
class cta_agent extends uvm_agent;
  `uvm_component_utils(cta_agent)

  cta_driver    drv;
  cta_monitor   mon;
  uvm_sequencer #(cta_seq_item) seqr;

  // Analysis ports forwarded from monitor
  uvm_analysis_port #(cta_seq_item) dispatch_ap;
  uvm_analysis_port #(cta_seq_item) complete_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon         = cta_monitor::type_id::create("mon", this);
    dispatch_ap = new("dispatch_ap", this);
    complete_ap = new("complete_ap", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv  = cta_driver::type_id::create("drv", this);
      seqr = uvm_sequencer #(cta_seq_item)::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
    mon.dispatch_ap.connect(dispatch_ap);
    mon.complete_ap.connect(complete_ap);
  endfunction

endclass
