// Top-level UVM environment for dice_core verification.
// Instantiates all agents and the scoreboard and wires them together.
class dice_core_env extends uvm_env;
  `uvm_component_utils(dice_core_env)

  cta_agent           cta_agnt;
  mem_slave_agent     mfetch_agnt;
  mem_slave_agent     bsfetch_agnt;
  axil_slave_agent    axil_agnt;
  cgra_prog_monitor   cgra_mon;
  dice_core_scoreboard sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cta_agnt     = cta_agent::type_id::create("cta_agnt",     this);
    axil_agnt    = axil_slave_agent::type_id::create("axil_agnt", this);
    cgra_mon     = cgra_prog_monitor::type_id::create("cgra_mon", this);
    sb           = dice_core_scoreboard::type_id::create("sb", this);

    mfetch_agnt  = mem_slave_agent::type_id::create("mfetch_agnt",  this);
    bsfetch_agnt = mem_slave_agent::type_id::create("bsfetch_agnt", this);

    // Tell each mem agent which DUT port to drive
    mfetch_agnt.port_sel  = MFETCH;
    bsfetch_agnt.port_sel = BSFETCH;
  endfunction

  function void connect_phase(uvm_phase phase);
    // Wire monitors to scoreboard FIFOs
    axil_agnt.ap.connect(sb.axil_fifo.analysis_export);
    cta_agnt.dispatch_ap.connect(sb.cta_dispatch_fifo.analysis_export);
    cta_agnt.complete_ap.connect(sb.cta_complete_fifo.analysis_export);
  endfunction

endclass
