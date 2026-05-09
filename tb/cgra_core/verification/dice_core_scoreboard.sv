// Scoreboard for dice_core.
// Checks every AXI-Lite transaction for OKAY response.
// Tests may call expect_store(addr, data) before cta_complete; the scoreboard
// then verifies that the DUT issues a matching write to that address.
class dice_core_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(dice_core_scoreboard)

  // Analysis FIFOs — connected from agent analysis ports in the env
  uvm_tlm_analysis_fifo #(axil_seq_item)         axil_fifo;
  uvm_tlm_analysis_fifo #(cta_seq_item)          cta_dispatch_fifo;
  uvm_tlm_analysis_fifo #(cta_seq_item)          cta_complete_fifo;
  uvm_tlm_analysis_fifo #(cgra_bitstream_item)   prog_fifo;
  uvm_tlm_analysis_fifo #(mem_seq_item)          mfetch_fifo;
  uvm_tlm_analysis_fifo #(mem_seq_item)          bsfetch_fifo;

  int unsigned txn_count       = 0;
  int unsigned error_count     = 0;
  int unsigned stores_seen     = 0;
  int unsigned stores_expected = 0;
  int unsigned bs_seen         = 0;
  int unsigned bs_expected     = 0;
  int unsigned mfetch_seen     = 0;
  int unsigned bsfetch_seen    = 0;
  int unsigned mfetch_expected = 0;
  int unsigned bsfetch_expected = 0;

  // addr → boolean; tests register the addresses they expect to be fetched.
  bit expected_mfetch_addr [logic [15:0]];
  bit expected_bsfetch_addr [logic [15:0]];

  // addr → expected write data; populated by tests via expect_store()
  logic [15:0] expected_data [logic [15:0]];

  // Addresses where tests deliberately injected an AXI error response.
  // The scoreboard logs but does not flag a non-OKAY response on these.
  bit expected_err_addr [logic [15:0]];
  int unsigned err_resp_seen = 0;

  // Queue of expected scan-chain bitstreams, in programming order.
  // Each entry is the full DICE_BITSTREAM_SIZE-bit sequence the chain should
  // shift in. Tests push to it via expect_bitstream().
  logic expected_bitstreams [$][];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Register an expected store result.  Call from run_body before cta_complete.
  function void expect_store(logic [15:0] addr, logic [15:0] data);
    expected_data[addr] = data;
    stores_expected++;
  endfunction

  // Register an address that the test has deliberately configured to return
  // a non-OKAY AXI response. The scoreboard counts but does not error on it.
  function void expect_axil_error(logic [15:0] addr);
    expected_err_addr[addr] = 1'b1;
  endfunction

  // Register a metadata-fetch address the test expects to see on the bus.
  function void expect_mfetch(logic [15:0] addr);
    expected_mfetch_addr[addr] = 1'b1;
    mfetch_expected++;
  endfunction

  // Register a bitstream-fetch address the test expects to see on the bus.
  function void expect_bsfetch(logic [15:0] addr);
    expected_bsfetch_addr[addr] = 1'b1;
    bsfetch_expected++;
  endfunction

  // Register an expected programming epoch from a 16-bit-word bitstream image.
  // The scan chain shifts LSB-first within each word, words in order, taking
  // the first DICE_BITSTREAM_SIZE bits — the rest of the image is padding.
  function void expect_bitstream(logic [15:0] words []);
    logic bits [];
    int unsigned w, b;
    bits = new[DICE_BITSTREAM_SIZE];
    for (int unsigned i = 0; i < DICE_BITSTREAM_SIZE; i++) begin
      w = i / 16;
      b = i % 16;
      if (w >= words.size()) begin
        `uvm_fatal("SB", $sformatf(
          "expect_bitstream: words[] too short (size=%0d, need >= %0d)",
          words.size(), (DICE_BITSTREAM_SIZE + 15)/16))
      end
      bits[i] = words[w][b];
    end
    expected_bitstreams.push_back(bits);
    bs_expected++;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axil_fifo          = new("axil_fifo",          this);
    cta_dispatch_fifo  = new("cta_dispatch_fifo",  this);
    cta_complete_fifo  = new("cta_complete_fifo",  this);
    prog_fifo          = new("prog_fifo",          this);
    mfetch_fifo        = new("mfetch_fifo",        this);
    bsfetch_fifo       = new("bsfetch_fifo",       this);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      check_axil_txns();
      track_cta_completions();
      check_bitstreams();
      check_mfetch();
      check_bsfetch();
    join
  endtask

  task check_axil_txns();
    axil_seq_item item;
    forever begin
      axil_fifo.get(item);
      txn_count++;
      if (item.resp !== 2'b00) begin
        if (expected_err_addr.exists(item.addr)) begin
          err_resp_seen++;
          `uvm_info("SB", $sformatf(
            "Expected non-OKAY AXI-Lite response (addr=0x%04x resp=%0b): tolerated",
            item.addr, item.resp), UVM_LOW)
        end else begin
          `uvm_error("SB", $sformatf("Non-OKAY AXI-Lite response: %s", item.convert2string()))
          error_count++;
        end
      end else if (item.txn_type == axil_seq_item::WRITE) begin
        `uvm_info("SB", $sformatf("Store: %s", item.convert2string()), UVM_LOW)
        if (expected_data.exists(item.addr)) begin
          stores_seen++;
          if (item.data !== expected_data[item.addr]) begin
            `uvm_error("SB", $sformatf(
              "Store mismatch at 0x%04x: got 0x%04x, expected 0x%04x",
              item.addr, item.data, expected_data[item.addr]))
            error_count++;
          end else begin
            `uvm_info("SB", $sformatf("Store match at 0x%04x: 0x%04x", item.addr, item.data), UVM_NONE)
          end
        end
      end else begin
        `uvm_info("SB", $sformatf("OK: %s", item.convert2string()), UVM_HIGH)
      end
    end
  endtask

  task track_cta_completions();
    cta_seq_item item;
    forever begin
      cta_complete_fifo.get(item);
      `uvm_info("SB", "CTA completed", UVM_MEDIUM)
    end
  endtask

  task check_bitstreams();
    cgra_bitstream_item item;
    logic exp [];
    int unsigned mismatch_bits;
    forever begin
      prog_fifo.get(item);
      bs_seen++;
      if (item.bit_count !== DICE_BITSTREAM_SIZE) begin
        `uvm_error("SB", $sformatf(
          "Bitstream epoch %0d: bit_count=%0d, expected %0d",
          bs_seen, item.bit_count, DICE_BITSTREAM_SIZE))
        error_count++;
      end
      if (expected_bitstreams.size() == 0) begin
        `uvm_info("SB", $sformatf(
          "Bitstream epoch %0d observed (no expectation registered)", bs_seen),
          UVM_LOW)
        continue;
      end
      exp = expected_bitstreams.pop_front();
      mismatch_bits = 0;
      for (int unsigned i = 0; i < DICE_BITSTREAM_SIZE; i++) begin
        if (item.bits[i] !== exp[i]) mismatch_bits++;
      end
      if (mismatch_bits != 0) begin
        `uvm_error("SB", $sformatf(
          "Bitstream epoch %0d mismatch: %0d/%0d bits differ",
          bs_seen, mismatch_bits, DICE_BITSTREAM_SIZE))
        error_count++;
      end else begin
        `uvm_info("SB",
          $sformatf("Bitstream epoch %0d match (%0d bits)", bs_seen, DICE_BITSTREAM_SIZE),
          UVM_LOW)
      end
    end
  endtask

  task check_mfetch();
    mem_seq_item item;
    forever begin
      mfetch_fifo.get(item);
      mfetch_seen++;
      `uvm_info("SB", $sformatf("mfetch AR observed: addr=0x%04x len=%0d",
                item.addr, item.len), UVM_LOW)
      if (expected_mfetch_addr.size() > 0
          && !expected_mfetch_addr.exists(item.addr)) begin
        `uvm_error("SB", $sformatf(
          "Unexpected mfetch address: 0x%04x (not in expected set)", item.addr))
        error_count++;
      end
    end
  endtask

  task check_bsfetch();
    mem_seq_item item;
    forever begin
      bsfetch_fifo.get(item);
      bsfetch_seen++;
      `uvm_info("SB", $sformatf("bsfetch AR observed: addr=0x%04x len=%0d",
                item.addr, item.len), UVM_LOW)
      if (expected_bsfetch_addr.size() > 0
          && !expected_bsfetch_addr.exists(item.addr)) begin
        `uvm_error("SB", $sformatf(
          "Unexpected bsfetch address: 0x%04x (not in expected set)", item.addr))
        error_count++;
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    if (stores_expected > 0 && stores_seen < stores_expected) begin
      `uvm_error("SB", $sformatf("Missing stores: expected %0d, saw %0d",
                 stores_expected, stores_seen))
      error_count++;
    end
    if (bs_expected > 0 && bs_seen < bs_expected) begin
      `uvm_error("SB", $sformatf("Missing bitstreams: expected %0d, saw %0d",
                 bs_expected, bs_seen))
      error_count++;
    end
    if (mfetch_expected > 0 && mfetch_seen < mfetch_expected) begin
      `uvm_error("SB", $sformatf("Missing mfetch ARs: expected %0d, saw %0d",
                 mfetch_expected, mfetch_seen))
      error_count++;
    end
    if (bsfetch_expected > 0 && bsfetch_seen < bsfetch_expected) begin
      `uvm_error("SB", $sformatf("Missing bsfetch ARs: expected %0d, saw %0d",
                 bsfetch_expected, bsfetch_seen))
      error_count++;
    end
    `uvm_info("SB", $sformatf(
      "Scoreboard: %0d txns, %0d stores, %0d bitstreams, %0d mfetch ARs, %0d bsfetch ARs, %0d errors",
      txn_count, stores_seen, bs_seen, mfetch_seen, bsfetch_seen, error_count), UVM_NONE)
    if (error_count > 0)
      `uvm_error("SB", "TEST FAILED: errors detected")
    else
      `uvm_info("SB", "TEST PASSED", UVM_NONE)
  endfunction

endclass
