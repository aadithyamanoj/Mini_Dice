// =============================================================================
// mini_dice_chip_pkg.sv — UVM package for the mini_dice_top chip-level env.
//
// Components:
//   - csr_agent       : drives CSR writes through the FPGA-side axi_link_tx.
//                       Sequences emit (addr, data) pairs; driver issues AW + W
//                       and waits for an internal "B-equivalent" (none — the
//                       link wrapper eliminates B per slide 39 of the deck).
//   - mem_agent       : services chip-side reads/writes via the FPGA-side
//                       axi_link_rx. Reads are answered from the DPI memory
//                       store; writes are recorded for the scoreboard.
//   - chip_scoreboard : compares observed AXI writes against expected_writes
//                       loaded from the test vector runtime JSON via DPI.
//
// Tests live in tests/ and are included at the bottom of this package.
// =============================================================================

package mini_dice_chip_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import dice_pkg::*;
  import DE_pkg::*;

  // DPI imports — runtime state shared with the core-level env
  import "DPI-C" context function void dice_core_tb_init(
    input string cta_desc_mem_file,
    input string meta_mem_file,
    input string bitstream_mem_file,
    input string runtime_json_file
  );
  import "DPI-C" context function int unsigned dice_core_tb_has_init_error();
  import "DPI-C" context function string dice_core_tb_get_init_error();
  import "DPI-C" context function int unsigned dice_core_tb_get_cta_desc_word(
    input int unsigned word_idx
  );
  import "DPI-C" context function int unsigned dice_core_tb_get_csr(input int unsigned csr_idx);
  import "DPI-C" context function int unsigned dice_core_tb_meta_read16(input int unsigned byte_addr);
  import "DPI-C" context function int unsigned dice_core_tb_meta_read32(input int unsigned byte_addr);
  import "DPI-C" context function int unsigned dice_core_tb_bitstream_read16(
    input int unsigned byte_addr
  );
  import "DPI-C" context function int unsigned dice_core_tb_bitstream_read32(
    input int unsigned byte_addr
  );
  import "DPI-C" context function int unsigned dice_core_tb_axi_read16(input int unsigned addr);
  import "DPI-C" context function void dice_core_tb_record_axi_write(
    input int unsigned addr,
    input int unsigned data,
    input int unsigned strb
  );
  import "DPI-C" context function int unsigned dice_core_tb_check_done();

  // CSR map (mirrors tb_chip_top / mini_dice_top's cgra_io_csr)
  localparam logic [15:0] CSR_BASE         = 16'hFF00;
  localparam logic [15:0] REG_CTRL         = CSR_BASE + 16'h0000;
  localparam logic [15:0] REG_STARTPC      = CSR_BASE + 16'h0002;
  localparam logic [15:0] REG_STATUS       = CSR_BASE + 16'h0004;
  localparam logic [15:0] REG_THREAD_COUNT = CSR_BASE + 16'h000c;
  localparam logic [15:0] REG_CSRX0        = CSR_BASE + 16'h0010;

  localparam logic [15:0] CTRL_START       = 16'h0001;
  localparam logic [15:0] CTRL_CGRA_RESET  = 16'h0002;
  localparam logic [15:0] CTRL_BSLOAD_EN   = 16'h0004;

  // ---------------------------------------------------------------------------
  // csr_seq_item : one CSR write transaction (16-bit data, 16-bit addr)
  // ---------------------------------------------------------------------------
  class csr_seq_item extends uvm_sequence_item;
    `uvm_object_utils(csr_seq_item)
    rand logic [15:0] addr;
    rand logic [15:0] data;
    function new(string name = "csr_seq_item"); super.new(name); endfunction
    function string convert2string();
      return $sformatf("CSR addr=0x%04x data=0x%04x", addr, data);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // csr_driver : drives WRITE flits at the FPGA-side TX of axi_link_tx in the TB
  // ---------------------------------------------------------------------------
  class csr_driver extends uvm_driver #(csr_seq_item);
    `uvm_component_utils(csr_driver)
    virtual mini_dice_chip_vif vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db #(virtual mini_dice_chip_vif)::get(this, "", "vif", vif))
        `uvm_fatal("CFG", "csr_driver: vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      // Idle outputs
      vif.ep_tx_awvalid = 1'b0;
      vif.ep_tx_wvalid  = 1'b0;
      vif.ep_tx_arvalid = 1'b0;
      vif.ep_tx_awaddr  = '0;
      vif.ep_tx_awlen   = '0;
      vif.ep_tx_awid    = '0;
      vif.ep_tx_wdata   = '0;
      vif.ep_tx_wlast   = 1'b1;
      vif.ep_tx_araddr  = '0;
      vif.ep_tx_arlen   = '0;
      vif.ep_tx_ar_is_burst = 1'b0;
      vif.ep_tx_arid    = '0;
      vif.ep_rx_rready  = 1'b0;
      @(negedge vif.rst_i);
      @(posedge vif.clk_i);

      forever begin
        csr_seq_item req;
        seq_item_port.get_next_item(req);
        do_axi_write(req.addr, 32'(req.data));
        seq_item_port.item_done();
      end
    endtask

    // Single 16-bit write to a 16-bit address. axi_link_tx encodes as one
    // WRITE flit (header) + 1 W-beat (data).
    task automatic do_axi_write(input logic [15:0] addr, input logic [31:0] data);
      @(posedge vif.clk_i);
      #1;
      vif.ep_tx_awaddr  = addr;
      vif.ep_tx_awlen   = 8'd0;
      vif.ep_tx_awid    = 2'b0;
      vif.ep_tx_awvalid = 1'b1;
      do @(posedge vif.clk_i); while (vif.ep_tx_awready !== 1'b1);
      #1;
      vif.ep_tx_awvalid = 1'b0;

      vif.ep_tx_wdata  = data;
      vif.ep_tx_wlast  = 1'b1;
      vif.ep_tx_wvalid = 1'b1;
      do @(posedge vif.clk_i); while (vif.ep_tx_wready !== 1'b1);
      #1;
      vif.ep_tx_wvalid = 1'b0;
      `uvm_info("CSR_DRV",
        $sformatf("CSR write addr=0x%04x data=0x%08x", addr, data), UVM_HIGH)
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // mem_responder : single FSM that handles AR / AW / W from the chip
  // ---------------------------------------------------------------------------
  // Read flow: AR captured -> wait delay -> drive R beats (multi-beat for
  //            bursts via arlen + 1)
  // Write flow: AW + W captured -> dice_core_tb_record_axi_write(addr,data,strb)
  // ---------------------------------------------------------------------------
  class mem_responder extends uvm_component;
    `uvm_component_utils(mem_responder)
    virtual mini_dice_chip_vif vif;

    int unsigned response_delay_cyc = 10;
    int unsigned writes_observed = 0;

    // Optional overrides: when an entry exists for `addr`, the responder
    // returns that data instead of the DPI's default (mem[addr]=addr).
    // Use to inject random / corner-case load values without rewriting
    // the test vector JSON.
    logic [15:0] override_data [logic [15:0]];

    // Optional rresp injection: when an entry exists for `addr`, the
    // responder drives that rresp on the read response for that address.
    // 2'b10 = SLVERR, 2'b11 = DECERR. Applies to single-beat data reads.
    logic [1:0]  read_resp_err [logic [15:0]];

    // Optional rresp injection for METADATA burst reads (kind=1). Keyed
    // by the AR base address (the 16-bit addr in the FETCH_REQ flit).
    logic [1:0]  meta_resp_err [logic [15:0]];

    // Optional rresp injection for BITSTREAM burst reads (kind=2). Same
    // keying as meta_resp_err.
    logic [1:0]  bs_resp_err   [logic [15:0]];

    // Local copy of every AXI write the chip made (addr → data).
    // Tests that don't rely on DPI's expected_writes (e.g. random data)
    // compare against their own expected map here.
    logic [15:0] local_writes [logic [15:0]];

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      if (!uvm_config_db #(virtual mini_dice_chip_vif)::get(this, "", "vif", vif))
        `uvm_fatal("CFG", "mem_responder: vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      // Idle outputs
      vif.ep_rx_arready    = 1'b0;
      vif.ep_tx_rvalid     = 1'b0;
      vif.ep_tx_rdata      = '0;
      vif.ep_tx_rresp      = 2'b00;
      vif.ep_tx_rlast      = 1'b0;
      vif.ep_tx_rid        = '0;
      vif.ep_tx_r_is_burst = 1'b0;
      vif.ep_tx_rlen       = '0;
      @(negedge vif.rst_i);
      fork
        serve_reads();
        serve_writes();
      join
    endtask

    // Read state machine
    task automatic serve_reads();
      typedef enum logic [1:0] { RD_IDLE, RD_WAIT, RD_ACTIVE } rd_state_e;
      rd_state_e   state;
      logic [15:0] base_addr;
      logic [7:0]  beat_idx;
      logic [7:0]  arlen;
      logic [1:0]  kind;            // 0=axi_read16, 1=meta, 2=bitstream
      logic        is_meta_ar;      // for meta echo
      logic [12:0] aruser_meta;
      logic [1:0]  rid;
      logic        r_is_burst;
      int unsigned delay;

      state              = RD_IDLE;
      vif.ep_rx_arready  = 1'b1;
      forever begin
        @(posedge vif.clk_i);
        unique case (state)
          RD_IDLE: begin
            if (vif.ep_rx_arvalid && vif.ep_rx_arready) begin
              base_addr   = vif.ep_rx_araddr;
              arlen       = vif.ep_rx_arlen;
              beat_idx    = '0;
              rid         = vif.ep_rx_arid;
              r_is_burst  = vif.ep_rx_ar_is_burst;
              if (vif.ep_rx_ar_is_burst)
                kind = vif.ep_rx_arid[0] ? 2'd2 : 2'd1;
              else
                kind = 2'd0;
              is_meta_ar  = !vif.ep_rx_ar_is_burst;
              aruser_meta = {1'b0, vif.ep_rx_ar_tid,
                             vif.ep_rx_ar_eblock, vif.ep_rx_ar_regaddr};
              `uvm_info("MEM_RD",
                $sformatf("AR captured addr=0x%04x len=%0d kind=%0d burst=%0b id=%0d",
                          base_addr, arlen, kind, r_is_burst, rid), UVM_HIGH)
              delay = response_delay_cyc;
              vif.ep_rx_arready = 1'b0;
              vif.ep_tx_rlen    = arlen;
              vif.ep_tx_rid     = rid;
              vif.ep_tx_r_is_burst = r_is_burst;
              state = RD_WAIT;
            end
          end
          RD_WAIT: begin
            if (delay <= 1) begin
              vif.ep_tx_rdata  = pack_beat(kind, base_addr, beat_idx,
                                            is_meta_ar, aruser_meta);
              vif.ep_tx_rlast  = (arlen == 8'd0);
              // Inject SLVERR / DECERR. kind selects which map to consult.
              //   kind=0 (data load)   → read_resp_err
              //   kind=1 (meta burst)  → meta_resp_err
              //   kind=2 (bs   burst)  → bs_resp_err
              vif.ep_tx_rresp = 2'b00;
              case (kind)
                2'd0: if (read_resp_err.exists(base_addr))
                        vif.ep_tx_rresp = read_resp_err[base_addr];
                2'd1: if (meta_resp_err.exists(base_addr))
                        vif.ep_tx_rresp = meta_resp_err[base_addr];
                2'd2: if (bs_resp_err.exists(base_addr))
                        vif.ep_tx_rresp = bs_resp_err[base_addr];
              endcase
              vif.ep_tx_rvalid = 1'b1;
              state = RD_ACTIVE;
            end else begin
              delay--;
            end
          end
          RD_ACTIVE: begin
            if (vif.ep_tx_rvalid && vif.ep_tx_rready) begin
              if (vif.ep_tx_rlast) begin
                vif.ep_tx_rvalid  = 1'b0;
                vif.ep_tx_rlast   = 1'b0;
                vif.ep_rx_arready = 1'b1;
                state = RD_IDLE;
              end else begin
                beat_idx = beat_idx + 8'd1;
                vif.ep_tx_rdata = pack_beat(kind, base_addr, int'(beat_idx),
                                            is_meta_ar, aruser_meta);
                vif.ep_tx_rlast = (beat_idx == arlen);
              end
            end
          end
        endcase
      end
    endtask

    function automatic logic [31:0] pack_beat(
        input logic [1:0]  kind,
        input logic [15:0] base,
        input int unsigned beat_idx,
        input logic        is_meta,
        input logic [12:0] aruser_meta
    );
      logic [31:0] word;
      int unsigned byte_addr;
      logic [15:0] addr16;
      byte_addr = int'(base) + beat_idx * 4;
      case (kind)
        2'd1:    word = 32'(dice_core_tb_meta_read32(byte_addr));
        2'd2:    word = 32'(dice_core_tb_bitstream_read32(byte_addr));
        default: begin
          int unsigned single_addr = int'(base) + beat_idx * 2;
          addr16 = 16'(single_addr);
          if (override_data.exists(addr16))
            word = 32'(override_data[addr16]);
          else
            word = 32'(dice_core_tb_axi_read16(single_addr));
        end
      endcase
      if (is_meta) word[28:16] = aruser_meta;
      return word;
    endfunction

    // Write capture: when AW + W both seen, record via DPI
    task automatic serve_writes();
      logic [15:0] aw_addr_lat;
      logic        aw_pending;
      aw_pending = 1'b0;
      forever begin
        @(posedge vif.clk_i);
        if (vif.ep_rx_awvalid && !aw_pending) begin
          aw_addr_lat = vif.ep_rx_awaddr;
          aw_pending  = 1'b1;
        end
        if (vif.ep_rx_wvalid && aw_pending) begin
          dice_core_tb_record_axi_write(int'(aw_addr_lat),
                                         int'(vif.ep_rx_wdata[15:0]),
                                         int'(32'h3));
          local_writes[aw_addr_lat] = vif.ep_rx_wdata[15:0];
          writes_observed++;
          `uvm_info("MEM_WR",
            $sformatf("AXI write addr=0x%04x data=0x%04x (count=%0d)",
                      aw_addr_lat, vif.ep_rx_wdata[15:0], writes_observed),
            UVM_HIGH)
          aw_pending = 1'b0;
        end
      end
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // chip_scoreboard : end-of-test pass/fail based on DPI write diff
  // ---------------------------------------------------------------------------
  class chip_scoreboard extends uvm_component;
    `uvm_component_utils(chip_scoreboard)
    int unsigned final_writes_seen;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void check_done(input string ctx = "");
      int unsigned ok;
      ok = dice_core_tb_check_done();
      if (ok != 0)
        `uvm_info("SB", $sformatf("PASS%s: DPI write diff clean (%0d writes seen)",
          (ctx != "") ? $sformatf(" [%s]", ctx) : "", final_writes_seen), UVM_NONE)
      else
        `uvm_error("SB", $sformatf("FAIL%s: DPI write diff mismatch (%0d writes seen)",
          (ctx != "") ? $sformatf(" [%s]", ctx) : "", final_writes_seen))
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // csr_sequencer : the usual UVM sequencer
  // ---------------------------------------------------------------------------
  typedef uvm_sequencer #(csr_seq_item) csr_sequencer;

  // ---------------------------------------------------------------------------
  // csr_agent : driver + sequencer
  // ---------------------------------------------------------------------------
  class csr_agent extends uvm_component;
    `uvm_component_utils(csr_agent)
    csr_driver    drv;
    csr_sequencer seqr;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      drv  = csr_driver::type_id::create("drv", this);
      seqr = csr_sequencer::type_id::create("seqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // chip_env : composes the agents
  // ---------------------------------------------------------------------------
  class chip_env extends uvm_env;
    `uvm_component_utils(chip_env)
    csr_agent       csr_agnt;
    mem_responder   mem_resp;
    chip_scoreboard sb;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
      csr_agnt = csr_agent::type_id::create("csr_agnt", this);
      mem_resp = mem_responder::type_id::create("mem_resp", this);
      sb       = chip_scoreboard::type_id::create("sb", this);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // CSR-program sequence: builds the canonical launch (csrX0..7, start_pc,
  // thread_count, CTRL.start) from values cached in the test base class.
  // ---------------------------------------------------------------------------
  class csr_launch_seq extends uvm_sequence #(csr_seq_item);
    `uvm_object_utils(csr_launch_seq)
    logic [15:0] csr_values [8];
    logic [15:0] start_pc;
    logic [15:0] thread_count;

    function new(string name = "csr_launch_seq"); super.new(name); endfunction
    task body();
      csr_seq_item item;
      for (int i = 0; i < 8; i++) begin
        item = csr_seq_item::type_id::create("item");
        start_item(item);
        item.addr = REG_CSRX0 + 16'(i * 2);
        item.data = csr_values[i];
        finish_item(item);
      end
      item = csr_seq_item::type_id::create("item");
      start_item(item);
      item.addr = REG_STARTPC; item.data = start_pc;
      finish_item(item);
      item = csr_seq_item::type_id::create("item");
      start_item(item);
      item.addr = REG_THREAD_COUNT; item.data = thread_count;
      finish_item(item);
      item = csr_seq_item::type_id::create("item");
      start_item(item);
      item.addr = REG_CTRL; item.data = CTRL_START;
      finish_item(item);
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // csr_one_shot_seq: writes a single (addr, data) pair. Useful for tests that
  // want to twiddle one CSR mid-run (e.g., re-pulse CTRL.START).
  // ---------------------------------------------------------------------------
  class csr_one_shot_seq extends uvm_sequence #(csr_seq_item);
    `uvm_object_utils(csr_one_shot_seq)
    logic [15:0] addr;
    logic [15:0] data;
    function new(string name = "csr_one_shot_seq"); super.new(name); endfunction
    task body();
      csr_seq_item item;
      item = csr_seq_item::type_id::create("item");
      start_item(item);
      item.addr = addr; item.data = data;
      finish_item(item);
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // csr_read_via_link: drives a single-beat READ flit to the chip and waits
  // for the READ_RESP back on vif.ep_rx_r*. Returns the 16-bit read value.
  // Not a sequence — used directly from a test's run_phase.
  // ---------------------------------------------------------------------------
  task automatic csr_read_via_link(
      virtual mini_dice_chip_vif vif,
      input  logic [15:0]        addr,
      output logic [15:0]        data,
      input  int unsigned        timeout_cyc = 5000
  );
    int unsigned cyc;

    // Drive AR
    @(posedge vif.clk_i); #1;
    vif.ep_tx_araddr      = addr;
    vif.ep_tx_arlen       = 8'd0;
    vif.ep_tx_arid        = 2'd0;
    vif.ep_tx_ar_is_burst = 1'b0;
    vif.ep_tx_arvalid     = 1'b1;
    do @(posedge vif.clk_i); while (vif.ep_tx_arready !== 1'b1);
    #1;
    vif.ep_tx_arvalid = 1'b0;

    // Wait for R response (with timeout)
    vif.ep_rx_rready = 1'b1;
    cyc = 0;
    while (vif.ep_rx_rvalid !== 1'b1 && cyc < timeout_cyc) begin
      @(posedge vif.clk_i);
      cyc++;
    end

    if (vif.ep_rx_rvalid === 1'b1) begin
      data = vif.ep_rx_rdata[15:0];
      `uvm_info("CSR_RD",
        $sformatf("CSR read addr=0x%04x → data=0x%04x (rresp=%b, %0d cyc)",
                  addr, data, vif.ep_rx_rresp, cyc),
        UVM_HIGH)
    end else begin
      data = 16'hDEAD;
      `uvm_error("CSR_RD",
        $sformatf("CSR read timeout addr=0x%04x after %0d cyc", addr, cyc))
    end

    @(posedge vif.clk_i); #1;
    vif.ep_rx_rready = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Tests (included at end of pkg)
  // ---------------------------------------------------------------------------
  `include "tests/mini_dice_chip_base_test.sv"
  `include "tests/mini_dice_chip_full_mul_array_test.sv"
  `include "tests/mini_dice_chip_add_array_test.sv"
  `include "tests/mini_dice_chip_simple_branching_test.sv"
  `include "tests/mini_dice_chip_partial_thread_test.sv"
  `include "tests/mini_dice_chip_fetch_latency_test.sv"
  `include "tests/mini_dice_chip_axil_error_test.sv"
  `include "tests/mini_dice_chip_mul_random_data_test.sv"
  `include "tests/mini_dice_chip_sequential_cta_test.sv"
  `include "tests/mini_dice_chip_csr_smoke_test.sv"
  `include "tests/mini_dice_chip_link_backpressure_test.sv"
  `include "tests/mini_dice_chip_random_seed_test.sv"
  `include "tests/mini_dice_chip_branch_axil_error_test.sv"
  `include "tests/mini_dice_chip_random_regression_test.sv"
  `include "tests/mini_dice_chip_random_dag_test.sv"
  `include "tests/mini_dice_chip_sequential_cta_random_test.sv"
  `include "tests/mini_dice_chip_mid_reset_test.sv"
  `include "tests/mini_dice_chip_csr_readback_test.sv"
  `include "tests/mini_dice_chip_decerr_test.sv"
  `include "tests/mini_dice_chip_multi_error_test.sv"
  `include "tests/mini_dice_chip_out_of_range_test.sv"
  `include "tests/mini_dice_chip_port_contention_test.sv"
  `include "tests/mini_dice_chip_cgra_reset_test.sv"
  `include "tests/mini_dice_chip_endurance_test.sv"
  `include "tests/mini_dice_chip_oor_empirical_test.sv"
  `include "tests/mini_dice_chip_meta_error_test.sv"
  `include "tests/mini_dice_chip_bs_error_test.sv"
  `include "tests/mini_dice_chip_eblock8_test.sv"

endpackage
