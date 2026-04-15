// =============================================================================
// tb_cgra_io_axi4_link_top.sv
//
// Testbench for the off-chip memory link path through cgra_io_axi4_top.
//
// Path under test:
//   mem_req_fifo (enq_*) → [dfetch port] → crossbar → top_level_io TX
//   → bsg_link_ddr_upstream → [DDR pins] → FPGA endpoint (second top_level_io)
//   FPGA endpoint → [DDR pins] → bsg_link_ddr_downstream → top_level_io RX
//   → ID shim → crossbar → mem_req_fifo (rsp_*)
//
// The TB acts as the FPGA SRAM endpoint via a second top_level_io instance
// connected back-to-back on the DDR physical pins.  The FPGA memory model
// drives the endpoint's flat AXI TX ports (R/B responses) and reads its
// RX ports (AW/W/AR requests decoded from chip flits).
//
// Test plan:
//   T1 : Single load  — enqueue AR, FPGA endpoint returns READ_RESP,
//                        check rsp_data_o and rsp_tid_bitmap_o
//   T2 : Single store — enqueue AW+W, FPGA endpoint returns WRITE_RESP
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
  localparam int AW          = 16;
  localparam int DW          = 16;
  localparam int FW          = 16;
  localparam int CLK_HALF_NS = 5;   // 100 MHz core clock

  localparam logic [AW-1:0] MEM_BASE  = 16'h0800;
  localparam int             MEM_WORDS = 1024;

  // -------------------------------------------------------------------------
  // Clocks — single clock used for core and IO in simulation
  // -------------------------------------------------------------------------
  bit   clk_i;
  logic rst_i = 1'b1;
  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

  // -------------------------------------------------------------------------
  // FPGA AXI-Lite flat pins (fpga_mst port — tied off)
  // -------------------------------------------------------------------------
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

  // -------------------------------------------------------------------------
  // mem_req_fifo enqueue interface — 4 parallel ports; TB uses only port 0
  // -------------------------------------------------------------------------
  logic        enq_valid_0 = 1'b0;
  logic        enq_ready;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] enq_tid = '0;
  logic [15:0] enq_addr_0 = '0;
  logic [15:0] enq_data_0 = '0;
  logic        enq_op_0   = 1'b0;   // 0 = load, 1 = store

  // -------------------------------------------------------------------------
  // mem_req_fifo response interface
  // -------------------------------------------------------------------------
  logic        rsp_data_ready = 1'b1;
  logic        pop_out;
  logic        rsp_valid;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0] rsp_tid;
  logic [15:0] rsp_addr;
  logic [15:0] rsp_data;

  // -------------------------------------------------------------------------
  // CSR slave (tied off)
  // -------------------------------------------------------------------------
  mst_req_t  csr_req;
  mst_resp_t csr_resp;
  assign csr_resp = '0;

  // -------------------------------------------------------------------------
  // bsg_link reset/control for DUT
  // -------------------------------------------------------------------------
  logic dut_upstream_io_link_reset   = 1'b1;
  logic dut_async_token_reset        = 1'b0;
  logic dut_downstream_io_link_reset = 1'b1;

  // -------------------------------------------------------------------------
  // DDR physical pins: DUT upstream output → FPGA endpoint downstream input
  // -------------------------------------------------------------------------
  logic       dut_up_clk_r;
  logic [15:0] dut_up_data_r;
  logic        dut_up_valid_r;
  logic        dut_dn_token_r;   // DUT downstream token → FPGA ep token_clk_i

  // -------------------------------------------------------------------------
  // DDR physical pins: FPGA endpoint upstream output → DUT downstream input
  // -------------------------------------------------------------------------
  logic        ep_up_clk_r;
  logic [15:0] ep_up_data_r;
  logic       ep_up_valid_r;
  logic       ep_dn_token_r;    // FPGA ep downstream token → DUT token_clk_i

  // -------------------------------------------------------------------------
  // bsg_link reset/control for FPGA endpoint
  // -------------------------------------------------------------------------
  logic ep_upstream_io_link_reset   = 1'b1;
  logic ep_async_token_reset        = 1'b0;
  logic ep_downstream_io_link_reset = 1'b1;

  // =========================================================================
  // DUT: cgra_io_axi4_top
  // =========================================================================
  cgra_io_axi4_top #(
    .ADDR_WIDTH          ( AW ),
    .DATA_WIDTH          ( DW ),
    .FLIT_WIDTH          ( FW ),
    .BYPASS_GEARBOX      ( 1  ),
    .BYPASS_TWOFER_FIFO  ( 1  )
  ) dut (
    .clk_i                      ( clk_i                    ),
    .rst_i                      ( rst_i                    ),

    .fpga_axi_i_aw_addr         ( fpga_aw_addr             ),
    .fpga_axi_i_aw_prot         ( fpga_aw_prot             ),
    .fpga_axi_i_aw_valid        ( fpga_aw_valid            ),
    .fpga_axi_i_aw_ready        ( fpga_aw_ready            ),
    .fpga_axi_i_w_data          ( fpga_w_data              ),
    .fpga_axi_i_w_strb          ( fpga_w_strb              ),
    .fpga_axi_i_w_valid         ( fpga_w_valid             ),
    .fpga_axi_i_w_ready         ( fpga_w_ready             ),
    .fpga_axi_i_b_resp          ( fpga_b_resp              ),
    .fpga_axi_i_b_valid         ( fpga_b_valid             ),
    .fpga_axi_i_b_ready         ( fpga_b_ready             ),
    .fpga_axi_i_ar_addr         ( fpga_ar_addr             ),
    .fpga_axi_i_ar_prot         ( fpga_ar_prot             ),
    .fpga_axi_i_ar_valid        ( fpga_ar_valid            ),
    .fpga_axi_i_ar_ready        ( fpga_ar_ready            ),
    .fpga_axi_i_r_data          ( fpga_r_data              ),
    .fpga_axi_i_r_resp          ( fpga_r_resp              ),
    .fpga_axi_i_r_valid         ( fpga_r_valid             ),
    .fpga_axi_i_r_ready         ( fpga_r_ready             ),

    .enq_valid_i_0              ( enq_valid_0              ),
    .enq_valid_i_1              ( 1'b0                     ),
    .enq_valid_i_2              ( 1'b0                     ),
    .enq_valid_i_3              ( 1'b0                     ),
    .enq_ready_o                ( enq_ready                ),
    .enq_tid_i                  ( enq_tid                  ),
    .enq_addr_i_0               ( enq_addr_0               ),
    .enq_addr_i_1               ( '0                       ),
    .enq_addr_i_2               ( '0                       ),
    .enq_addr_i_3               ( '0                       ),
    .enq_data_i_0               ( enq_data_0               ),
    .enq_data_i_1               ( '0                       ),
    .enq_data_i_2               ( '0                       ),
    .enq_data_i_3               ( '0                       ),
    .enq_op_i_0                 ( enq_op_0                 ),
    .enq_op_i_1                 ( 1'b0                     ),
    .enq_op_i_2                 ( 1'b0                     ),
    .enq_op_i_3                 ( 1'b0                     ),

    .rsp_data_ready_i           ( rsp_data_ready           ),
    .pop_o                      ( pop_out                  ),
    .rsp_valid_o                ( rsp_valid                ),
    .rsp_tid_o                  ( rsp_tid                  ),
    .rsp_addr_o                 ( rsp_addr                 ),
    .rsp_data_o                 ( rsp_data                 ),

    // bsg_link upstream (DUT → FPGA endpoint)
    .io_master_clk_i            ( clk_i                    ),
    .upstream_io_link_reset_i   ( dut_upstream_io_link_reset ),
    .async_token_reset_i        ( dut_async_token_reset    ),
    .token_clk_i                ( ep_dn_token_r            ),  // FPGA ep downstream token
    .upstream_io_clk_r_o        ( dut_up_clk_r             ),
    .upstream_io_data_r_o       ( dut_up_data_r            ),
    .upstream_io_valid_r_o      ( dut_up_valid_r           ),

    // bsg_link downstream (FPGA endpoint → DUT)
    .downstream_io_link_reset_i ( dut_downstream_io_link_reset ),
    .downstream_io_clk_i        ( ep_up_clk_r              ),  // FPGA ep upstream clk
    .downstream_io_data_i       ( ep_up_data_r             ),  // FPGA ep upstream data
    .downstream_io_valid_i      ( ep_up_valid_r            ),  // FPGA ep upstream valid
    .downstream_core_token_r_o  ( dut_dn_token_r           ),  // → FPGA ep token_clk_i

    .cgra_csr_req_o             ( csr_req                  ),
    .cgra_csr_resp_i            ( csr_resp                 )
  );

  // =========================================================================
  // FPGA endpoint: second top_level_io, back-to-back with DUT
  //
  // Physical connections (mirrored):
  //   DUT upstream out  →  FPGA ep downstream in
  //   FPGA ep upstream out  →  DUT downstream in
  //   DUT downstream token  →  FPGA ep token_clk_i
  //   FPGA ep downstream token  →  DUT token_clk_i
  // =========================================================================

  // FPGA endpoint AXI signals driven by memory model
  logic        ep_tx_rvalid  = 1'b0;
  logic [DW-1:0] ep_tx_rdata  = '0;
  logic        ep_tx_rlast   = 1'b0;
  logic [1:0]  ep_tx_rresp   = '0;
  logic        ep_tx_rready;          // from top_level_io (link can accept R)

  logic        ep_tx_bvalid  = 1'b0;
  logic [1:0]  ep_tx_bresp   = '0;
  logic        ep_tx_bready;          // from top_level_io (link can accept B)

  // FPGA endpoint AXI RX outputs (decoded requests from chip)
  logic        ep_rx_arvalid;
  logic [AW-1:0] ep_rx_araddr;
  logic        ep_rx_awvalid;
  logic [AW-1:0] ep_rx_awaddr;
  logic        ep_rx_wvalid;
  logic [DW-1:0] ep_rx_wdata;

  top_level_io #(
    .flit_width_p                    ( FW ),
    .addr_width_p                    ( AW ),
    .channel_width_p                 ( 16 ),
    .num_channels_p                  ( 1  ),
    .bypass_gearbox_p                ( 1  ),
    .bypass_twofer_fifo_p            ( 1  ),
    .rx_link_fifo_els_p              ( 8  ),
    .rx_aw_desc_fifo_els_p           ( 2  ),
    .rx_ar_desc_fifo_els_p           ( 2  ),
    .rx_w_len_fifo_els_p             ( 4  ),
    .rx_w_data_fifo_els_p            ( 8  ),
    .rx_r_len_fifo_els_p             ( 4  ),
    .rx_r_data_fifo_els_p            ( 8  ),
    .rx_b_resp_fifo_els_p            ( 4  ),
    .tx_link_fifo_els_p              ( 8  ),
    .tx_aw_desc_fifo_els_p           ( 2  ),
    .tx_ar_desc_fifo_els_p           ( 2  ),
    .tx_w_len_fifo_els_p             ( 4  ),
    .tx_w_data_fifo_els_p            ( 8  ),
    .tx_r_len_fifo_els_p             ( 4  ),
    .tx_r_data_fifo_els_p            ( 8  ),
    .tx_b_resp_fifo_els_p            ( 4  ),
    .tx_pkt_order_fifo_els_p         ( 8  )
  ) u_fpga_ep (
    .core_clk_i                 ( clk_i                    ),
    .reset_i                    ( rst_i                    ),

    // bsg_link upstream (FPGA ep → DUT downstream)
    .io_master_clk_i            ( clk_i                    ),
    .upstream_io_link_reset_i   ( ep_upstream_io_link_reset ),
    .async_token_reset_i        ( ep_async_token_reset     ),
    .token_clk_i                ( dut_dn_token_r           ),  // DUT downstream token
    .upstream_io_clk_r_o        ( ep_up_clk_r              ),
    .upstream_io_data_r_o       ( ep_up_data_r             ),
    .upstream_io_valid_r_o      ( ep_up_valid_r            ),

    // bsg_link downstream (DUT upstream → FPGA ep)
    .downstream_io_link_reset_i ( ep_downstream_io_link_reset ),
    .downstream_io_clk_i        ( dut_up_clk_r             ),  // DUT upstream clk
    .downstream_io_data_i       ( dut_up_data_r            ),  // DUT upstream data
    .downstream_io_valid_i      ( dut_up_valid_r           ),  // DUT upstream valid
    .downstream_core_token_r_o  ( ep_dn_token_r            ),  // → DUT token_clk_i

    // TX: FPGA ep sends R/B responses back to chip
    .tx_awvalid_i   ( 1'b0         ),
    .tx_awready_o   (              ),
    .tx_awaddr_i    ( '0           ),
    .tx_awlen_i     ( '0           ),
    .tx_awsize_i    ( '0           ),
    .tx_awburst_i   ( '0           ),
    .tx_wvalid_i    ( 1'b0         ),
    .tx_wready_o    (              ),
    .tx_wdata_i     ( '0           ),
    .tx_wlast_i     ( 1'b0         ),
    .tx_arvalid_i   ( 1'b0         ),
    .tx_arready_o   (              ),
    .tx_araddr_i    ( '0           ),
    .tx_arlen_i     ( '0           ),
    .tx_arsize_i    ( '0           ),
    .tx_arburst_i   ( '0           ),
    .tx_rvalid_i    ( ep_tx_rvalid ),
    .tx_rready_o    ( ep_tx_rready ),
    .tx_rdata_i     ( ep_tx_rdata  ),
    .tx_rresp_i     ( ep_tx_rresp  ),
    .tx_rlast_i     ( ep_tx_rlast  ),
    .tx_bvalid_i    ( ep_tx_bvalid ),
    .tx_bready_o    ( ep_tx_bready ),
    .tx_bresp_i     ( ep_tx_bresp  ),

    // RX: FPGA ep receives AW/W/AR decoded from chip flits
    .rx_awvalid_o   ( ep_rx_awvalid ),
    .rx_awready_i   ( 1'b1          ),
    .rx_awaddr_o    ( ep_rx_awaddr  ),
    .rx_awlen_o     (               ),
    .rx_awsize_o    (               ),
    .rx_awburst_o   (               ),
    .rx_wvalid_o    ( ep_rx_wvalid  ),
    .rx_wready_i    ( 1'b1          ),
    .rx_wdata_o     ( ep_rx_wdata   ),
    .rx_wlast_o     (               ),
    .rx_arvalid_o   ( ep_rx_arvalid ),
    .rx_arready_i   ( 1'b1          ),
    .rx_araddr_o    ( ep_rx_araddr  ),
    .rx_arlen_o     (               ),
    .rx_arsize_o    (               ),
    .rx_arburst_o   (               ),
    // chip does not send R/B to FPGA — ignore
    .rx_rvalid_o    (               ),
    .rx_rready_i    ( 1'b0          ),
    .rx_rdata_o     (               ),
    .rx_rresp_o     (               ),
    .rx_rlast_o     (               ),
    .rx_bvalid_o    (               ),
    .rx_bready_i    ( 1'b0          ),
    .rx_bresp_o     (               )
  );

  // =========================================================================
  // FPGA memory model
  // =========================================================================
  logic [15:0] fpga_sram [0:MEM_WORDS-1];

  // =========================================================================
  // FPGA AXI slave — drives ep_tx_* in response to ep_rx_*
  // Single-outstanding, so no overlap between transactions.
  // =========================================================================
  logic        ep_aw_pending = 1'b0;
  logic [AW-1:0] ep_aw_addr_lat = '0;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ep_tx_rvalid  <= 1'b0;
      ep_tx_bvalid  <= 1'b0;
      ep_aw_pending <= 1'b0;
      foreach (fpga_sram[i]) fpga_sram[i] <= 16'(i + 16'hA000);
    end else begin
      // Deassert when link accepts the beat
      if (ep_tx_rvalid && ep_tx_rready) ep_tx_rvalid <= 1'b0;
      if (ep_tx_bvalid && ep_tx_bready) ep_tx_bvalid <= 1'b0;

      // Service read: AR visible → capture addr and queue R response
      if (ep_rx_arvalid && !ep_tx_rvalid) begin
        begin : rd_blk
          int idx;
          idx = int'((ep_rx_araddr - AW'(MEM_BASE)) >> 1);
          ep_tx_rdata  <= (idx >= 0 && idx < MEM_WORDS) ? fpga_sram[idx] : 16'hDEAD;
        end
        ep_tx_rlast  <= 1'b1;
        ep_tx_rresp  <= 2'b00;
        ep_tx_rvalid <= 1'b1;
      end

      // Latch write address
      if (ep_rx_awvalid && !ep_aw_pending) begin
        ep_aw_addr_lat <= ep_rx_awaddr;
        ep_aw_pending  <= 1'b1;
      end

      // Service write: W arrives after AW latched → write mem + send B
      if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid) begin
        begin : wr_blk
          int idx;
          idx = int'((ep_aw_addr_lat - AW'(MEM_BASE)) >> 1);
          if (idx >= 0 && idx < MEM_WORDS)
            fpga_sram[idx] <= ep_rx_wdata[15:0];
        end
        ep_aw_pending  <= 1'b0;
        ep_tx_bresp    <= 2'b00;
        ep_tx_bvalid   <= 1'b1;
      end
    end
  end

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
  // Stimulus helpers
  // =========================================================================
  task automatic cgra_load(input logic [15:0] addr);
    @(posedge clk_i); #1;
    enq_valid_0 = 1'b1;
    enq_addr_0  = addr;
    enq_data_0  = '0;
    enq_op_0    = 1'b0;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid_0 = 1'b0;
  endtask

  task automatic cgra_store(input logic [15:0] addr, input logic [15:0] data);
    @(posedge clk_i); #1;
    enq_valid_0 = 1'b1;
    enq_addr_0  = addr;
    enq_data_0  = data;
    enq_op_0    = 1'b1;
    while (!enq_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    enq_valid_0 = 1'b0;
  endtask

  task automatic wait_rsp(output logic [15:0] data);
    @(posedge clk_i);
    while (!rsp_valid) @(posedge clk_i);
    data = rsp_data;
    @(posedge clk_i);
  endtask

  // =========================================================================
  // Stimulus + bsg_link reset sequence
  // =========================================================================
  initial begin
    enq_valid_0 = 1'b0;
    enq_addr_0  = '0;
    enq_data_0  = '0;
    enq_op_0    = 1'b0;
    enq_tid     = '0;
    pass_cnt    = 0;
    fail_cnt    = 0;

    // -- bsg_link reset sequence --
    // Step 1: assert all resets
    rst_i                        = 1'b1;
    dut_upstream_io_link_reset   = 1'b1;
    dut_downstream_io_link_reset = 1'b1;
    ep_upstream_io_link_reset    = 1'b1;
    ep_downstream_io_link_reset  = 1'b1;
    dut_async_token_reset        = 1'b0;
    ep_async_token_reset         = 1'b0;
    repeat(4) @(posedge clk_i);

    // Step 2: toggle async_token_reset while io_link_resets are still high
    @(posedge clk_i); #1;
    dut_async_token_reset = 1'b1;
    ep_async_token_reset  = 1'b1;
    @(posedge clk_i); #1;
    dut_async_token_reset = 1'b0;
    ep_async_token_reset  = 1'b0;

    // Step 3: let core clock run (io_clk = core_clk for master side)
    repeat(8) @(posedge clk_i);

    // Step 4a: deassert UPSTREAM io_link_resets — starts ODDR clock outputs
    //          (dut_up_clk_r and ep_up_clk_r begin toggling)
    @(posedge clk_i); #1;
    dut_upstream_io_link_reset = 1'b0;
    ep_upstream_io_link_reset  = 1'b0;

    // Step 4b: wait for ODDR clock outputs to stabilize (~4 cycles through PHY pipeline)
    repeat(8) @(posedge clk_i);

    // Step 4c: deassert DOWNSTREAM io_link_resets — now downstream io_clk_i is valid
    @(posedge clk_i); #1;
    dut_downstream_io_link_reset = 1'b0;
    ep_downstream_io_link_reset  = 1'b0;

    // Step 5: deassert core reset
    repeat(4) @(posedge clk_i);
    @(posedge clk_i); #1;
    rst_i = 1'b0;
    repeat(10) @(posedge clk_i);

    // -----------------------------------------------------------------------
    $display("\n--- T1: Single load via off-chip DDR link ---");
    begin
      logic [15:0] got_data;
      // SRAM[0] pre-initialized to 0xA000
      cgra_load(MEM_BASE);
      wait_rsp(got_data);
      check16(got_data, 16'hA000, "T1: load data from FPGA SRAM[0]");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T2: Single store via off-chip DDR link ---");
    begin
      // Store 0xBEEF into SRAM[1] (addr = MEM_BASE + 2)
      cgra_store(MEM_BASE + 16'h0002, 16'hBEEF);
      repeat(100) @(posedge clk_i);
      // Verify by loading back
      cgra_load(MEM_BASE + 16'h0002);
      begin
        logic [15:0] got_data;
        wait_rsp(got_data);
        check16(got_data, 16'hBEEF, "T2: store then load round-trip");
      end
    end

    // -----------------------------------------------------------------------
    $display("\n--- T3: Back-to-back loads ---");
    begin
      logic [15:0] got_data;
      for (int i = 0; i < 4; i++) begin
        cgra_load(MEM_BASE + 16'(i * 2));
        wait_rsp(got_data);
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

  // Debug monitor
  initial begin
    forever begin
      repeat(50) @(posedge clk_i);
      $display("[DBG t=%0t] enq_v=%b rdy=%b op=%b | rsp_v=%b | ep_rx_ar=%b ep_rx_aw=%b ep_rx_w=%b | ep_tx_r=%b ep_tx_b=%b",
               $time,
               enq_valid_0, enq_ready, enq_op_0,
               rsp_valid,
               ep_rx_arvalid, ep_rx_awvalid, ep_rx_wvalid,
               ep_tx_rvalid,  ep_tx_bvalid);
    end
  end

  // Watchdog — extended to allow for bsg_link DDR latency
  initial begin
    #50_000_000;
    $error("TIMEOUT: simulation exceeded 50 us");
    $finish;
  end

endmodule : tb_cgra_io_axi4_link_top
