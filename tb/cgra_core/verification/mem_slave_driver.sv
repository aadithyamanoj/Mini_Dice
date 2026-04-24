// AXI4 slave driver for a fetch memory port (mfetch or bsfetch).
// Watches the DUT's AR channel and returns data from an internal memory model.
// Only the read path is implemented — the DUT never writes to fetch memories.
//
// Usage: call load_mem() before run_phase starts to pre-populate instruction data.
class mem_slave_driver extends uvm_driver #(mem_seq_item);
  `uvm_component_utils(mem_slave_driver)


  virtual dice_core_vif vif;

  // Which fetch port this driver manages
  mem_port_sel_e port_sel = MFETCH;

  // Simple word-addressed memory model (address → 16-bit word)
  logic [15:0] mem_model [logic [15:0]];

  // Configurable response latency (cycles between AR and first R beat)
  int unsigned resp_latency = 1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual dice_core_vif)::get(this, "", "vif", vif))
      `uvm_fatal("CFG", "mem_slave_driver: vif not found in config_db")
  endfunction

  // Pre-load a block of words into the memory model starting at base_addr.
  function void load_mem(logic [15:0] base_addr, logic [15:0] words []);
    foreach (words[i])
      mem_model[base_addr + 16'(i)] = words[i];
  endfunction

  task run_phase(uvm_phase phase);
    idle_resp();
    @(negedge vif.rst);
    @(posedge vif.clk);
    forever serve_read_request();
  endtask

  task idle_resp();
    if (port_sel == MFETCH) begin
      vif.mfetch_resp  = '0;
      vif.mfetch_resp.ar_ready = 1'b1;
    end else begin
      vif.bsfetch_resp  = '0;
      vif.bsfetch_resp.ar_ready = 1'b1;
    end
  endtask

  task serve_read_request();
    slv_req_t  req;
    slv_resp_t resp_out;
    mem_seq_item item;
    int unsigned beats;

    // Wait for AR valid
    do begin
      @(posedge vif.clk);
      req = (port_sel == MFETCH) ? vif.mfetch_req : vif.bsfetch_req;
    end while (!req.ar_valid);

    // Accept the address
    item       = mem_seq_item::type_id::create("item");
    item.addr  = req.ar.addr;
    item.id    = req.ar.id;
    item.len   = req.ar.len;
    item.size  = req.ar.size;
    beats      = int'(req.ar.len) + 1;

    // De-assert ar_ready for one cycle (simulate accept)
    set_ar_ready(1'b0);
    @(posedge vif.clk);
    set_ar_ready(1'b1);

    // Optional latency before responding
    repeat (resp_latency) @(posedge vif.clk);

    // Drive R channel beat by beat
    for (int i = 0; i < beats; i++) begin
      logic [15:0] addr_i = item.addr + 16'(i);
      logic [15:0] data_i = mem_model.exists(addr_i) ? mem_model[addr_i] : 16'hDEAD;

      set_r(item.id, data_i, 2'b00, (i == beats - 1));

      // Wait for r_ready, then delay 1ns so next beat's data change lands
      // after the DUT's posedge sampling (avoids active-region race).
      do @(posedge vif.clk); while (!get_r_ready());
      #1;
    end

    clear_r();
    `uvm_info("MEM_DRV", $sformatf("[%s] %s beats=%0d",
              port_sel.name(), item.convert2string(), beats), UVM_HIGH)
  endtask

  // -------------------------------------------------------------------------
  // Helpers: abstract away which port we're driving
  // -------------------------------------------------------------------------
  function void set_ar_ready(logic val);
    if (port_sel == MFETCH) vif.mfetch_resp.ar_ready  = val;
    else                    vif.bsfetch_resp.ar_ready  = val;
  endfunction

  function void set_r(logic [3:0] id, logic [15:0] data,
                      logic [1:0] resp, logic last);
    if (port_sel == MFETCH) begin
      vif.mfetch_resp.r.id   = id;
      vif.mfetch_resp.r.data = data;
      vif.mfetch_resp.r.resp = resp;
      vif.mfetch_resp.r.last = last;
      vif.mfetch_resp.r_valid = 1'b1;
    end else begin
      vif.bsfetch_resp.r.id   = id;
      vif.bsfetch_resp.r.data = data;
      vif.bsfetch_resp.r.resp = resp;
      vif.bsfetch_resp.r.last = last;
      vif.bsfetch_resp.r_valid = 1'b1;
    end
  endfunction

  function void clear_r();
    if (port_sel == MFETCH) begin
      vif.mfetch_resp.r_valid = 1'b0;
      vif.mfetch_resp.r       = '0;
    end else begin
      vif.bsfetch_resp.r_valid = 1'b0;
      vif.bsfetch_resp.r       = '0;
    end
  endfunction

  function logic get_r_ready();
    slv_req_t req = (port_sel == MFETCH) ? vif.mfetch_req : vif.bsfetch_req;
    return req.r_ready;
  endfunction

endclass
