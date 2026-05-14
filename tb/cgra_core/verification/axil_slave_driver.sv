// 4-port AXI-Lite slave driver for the new dice_core LDST interface.
//
// Topology (per dice_core ports):
//   - AW/W/B/AR: NUM_MEM_PORTS=4 independent channels, one per CGRA mem port
//   - R: SHARED single channel; ARUSER tags identify which port a response
//     belongs to. Master must keep enough outstanding-tag accounting to
//     route incoming rdata back to the correct port.
//
// Read response packing (per mem_req_fifo.sv):
//   rdata[15:0]   = load data
//   rdata[27:16]  = echoed metadata (aruser[11:0]: tid|eblock|rsp_addr)
//   rdata[31:28]  = unused
//
// Default: writes return OKAY, reads return read_mem[addr] or 0.
class axil_slave_driver extends uvm_driver #(axil_seq_item);
  `uvm_component_utils(axil_slave_driver)

  virtual dice_core_vif vif;

  // Configurable response data for reads (address → data)
  logic [15:0] read_mem [logic [15:0]];

  // Configurable error responses (addr → 2-bit rresp/bresp)
  logic [1:0]  read_resp_err  [logic [15:0]];
  logic [1:0]  write_resp_err [logic [15:0]];

  // Pending read queue (FIFO of captured ARs awaiting R service)
  typedef struct packed {
    logic [1:0]                 port_id;
    logic [15:0]                addr;
    logic [AxiUserWidth-1:0]    aruser;
  } pending_read_t;

  pending_read_t read_q[$];

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
      // Per-port write servers (independent AW/W/B per port)
      handle_writes_port(0);
      handle_writes_port(1);
      handle_writes_port(2);
      handle_writes_port(3);
      // Per-port read capture (push AR transactions into shared queue)
      capture_reads_port(0);
      capture_reads_port(1);
      capture_reads_port(2);
      capture_reads_port(3);
      // Single read server for the shared R channel
      serve_reads();
    join
  endtask

  task idle();
    vif.axi_awready = '1;     // 4-bit packed: all ports ready
    vif.axi_wready  = '1;
    vif.axi_bvalid  = '0;
    vif.axi_bresp   = '0;
    vif.axi_arready = '1;
    vif.axi_rvalid  = 1'b0;   // shared 1-bit
    vif.axi_rdata   = '0;
    vif.axi_rresp   = 2'b00;
  endtask

  task handle_writes_port(int unsigned p);
    logic [15:0] aw_addr, wd;
    logic [1:0]  ws;
    forever begin
      // Capture AW handshake on this port
      do @(posedge vif.clk); while (vif.axi_awvalid[p] !== 1'b1);
      aw_addr = vif.axi_awaddr[p];

      // W may co-fire with AW (same cycle) or arrive later — check current
      // cycle first to avoid the single-cycle slip race
      if (vif.axi_wvalid[p] !== 1'b1)
        do @(posedge vif.clk); while (vif.axi_wvalid[p] !== 1'b1);
      wd = vif.axi_wdata[p];
      ws = vif.axi_wstrb[p];

      // Drive B response on this port
      vif.axi_bvalid[p] = 1'b1;
      vif.axi_bresp[p]  = respond_write(aw_addr, wd, ws);
      do @(posedge vif.clk); while (vif.axi_bready[p] !== 1'b1);
      #1;
      vif.axi_bvalid[p] = 1'b0;
      `uvm_info("AXIL_DRV",
        $sformatf("Write[p%0d]: addr=0x%04x data=0x%04x strb=%0b",
                  p, aw_addr, wd, ws), UVM_HIGH)
    end
  endtask

  task capture_reads_port(int unsigned p);
    pending_read_t req;
    forever begin
      @(posedge vif.clk);
      if (vif.axi_arvalid[p] === 1'b1 && vif.axi_arready[p] === 1'b1) begin
        req.port_id = p[1:0];
        req.addr    = vif.axi_araddr[p];
        req.aruser  = vif.axi_aruser[p];
        read_q.push_back(req);
        `uvm_info("AXIL_DRV",
          $sformatf("AR[p%0d]: addr=0x%04x aruser=0x%0x",
                    p, req.addr, req.aruser), UVM_HIGH)
      end
    end
  endtask

  // Shared R channel: serve one queued read at a time
  task serve_reads();
    pending_read_t req;
    logic [15:0]   data;
    logic [12:0]   meta_echo;   // 13 bits: tid[4:0] | eblock[2:0] | rsp_addr[4:0]
    forever begin
      // Wait until at least one AR has been captured
      while (read_q.size() == 0) @(posedge vif.clk);
      req = read_q.pop_front();

      data      = read_mem.exists(req.addr) ? read_mem[req.addr] : 16'h0000;
      meta_echo = req.aruser[12:0];   // tid|eblock|rsp_addr (drop only is_meta @ [13])

      vif.axi_rdata  = {3'b0, meta_echo, data};
      vif.axi_rresp  = read_resp_err.exists(req.addr) ? read_resp_err[req.addr]
                                                      : 2'b00;
      vif.axi_rvalid = 1'b1;
      do @(posedge vif.clk); while (vif.axi_rready !== 1'b1);
      // 1 ns deassert delay — keeps rvalid sampled high in master's always_ff
      // before going low (avoids active-region race)
      #1;
      vif.axi_rvalid = 1'b0;

      `uvm_info("AXIL_DRV",
        $sformatf("R[p%0d]: addr=0x%04x data=0x%04x", req.port_id, req.addr, data),
        UVM_HIGH)
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
