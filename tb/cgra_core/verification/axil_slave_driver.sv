// AXI-Lite slave driver: accepts transactions from the DUT's master port
// and drives back responses.
// Default behavior: accept all writes with OKAY, return 0 for all reads.
// Override respond_write / respond_read in a subclass for richer behaviour.
class axil_slave_driver extends uvm_driver #(axil_seq_item);
  `uvm_component_utils(axil_slave_driver)

  virtual dice_core_vif vif;

  // Configurable response data for reads (address → data)
  logic [15:0] read_mem [logic [15:0]];

  // Configurable error responses (address → 2-bit rresp/bresp).
  // Default behavior: any address not in this map returns OKAY (2'b00).
  // Tests inject SLVERR (2'b10) or DECERR (2'b11) here to exercise the
  // master's error-handshake path.
  logic [1:0]  read_resp_err  [logic [15:0]];
  logic [1:0]  write_resp_err [logic [15:0]];

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

      // Accept W — check current cycle first; only advance if not yet valid
      if (!vif.axi_wvalid)
        do @(posedge vif.clk); while (!vif.axi_wvalid);
      wd = vif.axi_wdata;
      ws = vif.axi_wstrb;

      // Send B response
      vif.axi_bvalid = 1'b1;
      vif.axi_bresp  = respond_write(aw_addr, wd, ws);
      do @(posedge vif.clk); while (!vif.axi_bready);
      #1;
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
      `uvm_info("AXIL_DRV", $sformatf("AR:    addr=0x%04x t=%0t", ar_addr, $time), UVM_NONE)

      // Send R response
      vif.axi_rvalid = 1'b1;
      vif.axi_rdata  = read_mem.exists(ar_addr) ? read_mem[ar_addr] : 16'h0000;
      vif.axi_rresp  = read_resp_err.exists(ar_addr) ? read_resp_err[ar_addr] : 2'b00;
      do @(posedge vif.clk); while (!vif.axi_rready);
      // Delay 1 ns before deasserting so the FSM's always_ff samples rvalid=1
      // at this posedge before it is pulled low (avoids active-region race).
      #1;
      vif.axi_rvalid = 1'b0;
      `uvm_info("AXIL_DRV", $sformatf("Read:  addr=0x%04x data=0x%04x", ar_addr, vif.axi_rdata), UVM_NONE)
    end
  endtask

  // Override to implement custom write response logic
  virtual function logic [1:0] respond_write(logic [15:0] addr,
                                              logic [15:0] data,
                                              logic [1:0]  strb);
    if (write_resp_err.exists(addr)) return write_resp_err[addr];
    return 2'b00;  // OKAY
  endfunction

endclass
