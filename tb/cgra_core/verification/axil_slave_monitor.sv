// 4-port AXI-Lite slave monitor.
// Captures completed write transactions per port (at B handshake) and
// completed read transactions on the shared R channel (decoded from rdata
// + the matching AR queue).
class axil_slave_monitor extends uvm_monitor;
  `uvm_component_utils(axil_slave_monitor)

  virtual dice_core_vif vif;

  uvm_analysis_port #(axil_seq_item) ap;

  // Pending-read tracking: AR captured per-port, popped on R handshake
  typedef struct packed {
    logic [1:0]              port_id;
    logic [15:0]             addr;
    logic [AxiUserWidth-1:0] aruser;
  } pending_read_t;

  pending_read_t read_q[$];

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
      monitor_writes_port(0);
      monitor_writes_port(1);
      monitor_writes_port(2);
      monitor_writes_port(3);
      monitor_ar_port(0);
      monitor_ar_port(1);
      monitor_ar_port(2);
      monitor_ar_port(3);
      monitor_r();
    join
  endtask

  task monitor_writes_port(int unsigned p);
    axil_seq_item item;
    logic [15:0] saved_addr, saved_data;
    logic [1:0]  saved_strb;
    forever begin
      // AW handshake
      do @(posedge vif.clk);
      while (!(vif.axi_awvalid[p] === 1'b1 && vif.axi_awready[p] === 1'b1));
      saved_addr = vif.axi_awaddr[p];

      // W handshake (same cycle or later)
      if (!(vif.axi_wvalid[p] === 1'b1 && vif.axi_wready[p] === 1'b1))
        do @(posedge vif.clk);
        while (!(vif.axi_wvalid[p] === 1'b1 && vif.axi_wready[p] === 1'b1));
      saved_data = vif.axi_wdata[p];
      saved_strb = vif.axi_wstrb[p];

      // B handshake
      do @(posedge vif.clk);
      while (!(vif.axi_bvalid[p] === 1'b1 && vif.axi_bready[p] === 1'b1));

      item          = axil_seq_item::type_id::create("wr");
      item.txn_type = axil_seq_item::WRITE;
      item.addr     = saved_addr;
      item.data     = saved_data;
      item.strb     = saved_strb;
      item.resp     = vif.axi_bresp[p];
      ap.write(item);
      `uvm_info("AXIL_MON",
        $sformatf("[p%0d] %s", p, item.convert2string()), UVM_HIGH)
    end
  endtask

  task monitor_ar_port(int unsigned p);
    pending_read_t req;
    forever begin
      @(posedge vif.clk);
      if (vif.axi_arvalid[p] === 1'b1 && vif.axi_arready[p] === 1'b1) begin
        req.port_id = p[1:0];
        req.addr    = vif.axi_araddr[p];
        req.aruser  = vif.axi_aruser[p];
        read_q.push_back(req);
      end
    end
  endtask

  task monitor_r();
    axil_seq_item   item;
    pending_read_t  req;
    forever begin
      @(posedge vif.clk);
      if (vif.axi_rvalid === 1'b1 && vif.axi_rready === 1'b1) begin
        if (read_q.size() == 0) begin
          `uvm_warning("AXIL_MON", "R handshake with no pending AR — dropped")
          continue;
        end
        req = read_q.pop_front();

        item          = axil_seq_item::type_id::create("rd");
        item.txn_type = axil_seq_item::READ;
        item.addr     = req.addr;
        item.data     = vif.axi_rdata[15:0];   // load data in low 16 bits
        item.resp     = vif.axi_rresp;
        ap.write(item);
        `uvm_info("AXIL_MON",
          $sformatf("[p%0d] %s", req.port_id, item.convert2string()), UVM_HIGH)
      end
    end
  endtask

endclass
