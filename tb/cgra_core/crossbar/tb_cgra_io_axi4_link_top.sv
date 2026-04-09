// =============================================================================
// tb_cgra_io_axi4_link_top.sv
//
// Testbench for the off-chip memory link path through cgra_io_axi4_top.
//
// Path under test:
//   mem_req_fifo (enq_*) → dfetch → crossbar → axi_link_tx → mem_link_tx
//   mem_link_rx → axi_link_rx → ID shim → crossbar → mem_req_fifo (rsp_*)
//
// The TB acts as the FPGA SRAM endpoint:
//   - Receives flit packets on mem_link_tx (READ_REQ / WRITE_REQ)
//   - Looks up / writes a local 16-bit memory model
//   - Sends flit-encoded responses on mem_link_rx (READ_RESP / WRITE_RESP)
//
// Flit protocol (axi_link_tx / axi_link_rx):
//   READ_REQ   : {3'b001, beats[12:0]}  + addr_flit
//   WRITE_REQ  : {3'b000, beats[12:0]}  + addr_flit + beats×data_flits
//   READ_RESP  : {3'b010, beats[12:0]}  + beats×data_flits + rresp_flit
//   WRITE_RESP : {3'b011, 13'd1}        + bresp_flit
//
// Test plan:
//   T1 : Single load  — enqueue AR, receive READ_REQ flit, respond READ_RESP,
//                        check rsp_data_o and rsp_tid_bitmap_o
//   T2 : Single store — enqueue AW+W, receive WRITE_REQ flit, respond
//                        WRITE_RESP (no rsp_valid expected)
//   T3 : Back-to-back — 4 consecutive loads, each response verified
// =============================================================================

`timescale 1ns/1ps

`include "dice_define.vh"

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module tb_cgra_io_axi4_link_top;

  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;

  // -------------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------------
  localparam int AW           = 16;
  localparam int DW           = 16;
  localparam int FW           = 16;
  localparam int CLK_HALF_NS  = 5;    // 100 MHz

  localparam logic [AW-1:0] MEM_BASE = 16'h0800;
  localparam int             MEM_WORDS = 1024;

  // Flit opcodes (must match axi_link_tx/rx)
  localparam logic [2:0] OP_WRITE_REQ  = 3'b000;
  localparam logic [2:0] OP_READ_REQ   = 3'b001;
  localparam logic [2:0] OP_READ_RESP  = 3'b010;
  localparam logic [2:0] OP_WRITE_RESP = 3'b011;

  // -------------------------------------------------------------------------
  // Clock / reset
  // -------------------------------------------------------------------------
  bit   clk_i;
  logic rst_i = 1'b1;
  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

  // -------------------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------------------

  // FPGA AXI-Lite flat pins (fpga_mst port — tied off in this TB)
  logic [AW-1:0] fpga_aw_addr  = '0;
  logic [2:0]    fpga_aw_prot  = '0;
  logic          fpga_aw_valid = '0;
  logic          fpga_aw_ready;
  logic [DW-1:0] fpga_w_data   = '0;
  logic [1:0]    fpga_w_strb   = '0;
  logic          fpga_w_valid  = '0;
  logic          fpga_w_ready;
  logic [1:0]    fpga_b_resp;
  logic          fpga_b_valid;
  logic          fpga_b_ready  = 1'b1;
  logic [AW-1:0] fpga_ar_addr  = '0;
  logic [2:0]    fpga_ar_prot  = '0;
  logic          fpga_ar_valid = '0;
  logic          fpga_ar_ready;
  logic [DW-1:0] fpga_r_data;
  logic [1:0]    fpga_r_resp;
  logic          fpga_r_valid;
  logic          fpga_r_ready  = 1'b1;

  // mem_req_fifo enqueue interface
  logic                                                              enq_valid;
  logic                                                              enq_ready;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                enq_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                      enq_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                   enq_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] enq_address_map;
  logic [15:0]                                                       enq_addr;
  logic [15:0]                                                       enq_data;
  logic                                                              enq_write_en;

  // mem_req_fifo response interface
  logic                                                              rsp_valid;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                      rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                   rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                   rsp_data;

  // Off-chip memory link (chip → FPGA)
  logic          mem_tx_v;
  logic [FW-1:0] mem_tx_data;
  logic          mem_tx_ready;

  // Off-chip memory link (FPGA → chip)
  logic          mem_rx_v;
  logic [FW-1:0] mem_rx_data;
  logic          mem_rx_ready;

  // CSR slave (tied off — not under test here)
  mst_req_t  csr_req;
  mst_resp_t csr_resp;
  assign csr_resp = '0;

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  cgra_io_axi4_top #(
    .ADDR_WIDTH ( AW ),
    .DATA_WIDTH ( DW ),
    .FLIT_WIDTH ( FW )
  ) dut (
    .clk_i                   ( clk_i          ),
    .rst_i                   ( rst_i          ),

    .fpga_axi_i_aw_addr      ( fpga_aw_addr   ),
    .fpga_axi_i_aw_prot      ( fpga_aw_prot   ),
    .fpga_axi_i_aw_valid     ( fpga_aw_valid  ),
    .fpga_axi_i_aw_ready     ( fpga_aw_ready  ),
    .fpga_axi_i_w_data       ( fpga_w_data    ),
    .fpga_axi_i_w_strb       ( fpga_w_strb    ),
    .fpga_axi_i_w_valid      ( fpga_w_valid   ),
    .fpga_axi_i_w_ready      ( fpga_w_ready   ),
    .fpga_axi_i_b_resp       ( fpga_b_resp    ),
    .fpga_axi_i_b_valid      ( fpga_b_valid   ),
    .fpga_axi_i_b_ready      ( fpga_b_ready   ),
    .fpga_axi_i_ar_addr      ( fpga_ar_addr   ),
    .fpga_axi_i_ar_prot      ( fpga_ar_prot   ),
    .fpga_axi_i_ar_valid     ( fpga_ar_valid  ),
    .fpga_axi_i_ar_ready     ( fpga_ar_ready  ),
    .fpga_axi_i_r_data       ( fpga_r_data    ),
    .fpga_axi_i_r_resp       ( fpga_r_resp    ),
    .fpga_axi_i_r_valid      ( fpga_r_valid   ),
    .fpga_axi_i_r_ready      ( fpga_r_ready   ),

    .enq_valid_i             ( enq_valid       ),
    .enq_ready_o             ( enq_ready       ),
    .enq_base_tid_i          ( enq_base_tid    ),
    .enq_tid_bitmap_i        ( enq_tid_bitmap  ),
    .enq_ld_dest_reg_i       ( enq_ld_dest_reg ),
    .enq_address_map_i       ( enq_address_map ),
    .enq_addr_i              ( enq_addr        ),
    .enq_data_i              ( enq_data        ),
    .enq_write_en_i          ( enq_write_en    ),

    .rsp_valid_o             ( rsp_valid       ),
    .rsp_base_tid_o          ( rsp_base_tid    ),
    .rsp_tid_bitmap_o        ( rsp_tid_bitmap  ),
    .rsp_ld_dest_reg_o       ( rsp_ld_dest_reg ),
    .rsp_address_map_o       ( rsp_address_map ),
    .rsp_data_o              ( rsp_data        ),

    .mem_link_tx_v_o         ( mem_tx_v        ),
    .mem_link_tx_data_o      ( mem_tx_data     ),
    .mem_link_tx_ready_i     ( mem_tx_ready    ),

    .mem_link_rx_v_i         ( mem_rx_v        ),
    .mem_link_rx_data_i      ( mem_rx_data     ),
    .mem_link_rx_ready_o     ( mem_rx_ready    ),

    .cgra_csr_req_o          ( csr_req         ),
    .cgra_csr_resp_i         ( csr_resp        )
  );

  // =========================================================================
  // TB FPGA memory model
  // =========================================================================
  logic [15:0] fpga_sram [0:MEM_WORDS-1];

  initial foreach (fpga_sram[i]) fpga_sram[i] = 16'(i + 16'hA000);

  // =========================================================================
  // Scoreboard
  // =========================================================================
  int pass_cnt, fail_cnt;

  task automatic check16(
    input logic [15:0] actual,
    input logic [15:0] expected,
    input string       msg
  );
    if (actual !== expected) begin
      $error("[FAIL] %s — Exp:0x%04h  Got:0x%04h", msg, expected, actual);
      fail_cnt++;
    end else begin
      $display("[PASS] %s", msg);
      pass_cnt++;
    end
  endtask

  // =========================================================================
  // Link helpers
  // =========================================================================

  // Send one flit on mem_link_rx (TB → DUT)
  task automatic send_rx_flit(input logic [FW-1:0] flit);
    @(posedge clk_i); #1;
    mem_rx_v    = 1'b1;
    mem_rx_data = flit;
    // mem_rx_ready (yumi) goes high when DUT consumed it
    @(posedge clk_i);
    while (!mem_rx_ready) @(posedge clk_i);
    #1;
    mem_rx_v    = 1'b0;
    mem_rx_data = '0;
  endtask

  // Receive one flit from mem_link_tx (DUT → TB)
  task automatic recv_tx_flit(output logic [FW-1:0] flit);
    mem_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!mem_tx_v) @(posedge clk_i);
    flit = mem_tx_data;
    @(posedge clk_i); #1;
    mem_tx_ready = 1'b0;
  endtask

  // =========================================================================
  // FPGA endpoint: receive request, service it, send response
  // Runs in a background always block
  // =========================================================================
  logic [2:0]  rx_opcode;
  logic [12:0] rx_beats;
  logic [15:0] rx_addr;
  logic [FW-1:0] flit_buf;

  always begin
    // Wait for a flit from DUT
    mem_tx_ready = 1'b0;
    @(posedge clk_i);
    while (!mem_tx_v) @(posedge clk_i);

    // Capture header
    mem_tx_ready = 1'b1;
    flit_buf     = mem_tx_data;
    @(posedge clk_i); #1;
    mem_tx_ready = 1'b0;

    rx_opcode = flit_buf[15:13];
    rx_beats  = flit_buf[12:0];

    case (rx_opcode)

      OP_READ_REQ: begin
        // Next flit = address
        recv_tx_flit(flit_buf);
        rx_addr = flit_buf;
        // Send READ_RESP: header + rx_beats data flits + rresp flit
        send_rx_flit({OP_READ_RESP, rx_beats});
        for (int b = 0; b < int'(rx_beats); b++) begin
          automatic int idx = int'((rx_addr - MEM_BASE) >> 1) + b;
          send_rx_flit((idx >= 0 && idx < MEM_WORDS) ? fpga_sram[idx] : 16'hDEAD);
        end
        send_rx_flit(16'h0000); // RRESP = OKAY
      end

      OP_WRITE_REQ: begin
        // Next flit = address, then rx_beats data flits
        recv_tx_flit(flit_buf);
        rx_addr = flit_buf;
        for (int b = 0; b < int'(rx_beats); b++) begin
          automatic int idx = int'((rx_addr - MEM_BASE) >> 1) + b;
          recv_tx_flit(flit_buf);
          if (idx >= 0 && idx < MEM_WORDS)
            fpga_sram[idx] = flit_buf;
        end
        // Send WRITE_RESP
        send_rx_flit({OP_WRITE_RESP, 13'd1});
        send_rx_flit(16'h0000); // BRESP = OKAY
      end

      default: begin
        $error("TB FPGA endpoint: unexpected opcode 0x%0x", rx_opcode);
      end

    endcase
  end

  // =========================================================================
  // Stimulus helpers
  // =========================================================================

  // Enqueue a load request and wait for FIFO accept
  task automatic cgra_load(
    input logic [15:0]             addr,
    input logic [TID_BITMAP_WIDTH-1:0] bitmap
  );
    @(posedge clk_i); #1;
    enq_valid      = 1'b1;
    enq_addr       = addr;
    enq_data       = '0;
    enq_write_en   = 1'b0;
    enq_tid_bitmap = bitmap;
    enq_base_tid   = '0;
    enq_ld_dest_reg = '0;
    enq_address_map = '0;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid = 1'b0;
  endtask

  // Enqueue a store request and wait for FIFO accept
  task automatic cgra_store(
    input logic [15:0] addr,
    input logic [15:0] data,
    input logic [TID_BITMAP_WIDTH-1:0] bitmap
  );
    @(posedge clk_i); #1;
    enq_valid      = 1'b1;
    enq_addr       = addr;
    enq_data       = data;
    enq_write_en   = 1'b1;
    enq_tid_bitmap = bitmap;
    enq_base_tid   = '0;
    enq_ld_dest_reg = '0;
    enq_address_map = '0;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid = 1'b0;
  endtask

  // Wait for rsp_valid and return rsp_data[15:0]
  task automatic wait_rsp(output logic [15:0] data, output logic [TID_BITMAP_WIDTH-1:0] bitmap);
    @(posedge clk_i);
    while (!rsp_valid) @(posedge clk_i);
    data   = rsp_data[15:0];
    bitmap = rsp_tid_bitmap;
    @(posedge clk_i);
  endtask

  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    enq_valid      = 1'b0;
    enq_addr       = '0;
    enq_data       = '0;
    enq_write_en   = 1'b0;
    enq_tid_bitmap = '0;
    enq_base_tid   = '0;
    enq_ld_dest_reg = '0;
    enq_address_map = '0;
    mem_rx_v       = 1'b0;
    mem_rx_data    = '0;
    mem_tx_ready   = 1'b0;
    pass_cnt       = 0;
    fail_cnt       = 0;

    rst_i = 1'b1;
    repeat(5) @(posedge clk_i);
    @(posedge clk_i); #1;
    rst_i = 1'b0;
    repeat(3) @(posedge clk_i);

    // -----------------------------------------------------------------------
    $display("\n--- T1: Single load via off-chip link ---");
    begin
      logic [15:0]             got_data;
      logic [TID_BITMAP_WIDTH-1:0] got_bitmap;
      // SRAM[0] pre-initialized to 0xA000
      cgra_load(MEM_BASE, 8'b0000_0001);   // thread slot 0
      wait_rsp(got_data, got_bitmap);
      check16(got_data,   16'hA000, "T1: load data from FPGA SRAM[0]");
      check16({{(16-TID_BITMAP_WIDTH){1'b0}}, got_bitmap}, 16'h0001, "T1: tid_bitmap passthrough");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T2: Single store via off-chip link ---");
    begin
      // Store 0xBEEF into SRAM[1] (addr = MEM_BASE + 2)
      cgra_store(MEM_BASE + 16'h0002, 16'hBEEF, 8'b0000_0010);
      // No rsp_valid for stores — wait enough cycles for WRITE_RESP to complete
      repeat(50) @(posedge clk_i);
      // Verify by loading back
      cgra_load(MEM_BASE + 16'h0002, 8'b0000_0001);
      begin
        logic [15:0] got_data;
        logic [TID_BITMAP_WIDTH-1:0] got_bitmap;
        wait_rsp(got_data, got_bitmap);
        check16(got_data, 16'hBEEF, "T2: store then load round-trip");
      end
    end

    // -----------------------------------------------------------------------
    $display("\n--- T3: Back-to-back loads ---");
    begin
      logic [15:0] got_data;
      logic [TID_BITMAP_WIDTH-1:0] got_bitmap;
      for (int i = 0; i < 4; i++) begin
        cgra_load(MEM_BASE + 16'(i * 2), 8'(1 << i));
        wait_rsp(got_data, got_bitmap);
        check16(got_data, fpga_sram[i],
                $sformatf("T3: back-to-back load SRAM[%0d]", i));
      end
    end

    // -----------------------------------------------------------------------
    $display("\n========================================");
    $display("  PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("  ALL TESTS PASSED!");
    $display("========================================\n");

    if (fail_cnt > 0) $stop;
    repeat(10) @(posedge clk_i);
    $finish;
  end

  // Debug monitor — print key signals every 50 cycles
  initial begin
    forever begin
      repeat(50) @(posedge clk_i);
      $display("[DBG t=%0t] enq_v=%b enq_rdy=%b enq_we=%b | rsp_v=%b | tx_v=%b tx_rdy=%b | rx_v=%b rx_rdy=%b | mem_rx_v=%b mem_rx_rdy=%b",
               $time, enq_valid, enq_ready, enq_write_en,
               rsp_valid,
               mem_tx_v, mem_tx_ready,
               mem_rx_v, mem_rx_ready,
               mem_rx_v, mem_rx_ready);
    end
  end

  // Watchdog
  initial begin
    #10_000_000;
    $error("TIMEOUT: simulation exceeded 10 us");
    $finish;
  end

endmodule : tb_cgra_io_axi4_link_top
