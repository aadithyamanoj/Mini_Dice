// Passively observes fetch memory transactions (AR + R channels).
class mem_slave_monitor extends uvm_monitor;
  `uvm_component_utils(mem_slave_monitor)


  virtual dice_core_vif vif;

  mem_port_sel_e port_sel = MFETCH;

  uvm_analysis_port #(mem_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "mem_slave_monitor: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      mem_seq_item item;
      slv_req_t    req;
      logic        ar_ready;

      // Wait for a clean AR handshake — strict-equals filters X during reset
      do begin
        @(posedge vif.clk);
        req      = (port_sel == MFETCH) ? vif.mfetch_req : vif.bsfetch_req;
        ar_ready = (port_sel == MFETCH) ? vif.mfetch_resp.ar_ready
                                        : vif.bsfetch_resp.ar_ready;
      end while (!(req.ar_valid === 1'b1 && ar_ready === 1'b1));

      item      = mem_seq_item::type_id::create("item");
      item.addr = req.ar.addr;
      item.id   = req.ar.id;
      item.len  = req.ar.len;
      item.size = req.ar.size;
      ap.write(item);
      `uvm_info("MEM_MON", $sformatf("[%s] %s", port_sel.name(),
                item.convert2string()), UVM_HIGH)
    end
  endtask

endclass
