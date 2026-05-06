// Observes completed AXI-Lite write and read transactions on the DUT master port.
// A transaction is captured at the response handshake (B or R valid+ready).
class axil_slave_monitor extends uvm_monitor;
  `uvm_component_utils(axil_slave_monitor)

  virtual dice_core_vif vif;

  uvm_analysis_port #(axil_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "axil_slave_monitor: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_writes();
      monitor_reads();
    join
  endtask

  // Capture write address, then write data, then record at B handshake
  task monitor_writes();
    axil_seq_item item;
    logic [15:0] saved_addr;
    logic [15:0] saved_data;
    logic [1:0]  saved_strb;
    forever begin
      // Capture AW
      do @(posedge vif.clk); while (!(vif.axi_awvalid && vif.axi_awready));
      saved_addr = vif.axi_awaddr;

      // Capture W — check current cycle first; AW and W fire on the same cycle
      if (!(vif.axi_wvalid && vif.axi_wready))
        do @(posedge vif.clk); while (!(vif.axi_wvalid && vif.axi_wready));
      saved_data = vif.axi_wdata;
      saved_strb = vif.axi_wstrb;

      // Wait for B
      do @(posedge vif.clk); while (!(vif.axi_bvalid && vif.axi_bready));

      item          = axil_seq_item::type_id::create("wr");
      item.txn_type = axil_seq_item::WRITE;
      item.addr     = saved_addr;
      item.data     = saved_data;
      item.strb     = saved_strb;
      item.resp     = vif.axi_bresp;
      ap.write(item);
      `uvm_info("AXIL_MON", item.convert2string(), UVM_HIGH)
    end
  endtask

  task monitor_reads();
    axil_seq_item item;
    logic [15:0] saved_addr;
    forever begin
      // Capture AR
      do @(posedge vif.clk); while (!(vif.axi_arvalid && vif.axi_arready));
      saved_addr = vif.axi_araddr;

      // Wait for R
      do @(posedge vif.clk); while (!(vif.axi_rvalid && vif.axi_rready));

      item          = axil_seq_item::type_id::create("rd");
      item.txn_type = axil_seq_item::READ;
      item.addr     = saved_addr;
      item.data     = vif.axi_rdata;
      item.resp     = vif.axi_rresp;
      ap.write(item);
      `uvm_info("AXIL_MON", item.convert2string(), UVM_HIGH)
    end
  endtask

endclass
