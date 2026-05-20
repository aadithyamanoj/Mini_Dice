// mini_dice_chip_mul_random_data_test
// ------------------------------------
// Runs full_mul_array with randomized A and B operand values. Reuses the
// canonical metadata/bitstream .mem files; overrides the load data via
// mem_responder.override_data and builds a local expected-store map of
// (A * B) mod 2^16 per (tid, lane) to compare against observed writes.
//
// CSR layout (from full_mul_array_test_vector.json):
//   csrX0=0x0001 (A base), csrX1=0x0080 (B base), csrX2=0x0100 (C base),
//   csrX3=0x0004 (stride), csrX4..7={0,1,2,3} (lane offsets).
// Address map: A=0x01..0x40, B=0x80..0xBF, C=0x100..0x13F.
//
// Run (fast): cd tb/mini_dice/verification && ./simv +UVM_TESTNAME=mini_dice_chip_mul_random_data_test +ntb_random_seed=42
// Run (chip): cd tb/mini_dice/verification && ../simv_chip +UVM_TESTNAME=mini_dice_chip_mul_random_data_test +ntb_random_seed=42

class mini_dice_chip_mul_random_data_test extends mini_dice_chip_full_mul_array_test;
  `uvm_component_utils(mini_dice_chip_mul_random_data_test)

  // addr → expected store value (A * B mod 2^16).
  logic [15:0] expected_data [logic [15:0]];

  function new(string name = "mini_dice_chip_mul_random_data_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void install_random_inputs();
    logic [15:0] a_addr, b_addr, c_addr;
    logic [15:0] a_val,  b_val,  expected;
    int unsigned t, k;
    for (t = 0; t < 16; t++) begin
      for (k = 0; k < 4; k++) begin
        a_addr = 16'(1   + 4*t + k);
        b_addr = 16'(128 + 4*t + k);
        c_addr = 16'(256 + 4*t + k);
        a_val  = 16'($urandom() & 16'hFFFF);
        b_val  = 16'($urandom() & 16'hFFFF);
        env.mem_resp.override_data[a_addr] = a_val;
        env.mem_resp.override_data[b_addr] = b_val;
        expected = a_val * b_val;  // truncates to 16 bits
        expected_data[c_addr] = expected;
      end
    end
    `uvm_info("RAND_DATA",
      $sformatf("Installed %0d random A/B values + %0d expected stores",
                env.mem_resp.override_data.size(), expected_data.size()),
      UVM_LOW)
  endfunction

  function void compare_results();
    int unsigned n_match  = 0;
    int unsigned misses   = 0;
    int unsigned extras   = 0;
    int unsigned mismatch = 0;
    logic [15:0] addr;

    foreach (expected_data[addr]) begin
      if (!env.mem_resp.local_writes.exists(addr)) begin
        misses++;
        `uvm_error("RAND_DATA",
          $sformatf("MISSING write at 0x%04x (expected 0x%04x)",
                    addr, expected_data[addr]))
      end else if (env.mem_resp.local_writes[addr] !== expected_data[addr]) begin
        mismatch++;
        `uvm_error("RAND_DATA",
          $sformatf("MISMATCH at 0x%04x: got 0x%04x, expected 0x%04x",
                    addr, env.mem_resp.local_writes[addr], expected_data[addr]))
      end else begin
        n_match++;
      end
    end
    foreach (env.mem_resp.local_writes[addr]) begin
      if (!expected_data.exists(addr)) begin
        extras++;
        `uvm_error("RAND_DATA",
          $sformatf("UNEXPECTED write at 0x%04x = 0x%04x",
                    addr, env.mem_resp.local_writes[addr]))
      end
    end

    if (n_match == expected_data.size() && misses == 0 && extras == 0 && mismatch == 0)
      `uvm_info("RAND_DATA",
        $sformatf("PASS: %0d/%0d random A*B stores match",
                  n_match, expected_data.size()), UVM_NONE)
    else
      `uvm_error("RAND_DATA",
        $sformatf("FAIL: n_match=%0d miss=%0d mismatch=%0d extra=%0d",
                  n_match, misses, mismatch, extras))
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned cyc;
    phase.raise_objection(this);

    load_collateral();
    // Install override_data BEFORE launch so loads see the random values.
    install_random_inputs();
    program_and_launch();

    for (cyc = 0; cyc < SETTLE_CYCLES; cyc++) begin
      @(posedge env.csr_agnt.drv.vif.clk_i);
      if (env.mem_resp.writes_observed >= 64) break;
    end
    repeat (200) @(posedge env.csr_agnt.drv.vif.clk_i);

    compare_results();
    #100;
    phase.drop_objection(this);
  endtask
endclass
