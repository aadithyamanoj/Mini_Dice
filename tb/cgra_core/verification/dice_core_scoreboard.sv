// Scoreboard for dice_core.
// Currently checks that every AXI-Lite transaction completes with OKAY response.
// Extend check_write / check_read for deeper correctness checks.
class dice_core_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(dice_core_scoreboard)

  // Analysis FIFOs — connected from agent analysis ports in the env
  uvm_tlm_analysis_fifo #(axil_seq_item) axil_fifo;
  uvm_tlm_analysis_fifo #(cta_seq_item)  cta_dispatch_fifo;
  uvm_tlm_analysis_fifo #(cta_seq_item)  cta_complete_fifo;

  int unsigned txn_count    = 0;
  int unsigned error_count  = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axil_fifo          = new("axil_fifo",          this);
    cta_dispatch_fifo  = new("cta_dispatch_fifo",  this);
    cta_complete_fifo  = new("cta_complete_fifo",  this);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      check_axil_txns();
      track_cta_completions();
    join
  endtask

  task check_axil_txns();
    axil_seq_item item;
    forever begin
      axil_fifo.get(item);
      txn_count++;
      if (item.resp !== 2'b00) begin
        `uvm_error("SB", $sformatf("Non-OKAY AXI-Lite response: %s", item.convert2string()))
        error_count++;
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

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("Scoreboard: %0d transactions checked, %0d errors",
              txn_count, error_count), UVM_NONE)
    if (error_count > 0)
      `uvm_error("SB", "TEST FAILED: errors detected")
    else
      `uvm_info("SB", "TEST PASSED", UVM_NONE)
  endfunction

endclass
