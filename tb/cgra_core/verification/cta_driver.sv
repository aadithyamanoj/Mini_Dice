// Drives CTA dispatch to dice_core via dice_core_vif.
class cta_driver extends uvm_driver #(cta_seq_item);
  `uvm_component_utils(cta_driver)


  virtual dice_core_vif vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "cta_driver: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    cta_seq_item item;
    // Idle state
    vif.cta_dispatch_valid <= 1'b0;
    vif.cta_dispatch_data  <= '0;
    vif.cta_complete_ready <= 1'b1;

    @(negedge vif.rst);  // wait for reset release
    @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(item);
      drive_dispatch(item);
      seq_item_port.item_done();
    end
  endtask

  task drive_dispatch(cta_seq_item item);
    dice_cta_desc_t desc;
    desc.cta_id               = item.cta_id;
    desc.kernel_desc.start_pc = item.start_pc;
    desc.kernel_desc.thread_count = item.thread_count;
    desc.kernel_desc.grid_size    = item.grid_size;

    // Assert dispatch
    @(posedge vif.clk);
    vif.cta_dispatch_valid <= 1'b1;
    vif.cta_dispatch_data  <= desc;

    // Wait for ready handshake
    do @(posedge vif.clk); while (!vif.cta_dispatch_ready);

    // Hold for extra cycles if requested
    repeat (item.hold_cycles - 1) @(posedge vif.clk);

    vif.cta_dispatch_valid <= 1'b0;
    `uvm_info("CTA_DRV", $sformatf("Dispatched: %s", item.convert2string()), UVM_MEDIUM)
  endtask

endclass
