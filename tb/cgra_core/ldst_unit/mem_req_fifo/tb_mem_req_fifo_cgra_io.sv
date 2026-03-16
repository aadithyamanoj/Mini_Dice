// =============================================================================
// tb_mem_req_fifo_cgra_io.sv
//
// Integration testbench: mem_req_fifo ↔ cgra_io_mem_top
//
// DUT hierarchy:
//   dut_fifo : mem_req_fifo     — 16-deep load/store FIFO, AXI-Lite master
//   dut_mem  : cgra_io_mem_top  — flit bridge + 4-master crossbar + CSR + SRAM
//
// Connections:
//   mem_req_fifo AXI-Lite master → dut_mem.fpga_axi_i   (Master[0], crossbar)
//   Flit link (link_rx/tx)       → dut_mem cgra_data_axi (Master[3], crossbar)
//     — flit path used only as a stimulus/cross-check tool on the same memory
//       system; it does NOT represent bitstream or metadata fetch traffic.
//
// Address coverage:
//   enq_addr_i[7:0] → AXI addr {8'b0, addr} → CSR bank 0x0000–0x000E
//   (8 × 16-bit CSR regs at 2-byte stride; reachable within 8-bit address)
//
// Testing protocol (dice_testing style: tasks + $display + pass/fail counts):
//   T1 — Flit pre-write CSR[0] → FIFO load → check rsp_data / bitmap / base_tid
//   T2 — FIFO store → flit read-back → verify written byte persisted
//   T3 — FIFO store→load RAW round-trip (entirely through FIFO/AXI path)
//   T4 — 4 sequential loads; verify FIFO preserves in-order responses
//   T5 — Multi-TID loads; verify base_tid / tid_bitmap / address_map per thread
//   T6 — Backpressure: fill FIFO to capacity; check enq_ready_o deasserts
//   T7 — Stress: 8 consecutive stores then 8 readbacks via FIFO
// =============================================================================

`include "axi/typedef.svh"
`include "axi/assign.svh"

module tb_mem_req_fifo_cgra_io;

  import dice_pkg::*;
  import DE_pkg::*;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int unsigned AW       = 16;
  localparam int unsigned DW       = 16;
  localparam int unsigned LW       = 16;
  localparam int          CLK_HALF = 5;   // 100 MHz
  localparam int          FDEPTH   = 16;

  // SLOT_W = DICE_BASE_TID_ADDRESS_OFFSET = $clog2(8) = 3
  localparam int SLOT_W = DICE_BASE_TID_ADDRESS_OFFSET;

  // Flit opcodes (must match flit_axil_bridge)
  localparam logic [2:0] OP_AR = 3'd0;
  localparam logic [2:0] OP_AW = 3'd1;
  localparam logic [2:0] OP_B  = 3'd3;

  // CSR byte address for register i
  function automatic logic [7:0] csr_a(int i);
    return 8'(i * 2);
  endfunction

  // =========================================================================
  // Clock / reset
  // =========================================================================
  bit   clk_i;
  logic rst_i = 1'b1;
  initial forever #(CLK_HALF * 1ns) clk_i = ~clk_i;

  // =========================================================================
  // mem_req_fifo enqueue interface
  // =========================================================================
  logic                           enq_valid;
  logic                           enq_ready;
  logic [DICE_TID_WIDTH-1:0]      enq_tid;
  logic [7:0]                     enq_addr;
  logic [7:0]                     enq_data;
  logic                           enq_we;
  logic [DICE_REG_ADDR_WIDTH-1:0] enq_dest_reg;

  // =========================================================================
  // mem_req_fifo response outputs
  // =========================================================================
  logic                                                                  rsp_valid;
  logic [DICE_TID_WIDTH-1:0]                                            rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                          rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                       rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                       rsp_data;

  // =========================================================================
  // Flat AXI-Lite wires: mem_req_fifo ↔ AXI_LITE interface
  // =========================================================================
  logic [AW-1:0] m_awaddr;  logic m_awvalid; logic m_awready;
  logic [DW-1:0] m_wdata;   logic [1:0] m_wstrb;
  logic          m_wvalid;  logic m_wready;
  logic [1:0]    m_bresp;   logic m_bvalid;  logic m_bready;
  logic [AW-1:0] m_araddr;  logic m_arvalid; logic m_arready;
  logic [DW-1:0] m_rdata;   logic [1:0] m_rresp;
  logic          m_rvalid;  logic m_rready;

  // AXI_LITE interface: dut_fifo master → dut_mem.fpga_axi_i slave
  AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fifo_axi ();

  assign fifo_axi.aw_addr  = m_awaddr;
  assign fifo_axi.aw_prot  = 3'b0;
  assign fifo_axi.aw_valid = m_awvalid;
  assign fifo_axi.w_data   = m_wdata;
  assign fifo_axi.w_strb   = m_wstrb;
  assign fifo_axi.w_valid  = m_wvalid;
  assign fifo_axi.b_ready  = m_bready;
  assign fifo_axi.ar_addr  = m_araddr;
  assign fifo_axi.ar_prot  = 3'b0;
  assign fifo_axi.ar_valid = m_arvalid;
  assign fifo_axi.r_ready  = m_rready;

  assign m_awready = fifo_axi.aw_ready;
  assign m_wready  = fifo_axi.w_ready;
  assign m_bresp   = fifo_axi.b_resp;
  assign m_bvalid  = fifo_axi.b_valid;
  assign m_arready = fifo_axi.ar_ready;
  assign m_rdata   = fifo_axi.r_data;
  assign m_rresp   = fifo_axi.r_resp;
  assign m_rvalid  = fifo_axi.r_valid;

  // =========================================================================
  // Flit link — cross-check path using cgra_data_axi Master[3]
  // =========================================================================
  logic          link_rx_v;
  logic [LW-1:0] link_rx_data;
  logic          link_rx_ready;
  logic          link_tx_v;
  logic [LW-1:0] link_tx_data;
  logic          link_tx_ready;

  // =========================================================================
  // DUT 1: mem_req_fifo
  // =========================================================================
  mem_req_fifo #(
    .DEPTH (FDEPTH)
  ) dut_fifo (
    .clk_i              (clk_i),
    .rst_i              (rst_i),
    .enq_valid_i        (enq_valid),
    .enq_ready_o        (enq_ready),
    .enq_tid_i          (enq_tid),
    .enq_addr_i         (enq_addr),
    .enq_data_i         (enq_data),
    .enq_write_en_i     (enq_we),
    .enq_ld_dest_reg_i  (enq_dest_reg),
    .axi_awaddr_o       (m_awaddr),
    .axi_awvalid_o      (m_awvalid),
    .axi_awready_i      (m_awready),
    .axi_wdata_o        (m_wdata),
    .axi_wstrb_o        (m_wstrb),
    .axi_wvalid_o       (m_wvalid),
    .axi_wready_i       (m_wready),
    .axi_bresp_i        (m_bresp),
    .axi_bvalid_i       (m_bvalid),
    .axi_bready_o       (m_bready),
    .axi_araddr_o       (m_araddr),
    .axi_arvalid_o      (m_arvalid),
    .axi_arready_i      (m_arready),
    .axi_rdata_i        (m_rdata),
    .axi_rresp_i        (m_rresp),
    .axi_rvalid_i       (m_rvalid),
    .axi_rready_o       (m_rready),
    .rsp_valid_o        (rsp_valid),
    .rsp_base_tid_o     (rsp_base_tid),
    .rsp_tid_bitmap_o   (rsp_tid_bitmap),
    .rsp_ld_dest_reg_o  (rsp_ld_dest_reg),
    .rsp_address_map_o  (rsp_address_map),
    .rsp_data_o         (rsp_data)
  );

  // =========================================================================
  // DUT 2: cgra_io_mem_top
  // =========================================================================
  cgra_io_mem_top #(
    .ADDR_WIDTH    (AW),
    .DATA_WIDTH    (DW),
    .FLIT_WIDTH    (16),
    .LINK_WIDTH    (LW),
    .RX_FIFO_ELS   (16),
    .TX_FIFO_ELS   (16),
    .CSR_NUM_REGS  (8),
    .MEM_NUM_WORDS (1024)
  ) dut_mem (
    .clk_i           (clk_i),
    .rst_i           (rst_i),
    .link_rx_v_i     (link_rx_v),
    .link_rx_data_i  (link_rx_data),
    .link_rx_ready_o (link_rx_ready),
    .link_tx_v_o     (link_tx_v),
    .link_tx_data_o  (link_tx_data),
    .link_tx_ready_i (link_tx_ready),
    .fpga_axi_i      (fifo_axi)
  );

  // =========================================================================
  // Shadow memory (tracks bytes written via FIFO stores)
  // =========================================================================
  logic [7:0] shadow [logic [7:0]];
  int pass_cnt, fail_cnt, cyc;
  always @(posedge clk_i) cyc <= cyc + 1;

  // =========================================================================
  // Check helpers
  // =========================================================================
  task automatic check8(
    input logic [7:0] actual, expected,
    input string      msg
  );
    if (actual !== expected) begin
      $error("[FAIL] %s — Exp:0x%02h  Got:0x%02h", msg, expected, actual);
      fail_cnt++;
    end else begin
      $display("[PASS] %s", msg);
      pass_cnt++;
    end
  endtask

  task automatic check4(
    input logic [3:0] actual, expected,
    input string      msg
  );
    if (actual !== expected) begin
      $error("[FAIL] %s — Exp:0x%01h  Got:0x%01h", msg, expected, actual);
      fail_cnt++;
    end else begin
      $display("[PASS] %s", msg);
      pass_cnt++;
    end
  endtask

  // =========================================================================
  // FIFO enqueue helpers
  // =========================================================================
  task automatic fifo_load(
    input logic [DICE_TID_WIDTH-1:0]      tid,
    input logic [7:0]                     addr,
    input logic [DICE_REG_ADDR_WIDTH-1:0] dest_reg = '0
  );
    @(posedge clk_i); #1;
    enq_valid = 1'b1; enq_tid = tid; enq_addr = addr;
    enq_data = '0;    enq_we  = 1'b0; enq_dest_reg = dest_reg;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid = 1'b0;
  endtask

  task automatic fifo_store(
    input logic [DICE_TID_WIDTH-1:0] tid,
    input logic [7:0]                addr,
    input logic [7:0]                data
  );
    @(posedge clk_i); #1;
    enq_valid = 1'b1; enq_tid = tid; enq_addr = addr;
    enq_data  = data; enq_we  = 1'b1; enq_dest_reg = '0;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid = 1'b0;
  endtask

  // Wait for rsp_valid; extract the response byte at tid's slot.
  // Times out after 300 cycles.
  task automatic wait_rsp(
    input  logic [DICE_TID_WIDTH-1:0] tid,
    output logic [7:0]                rdata_byte
  );
    int t;
    logic [SLOT_W-1:0] slot;
    slot = tid[SLOT_W-1:0];
    t = 0;
    @(posedge clk_i);
    while (!rsp_valid) begin
      @(posedge clk_i);
      if (++t > 300) begin
        $error("[FAIL] wait_rsp timeout (tid=%0d)", tid);
        fail_cnt++; rdata_byte = 8'hXX; return;
      end
    end
    rdata_byte = rsp_data[slot * 8 +: 8];
  endtask

  // =========================================================================
  // Flit link helpers (cross-check path, mirrors tb_cgra_io_mem_top.sv)
  // =========================================================================
  task automatic send_link_word(input logic [LW-1:0] word);
    @(posedge clk_i); #1;
    link_rx_v = 1'b1; link_rx_data = word;
    while (!link_rx_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    link_rx_v = 1'b0; link_rx_data = '0;
  endtask

  task automatic recv_link_word(output logic [LW-1:0] word);
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    word = link_tx_data;
    @(posedge clk_i); #1;
    link_tx_ready = 1'b0;
  endtask

  // Write via flit and consume BVALID response.
  task automatic flit_write(input logic [AW-1:0] addr, input logic [DW-1:0] data);
    logic [LW-1:0] hdr, stat;
    send_link_word({OP_AW, 13'd2}); // LEN=2: addr flit + data flit
    send_link_word(LW'(addr));
    send_link_word(data);
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i); hdr  = link_tx_data;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i); stat = link_tx_data;
    @(posedge clk_i);
    link_tx_ready = 1'b0;
  endtask

  // Read via flit link; returns 16-bit word and AXI resp code.
  task automatic flit_read(
    input  logic [AW-1:0] addr,
    output logic [DW-1:0] rdata,
    output logic [1:0]    resp
  );
    logic [LW-1:0] hdr, stat;
    send_link_word({OP_AR, 13'd2});
    send_link_word(LW'(addr));
    send_link_word(16'd1);
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i); hdr   = link_tx_data;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i); stat  = link_tx_data;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i); rdata = link_tx_data;
    @(posedge clk_i);
    link_tx_ready = 1'b0;
    resp = stat[1:0];
  endtask

  // =========================================================================
  // Response monitor
  // =========================================================================
  always @(posedge clk_i) begin
    if (!rst_i && rsp_valid)
      $display("[MON] t=%0t  base_tid=%0d  bitmap=%08b  dest=%0d  data=0x%064h",
               $time, rsp_base_tid, rsp_tid_bitmap, rsp_ld_dest_reg, rsp_data);
  end

  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    enq_valid = 1'b0; enq_tid = '0; enq_addr = '0;
    enq_data  = '0;   enq_we  = 1'b0; enq_dest_reg = '0;
    link_rx_v = 1'b0; link_rx_data = '0; link_tx_ready = 1'b0;
    pass_cnt = 0; fail_cnt = 0; cyc = 0;

    rst_i = 1'b1;
    repeat (5) @(posedge clk_i);
    @(posedge clk_i); #1;
    rst_i = 1'b0;
    repeat (3) @(posedge clk_i);

    // =====================================================================
    $display("\n--- T1: Flit pre-write CSR[0] → FIFO load → check rsp fields ---");
    // Flit writes 0xABCD to CSR[0] via cgra_data_axi (Master[3]).
    // FIFO loads CSR[0] with TID=2 (slot=2, base_tid=0).
    // Expected rsp: data byte=0xCD, bitmap=8'h04, base_tid=0.
    // =====================================================================
    begin
      logic [7:0] got;

      flit_write(16'h0000, 16'hABCD);
      repeat (3) @(posedge clk_i);

      fifo_load(.tid(4'd2), .addr(csr_a(0)), .dest_reg(3'd1));
      wait_rsp(.tid(4'd2), .rdata_byte(got));

      check8(got,                           8'hCD,        "T1: rsp_data byte = CSR[0] low byte");
      check8(rsp_tid_bitmap,                8'h04,        "T1: rsp_tid_bitmap bit 2 (TID=2)");
      check4(rsp_base_tid,                  4'd0,         "T1: rsp_base_tid=0 for TID=2");
      check8(rsp_address_map[2][4:0],       5'(csr_a(0)), "T1: address_map[2]=addr offset");
    end

    // =====================================================================
    $display("\n--- T2: FIFO store → flit read-back → verify byte ---");
    // FIFO stores 0x42 to CSR[1] (byte addr 0x02) with TID=0.
    // Flit read from same address should see 0x42 in the low byte.
    // =====================================================================
    begin
      logic [DW-1:0] flit_rdata;
      logic [1:0]    flit_resp;

      fifo_store(.tid(4'd0), .addr(csr_a(1)), .data(8'h42));
      shadow[csr_a(1)] = 8'h42;
      repeat (10) @(posedge clk_i);

      flit_read(16'h0002, flit_rdata, flit_resp);
      check8(flit_rdata[7:0], 8'h42, "T2: CSR[1] low byte after FIFO store");
      check8({6'b0, flit_resp}, 8'h0, "T2: OKAY AXI resp from flit read");
    end

    // =====================================================================
    $display("\n--- T3: FIFO store→load RAW round-trip ---");
    // FIFO store 0xBE to CSR[2], then load it back with TID=5.
    // FSM serialises the two so load always sees the written value.
    // =====================================================================
    begin
      logic [7:0] got;

      fifo_store(.tid(4'd5), .addr(csr_a(2)), .data(8'hBE));
      shadow[csr_a(2)] = 8'hBE;
      repeat (3) @(posedge clk_i);

      fifo_load(.tid(4'd5), .addr(csr_a(2)));
      wait_rsp(.tid(4'd5), .rdata_byte(got));

      check8(got,            8'hBE, "T3: RAW load returns stored byte");
      check8(rsp_tid_bitmap, 8'h20, "T3: rsp_tid_bitmap bit 5 (TID=5)");
      check4(rsp_base_tid,   4'd0,  "T3: rsp_base_tid=0 for TID=5");
    end

    // =====================================================================
    $display("\n--- T4: 4 sequential FIFO loads — verify in-order responses ---");
    // Pre-seed CSR[0..3] via flit, then enqueue 4 loads with TIDs 0–3.
    // Because AXI-Lite serialises, responses must arrive in enqueue order.
    // =====================================================================
    begin
      logic [7:0] got;
      logic [7:0] exp[4];

      for (int i = 0; i < 4; i++) begin
        flit_write(AW'(i * 2), DW'(16'hF0 + i));
        exp[i] = 8'(8'hF0 + i);
      end
      repeat (3) @(posedge clk_i);

      for (int i = 0; i < 4; i++)
        fifo_load(.tid(DICE_TID_WIDTH'(i)), .addr(8'(i * 2)));

      for (int i = 0; i < 4; i++) begin
        wait_rsp(.tid(DICE_TID_WIDTH'(i)), .rdata_byte(got));
        check8(got,            exp[i],          $sformatf("T4: load[%0d] data",   i));
        check8(rsp_tid_bitmap, 8'(1 << i),      $sformatf("T4: load[%0d] bitmap", i));
      end
    end

    // =====================================================================
    $display("\n--- T5: Multi-TID — base_tid / bitmap / address_map per thread ---");
    // TID=8  → slot=0, base_tid=8;  reads CSR[4] (0x08) = 0x70
    // TID=9  → slot=1, base_tid=8;  reads CSR[5] (0x0A) = 0x81
    // TID=15 → slot=7, base_tid=8;  reads CSR[3] (0x06) = 0xC3
    // =====================================================================
    begin
      logic [7:0] got;

      flit_write(16'h0008, 16'h0070);
      flit_write(16'h000A, 16'h0081);
      flit_write(16'h0006, 16'h00C3);
      repeat (3) @(posedge clk_i);

      fifo_load(.tid(4'd8), .addr(8'h08));
      wait_rsp(.tid(4'd8), .rdata_byte(got));
      check4(rsp_base_tid,   4'd8,   "T5: TID=8  base_tid=8");
      check8(rsp_tid_bitmap, 8'h01,  "T5: TID=8  bitmap bit 0");
      check8(got,            8'h70,  "T5: TID=8  data");

      fifo_load(.tid(4'd9), .addr(8'h0A));
      wait_rsp(.tid(4'd9), .rdata_byte(got));
      check4(rsp_base_tid,   4'd8,   "T5: TID=9  base_tid=8");
      check8(rsp_tid_bitmap, 8'h02,  "T5: TID=9  bitmap bit 1");
      check8(got,            8'h81,  "T5: TID=9  data");

      fifo_load(.tid(4'd15), .addr(8'h06));
      wait_rsp(.tid(4'd15), .rdata_byte(got));
      check4(rsp_base_tid,   4'd8,   "T5: TID=15 base_tid=8");
      check8(rsp_tid_bitmap, 8'h80,  "T5: TID=15 bitmap bit 7");
      check8(got,            8'hC3,  "T5: TID=15 data");
    end

    // =====================================================================
    $display("\n--- T6: Backpressure — fill FIFO; enq_ready_o must deassert ---");
    // =====================================================================
    begin
      int accepted;
      accepted = 0;

      // One store to keep the FSM occupied mid-handshake
      fifo_store(.tid(4'd0), .addr(8'h00), .data(8'hAA));
      accepted++;

      // Flood remaining slots without waiting for ready
      @(posedge clk_i); #1;
      for (int i = 1; i < FDEPTH + 4; i++) begin
        enq_valid = 1'b1; enq_tid = DICE_TID_WIDTH'(i % 8);
        enq_addr  = 8'h00; enq_data = '0;
        enq_we    = 1'b0;  enq_dest_reg = '0;
        @(posedge clk_i); #1;
        if (enq_ready) accepted++;
      end
      enq_valid = 1'b0;

      if (!enq_ready) begin
        $display("[PASS] T6: enq_ready_o deasserted (accepted %0d entries)", accepted);
        pass_cnt++;
      end else begin
        $error("[FAIL] T6: enq_ready_o still asserted after %0d enqueues", accepted);
        fail_cnt++;
      end

      // Wait for FIFO to fully drain before next test
      @(posedge clk_i);
      while (!enq_ready) @(posedge clk_i);
      repeat (FDEPTH * 20) @(posedge clk_i);
    end

    // =====================================================================
    $display("\n--- T7: Stress — 8 consecutive stores then 8 readbacks ---");
    // =====================================================================
    begin
      logic [7:0] got;
      logic [7:0] exp[8];

      for (int i = 0; i < 8; i++) begin
        exp[i] = 8'(8'hC0 + i);
        fifo_store(.tid(DICE_TID_WIDTH'(i % 8)), .addr(csr_a(i)), .data(exp[i]));
        shadow[csr_a(i)] = exp[i];
      end
      repeat (60) @(posedge clk_i);   // allow all stores to drain

      // Load and wait one at a time: rsp_valid_o is combinatorial and lasts
      // only one cycle, so all loads must not be pre-queued ahead of the
      // corresponding wait_rsp calls.
      for (int i = 0; i < 8; i++) begin
        fifo_load(.tid(DICE_TID_WIDTH'(i % 8)), .addr(csr_a(i)));
        wait_rsp(.tid(DICE_TID_WIDTH'(i % 8)), .rdata_byte(got));
        check8(got, exp[i], $sformatf("T7: readback CSR[%0d]=0x%02h", i, exp[i]));
      end
    end

    // =====================================================================
    $display("\n========================================");
    $display("  PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("  ALL TESTS PASSED!");
    $display("========================================\n");
    if (fail_cnt > 0) $stop;
    repeat (10) @(posedge clk_i);
    $finish;
  end

  // =========================================================================
  // Timeout watchdog
  // =========================================================================
  initial begin
    #500_000_000;
    $error("TIMEOUT: simulation exceeded 500 us");
    $finish;
  end

  // =========================================================================
  // Waveform dump
  // =========================================================================
  initial begin
    $fsdbDumpfile("tb_mem_req_fifo_cgra_io.fsdb");
    $fsdbDumpvars("+all");
  end

endmodule
