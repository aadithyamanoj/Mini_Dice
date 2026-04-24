// AXI-Lite slave driver: accepts transactions from the DUT's master port
// and drives back responses.
// Default behavior: accept all writes with OKAY, return 0 for all reads.
// Override respond_write / respond_read in a subclass for richer behaviour.
class axil_slave_driver extends uvm_driver #(axil_seq_item);
  `uvm_component_utils(axil_slave_driver)

  virtual dice_core_vif vif;

  // Configurable response data for reads (address → data)
  logic [15:0] read_mem [logic [15:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "axil_slave_driver: vif not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    idle();
    @(negedge vif.rst);
    @(posedge vif.clk);
    fork
      handle_writes();
      handle_reads();
    join
  endtask

  task idle();
    vif.axi_awready = 1'b1;
    vif.axi_wready  = 1'b1;
    vif.axi_bvalid  = 1'b0;
    vif.axi_bresp   = 2'b00;
    vif.axi_arready = 1'b1;
    vif.axi_rvalid  = 1'b0;
    vif.axi_rdata   = '0;
    vif.axi_rresp   = 2'b00;
  endtask

  task handle_writes();
    logic [15:0] aw_addr;
    logic [15:0] wd;
    logic [1:0]  ws;
    forever begin
      // Accept AW
      do @(posedge vif.clk); while (!vif.axi_awvalid);
      aw_addr = vif.axi_awaddr;

      // Accept W (may arrive same cycle or later)
      do @(posedge vif.clk); while (!vif.axi_wvalid);
      wd = vif.axi_wdata;
      ws = vif.axi_wstrb;

      // Send B response
      vif.axi_bvalid = 1'b1;
      vif.axi_bresp  = respond_write(aw_addr, wd, ws);
      do @(posedge vif.clk); while (!vif.axi_bready);
      vif.axi_bvalid = 1'b0;
      `uvm_info("AXIL_DRV", $sformatf("Write: addr=0x%04x data=0x%04x", aw_addr, wd), UVM_HIGH)
    end
  endtask

  task handle_reads();
    logic [15:0] ar_addr;
    forever begin
      // Accept AR
      do @(posedge vif.clk); while (!vif.axi_arvalid);
      ar_addr = vif.axi_araddr;

      // Send R response
      vif.axi_rvalid = 1'b1;
      vif.axi_rdata  = read_mem.exists(ar_addr) ? read_mem[ar_addr] : 16'h0000;
      vif.axi_rresp  = 2'b00;
      do @(posedge vif.clk); while (!vif.axi_rready);
      vif.axi_rvalid = 1'b0;
      `uvm_info("AXIL_DRV", $sformatf("Read:  addr=0x%04x data=0x%04x", ar_addr, vif.axi_rdata), UVM_HIGH)
    end
  endtask

  // Override to implement custom write response logic
  virtual function logic [1:0] respond_write(logic [15:0] addr,
                                              logic [15:0] data,
                                              logic [1:0]  strb);
    return 2'b00;  // OKAY
  endfunction

endclass
