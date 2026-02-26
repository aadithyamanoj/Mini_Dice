// `timescale 1ns/1ps

`include "DE_pkg.sv"
`include "dice_pkg.sv"
`include "bsg_defines.sv"   // for bsg_fifo_tracker inside DUT

import DE_pkg::*;
import dice_pkg::*;

module reg_wr_buffer_tb;
  // dump to fsdb for verdi
  initial begin
    $fsdbDumpfile("reg_wr_buffer_tb.fsdb");
    $fsdbDumpvars(0, "+all");
  end

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int WIDTH      = 32;
  localparam int ADDR_WIDTH = $clog2(512);
  localparam int DEPTH      = 8;

  // ---------------------------------------------------------------------------
  // DUT interface signals
  // ---------------------------------------------------------------------------
  logic        clk;
  logic        reset;

  reg_wr_cmd   wr_i;
  reg_rd_cmd   fw_req_i;
  logic        pop_i;
  logic        valid_i;

  logic                    full_o;
  logic                    empty_o;
  logic [ADDR_WIDTH-1:0]   wb_tid_o;
  logic [WIDTH-1:0]        wb_data_o;
  logic                    wb_valid_o;

  logic [DEPTH-1:0]        fw_hit_o;
  logic [WIDTH-1:0]        fw_data_o;
  logic                    fw_data_valid_o;

  // ---------------------------------------------------------------------------
  // DUT instance
  // ---------------------------------------------------------------------------
  reg_wr_buffer #(
      .WIDTH     (WIDTH)
    , .ADDR_WIDTH(ADDR_WIDTH)
    , .DEPTH     (DEPTH)
  ) dut (
      .clk_i            (clk)
    , .reset_i          (reset)

    , .wr_i             (wr_i)
    , .fw_req_i         (fw_req_i)
    , .pop_i            (pop_i)
    , .valid_i          (valid_i)

    , .full_o           (full_o)
    , .empty_o          (empty_o)

    , .wb_tid_o        (wb_tid_o)
    , .wb_data_o        (wb_data_o)
    , .wb_valid_o       (wb_valid_o)
    , .wb_ws_o          (wb_ws_o)

    , .fw_hit_o         (fw_hit_o)
    , .fw_data_o        (fw_data_o)
    , .fw_data_valid_o  (fw_data_valid_o)
  );

  // ---------------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;  // 100 MHz

  task automatic apply_reset();
    begin
      reset      = 1'b1;
      wr_i       = '0;
      fw_req_i   = '0;
      pop_i      = 1'b0;
      valid_i    = '0;
      @(posedge clk);
      @(posedge clk);
      reset      = 1'b0;
      @(posedge clk);
      @(posedge clk);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Helper tasks
  // ---------------------------------------------------------------------------

  // Single-cycle write command (if we==1, DUT will enq if not full)
  task automatic do_write(
      input logic we,
      input logic [DICE_TID_WIDTH-1:0]  tid,
      input logic [WIDTH-1:0]                   data
  );
    begin
      // $display("WRITING!!");
      wr_i.we   = we;
      wr_i.tid  = tid;
      wr_i.ws   = '0;              // not used in DUT right now
      wr_i.data = data;

      valid_i = 1'b1;
      @(posedge clk);
      valid_i = '0;
      // @(posedge clk);
    end
  endtask

  // Assert pop for one cycle
  task automatic do_pop();
    begin
      pop_i = 1'b1;
      @(posedge clk);
      pop_i = 1'b0;
    end
  endtask

  // Single-cycle forwarding request
  task automatic do_forward_req(
      input  logic [DICE_TID_WIDTH-1:0] tid,
      input  logic re
  );
    begin
      fw_req_i.tid = tid;
      fw_req_i.rs  = '0;  // not used in DUT compare
      fw_req_i.re  = re;
      @(posedge clk);
      // Leave re as-is; caller can deassert if they want
    end
  endtask


  // super basic test 

  task automatic test_super_simple(); 
    logic [WIDTH-1:0] expected_data [0:2];
    begin
      $display("[TB] Test 0: basic enqueue");

      expected_data[0] = 32'hDEAD0001;
      expected_data[1] = 32'hDEAD0002;
      expected_data[2] = 32'hDEAD0003;

      // Enqueue 3 entries with tids 0,1,2
      do_write(1'b1, '0, expected_data[0]);
      //  @(posedge clk);
      do_write(1'b1, '1, expected_data[1]);
      do_write(1'b1, 'd2, expected_data[2]);

      @(posedge clk);

    end
  endtask

  // ---------------------------------------------------------------------------
  // Test 1: Basic enqueue / dequeue order + empty/full
  // ---------------------------------------------------------------------------
  task automatic test_basic_enq_deq();
    logic [WIDTH-1:0] expected_data [0:2];
    begin
      $display("[TB] Test 1: basic enqueue/dequeue");

      expected_data[0] = 32'hDEAD0001;
      expected_data[1] = 32'hDEAD0002;
      expected_data[2] = 32'hDEAD0003;

      // After reset, should be empty and not full
      assert(empty_o === 1'b1) else $fatal("Time:%0t [T1] empty_o not 1 after reset", $time);
      assert(full_o  === 1'b0) else $fatal("[T1] full_o  not 0 after reset");

      // Enqueue 3 entries with tids 0,1,2
      do_write(1'b1, '0, expected_data[0]);
      do_write(1'b1, '1, expected_data[1]);
      do_write(1'b1, 'd2, expected_data[2]);

      // Should not be empty now
      assert(empty_o === 1'b0) else $fatal("[T1] empty_o still 1 after writes");

      // Check writeback order: oldest first
      // wb_* reflect oldest entry at rptr_r (before pop)
      // So we check after each pop on the following cycle.
      for (int i = 0; i < 3; i++) begin
        // wb_* should show current oldest before pop
        assert(wb_valid_o === 1'b1) else $fatal("[T1] wb_valid_o low before pop %0d", i);
        assert(wb_data_o  === expected_data[i])
          else $fatal("[T1] wb_data_o mismatch before pop %0d: got %h, exp %h",
                      i, wb_data_o, expected_data[i]);
        // Pop it
        do_pop();
        @(posedge clk);  // wait one cycle for fifo_tracker/buffer to update
      end

      // After popping all, buffer should be empty
      assert(empty_o === 1'b1) else $fatal("[T1] empty_o not 1 after pops");
      $display("[TB] Test 1 PASSED");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test 2: Full flag / stall behavior
  // ---------------------------------------------------------------------------
  task automatic test_full_flag();
    begin
      $display("[TB] Test 2: full / stall behavior");

      // First, completely fill the buffer
      for (int i = 0; i < DEPTH; i++) begin
        do_write(1'b1, i[DICE_TID_WIDTH-1:0], 32'h1000_0000 + i);
      end

      // Give it one extra cycle to settle
      @(posedge clk);

      // Should be full, not empty
      assert(full_o  === 1'b1) else $fatal("[T2] full_o not asserted at depth %0d", DEPTH);
      assert(empty_o === 1'b0) else $fatal("[T2] empty_o asserted while full");

      // Try to "write" one more entry with a unique data pattern
      do_write(1'b1, '0, 32'hCAFE_BABE);
      @(posedge clk);

      // Because enq_li = wr_i.we & ~full, this write must be ignored.
      // One way to check this: pop all entries and ensure the extra data never appears.
      for (int i = 0; i < DEPTH; i++) begin
        assert(wb_valid_o === 1'b1) else $fatal("[T2] wb_valid_o low while draining");
        assert(wb_data_o != 32'hCAFE_BABE)
          else $fatal("[T2] overflow write corrupted buffer (saw CAFE_BABE)");
        do_pop();
        @(posedge clk);
      end

      // Now should be empty again
      assert(empty_o === 1'b1) else $fatal("[T2] empty_o not 1 after draining");
      assert(full_o  === 1'b0) else $fatal("[T2] full_o not 0 after draining");

      $display("[TB] Test 2 PASSED");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test 3: Forwarding chooses youngest matching entry
  // ---------------------------------------------------------------------------
  task automatic test_forward_youngest();
    logic [WIDTH-1:0] d0, d1, d2;
    begin
      $display("[TB] Test 3: forwarding youngest-match priority");

      d0 = 32'hAAAA_0001;
      d1 = 32'hAAAA_0002;
      d2 = 32'hAAAA_0003;

      // Fill buffer with some noise + repeated tid=3
      // 0: tid=1, noise
      do_write(1'b1, 1, 32'h1111_1111);
      // 1: tid=3, old
      do_write(1'b1, 3, d0);
      // 2: tid=2, noise
      do_write(1'b1, 2, 32'h2222_2222);
      // 3: tid=3, middle
      do_write(1'b1, 3, d1);
      // 4: tid=4, noise
      do_write(1'b1, 4, 32'h4444_4444);
      // 5: tid=3, youngest
      do_write(1'b1, 3, d2);

      @(posedge clk);

      // Issue forwarding request for tid=3
      do_forward_req(3, 1'b1);
      @(posedge clk); // Wait for combinational logic to settle with re=1

      // Must pick youngest (d2)
      assert(fw_data_valid_o === 1'b1)
        else $fatal("[T3] fw_data_valid_o not asserted for matching tid");
      assert(fw_data_o === d2)
        else $fatal("[T3] forwarding picked wrong version: got %h, expected %h", fw_data_o, d2);

      // Also sanity check fw_hit_o has at least one bit
      assert(|fw_hit_o)
        else $fatal("[T3] fw_hit_o has no bits set for matching tid");

      // Now pop one entry (tid=1) and re-check: still youngest is tid=3@index 5
      do_pop();
      @(posedge clk);
      do_forward_req(3, 1'b1);
      @(posedge clk);
      assert(fw_data_valid_o === 1'b1)
        else $fatal("[T3] fw_data_valid_o deasserted after pop");
      assert(fw_data_o === d2)
        else $fatal("[T3] forwarding changed to non-youngest after pop");

      $display("[TB] Test 3 PASSED");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Top-level stimulus
  // ---------------------------------------------------------------------------
  initial begin
    $display("=== reg_wr_buffer_tb start ===");
    apply_reset();

    //test_super_simple();
    test_basic_enq_deq();
    test_full_flag();
    // test_forward_youngest();


    
  
    $display("=== reg_wr_buffer_tb ALL TESTS PASSED ===");
    $finish;
  end

  // always_ff @(posedge clk) begin // monitor
  //     $display("------------------------------------------------------------");
  //     $display("T[%0t]", $time);
  //     // for(int i = 0; i<8; i++) begin
        
  //     //   $display("buf[%0d]: we=%0b tid=%0d addr=%0h data=%0h",
  //     //    i,
  //     //    dut.buffer[i].valid,
  //     //    dut.buffer[i].tid,
  //     //    dut.buffer[i].ws,
  //     //    dut.buffer[i].data);
  //     // end

  //     // $display("enq_li: %0b", dut.enq_li);
  //     // $display("full: %0b", dut.full);
  //     // $display("valid_i: %0b", dut.valid_i);
  //     // $display("enq_r: %0b", dut.enq_r);
  //     $display("empty: %0b", dut.empty);
      
  //     $display("------------------------------------------------------------");
  // end

endmodule
