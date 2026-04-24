// Observes CTA dispatch handshakes and completion signals.
// Broadcasts captured items on the analysis port.
class cta_monitor extends uvm_monitor;
  `uvm_component_utils(cta_monitor)


  virtual dice_core_vif vif;

  uvm_analysis_port #(cta_seq_item) dispatch_ap;  // dispatched CTAs
  uvm_analysis_port #(cta_seq_item) complete_ap;  // completed CTAs

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    dispatch_ap = new("dispatch_ap", this);
    complete_ap = new("complete_ap", this);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "cta_monitor: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_dispatch();
      monitor_complete();
    join
  endtask

  task monitor_dispatch();
    cta_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.cta_dispatch_valid && vif.cta_dispatch_ready) begin
        item = cta_seq_item::type_id::create("dispatch_item");
        item.start_pc     = vif.cta_dispatch_data.kernel_desc.start_pc;
        item.thread_count = vif.cta_dispatch_data.kernel_desc.thread_count;
        item.grid_size    = vif.cta_dispatch_data.kernel_desc.grid_size;
        item.cta_id       = vif.cta_dispatch_data.cta_id;
        dispatch_ap.write(item);
        `uvm_info("CTA_MON", $sformatf("Dispatch observed: %s", item.convert2string()), UVM_HIGH)
      end
    end
  endtask

  task monitor_complete();
    cta_seq_item item;
    forever begin
      @(posedge vif.clk);
      if (vif.cta_complete_valid && vif.cta_complete_ready) begin
        item = cta_seq_item::type_id::create("complete_item");
        complete_ap.write(item);
        `uvm_info("CTA_MON", "CTA complete observed", UVM_HIGH)
      end
    end
  endtask

endclass
