// AXI4 fetch memory slave agent.
// Instantiated twice in the env: once for mfetch, once for bsfetch.
// Set port_sel on each instance before build_phase.
class mem_slave_agent extends uvm_agent;
  `uvm_component_utils(mem_slave_agent)

  mem_slave_driver  drv;
  mem_slave_monitor mon;
  uvm_sequencer #(mem_seq_item) seqr;

  uvm_analysis_port #(mem_seq_item) ap;

  // Set before build_phase to select which port this agent manages
  mem_port_sel_e port_sel = MFETCH;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon          = mem_slave_monitor::type_id::create("mon", this);
    mon.port_sel = port_sel;
    ap           = new("ap", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv          = mem_slave_driver::type_id::create("drv", this);
      drv.port_sel = port_sel;
      seqr         = uvm_sequencer #(mem_seq_item)::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
    mon.ap.connect(ap);
  endfunction

  // Convenience wrapper — delegates to driver's load_mem
  function void load_mem(logic [15:0] base_addr, logic [15:0] words []);
    if (drv != null)
      drv.load_mem(base_addr, words);
  endfunction

endclass
