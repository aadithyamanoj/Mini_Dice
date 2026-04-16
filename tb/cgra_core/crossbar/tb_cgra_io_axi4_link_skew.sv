// =============================================================================
// tb_cgra_io_axi4_link_skew.sv
//
// Stress testbench for cgra_io_axi4_top exercising realistic physical
// impairments on the bsg_link DDR source-synchronous bus:
//
//   1. DIFFERENT FREQUENCIES: core clock (100 MHz) vs IO master clock (~103 MHz).
//      The two clock domains drift relative to each other over time, exercising
//      the async FIFO and token flow-control across a non-trivial CDC boundary.
//
//   2. FORWARDED CLOCK PHASE OFFSET: ~1.5ns extra wire delay on the forwarded
//      io_clk_r signal between transmitter and receiver.  The ODDR PHY
//      center-aligns the clock to the data eye at launch; the extra board
//      delay shifts the sampling point within that eye.
//
//   3. PER-PIN DATA SKEW: each of the 8 data bits plus the valid pin has an
//      independent wire delay (0.3 – 2.1 ns range).  The IDDR PHY latches all
//      bits on the same forwarded clock edge, so it must tolerate this spread.
//
//   4. TOKEN ROUND-TRIP DELAY: the credit token wire back from downstream to
//      upstream has its own independent delay.
//
// The same T1/T2/T3 functional tests from the RTL TB are run.  Passing here
// confirms that the CDC logic and source-sync capture work under these
// conditions.
// =============================================================================

`timescale 1ns/1ps

`include "dice_define.vh"

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module tb_cgra_io_axi4_link_skew;

  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;

  // -------------------------------------------------------------------------
  // Clock parameters
  // -------------------------------------------------------------------------
  // Core clock: 100 MHz (10 ns period, 5 ns half)
  localparam real CORE_CLK_HALF_NS = 5.0;
  // IO master clock: ~103 MHz (9.7 ns period, 4.85 ns half).
  // Runs ~3% faster than core_clk → drifts ~1 cycle per 33 core cycles.
  localparam real IO_CLK_HALF_NS   = 4.85;

  // -------------------------------------------------------------------------
  // Wire delay parameters (ns) for the DDR physical bus
  // -------------------------------------------------------------------------
  // Forwarded clock: extra 1.5 ns board delay beyond the data traces.
  // (Clock and data both have ~0.5 ns base common-mode delay, so net
  //  clock-to-data skew at the receiver is +1.5 ns — clock arrives later,
  //  meaning data is already stable, which adds setup margin.)
  localparam real CLK_EXTRA_DELAY_NS   = 1.5;
  localparam real CLK_BASE_DELAY_NS    = 0.5;
  localparam real CLK_WIRE_DELAY_NS    = CLK_BASE_DELAY_NS + CLK_EXTRA_DELAY_NS; // 2.0 ns

  // Data bit delays (base + per-bit skew to spread across a 1.8 ns window)
  // Bit 0 is shortest trace, bit 7 is longest.
  localparam real DATA_BASE_NS         = 0.3;
  localparam real DATA_SKEW_STEP_NS    = 0.25; // 0.25 ns between adjacent bits

  localparam real VALID_WIRE_DELAY_NS  = 0.7;
  localparam real TOKEN_WIRE_DELAY_NS  = 0.6;

  // -------------------------------------------------------------------------
  // AXI / link widths
  // -------------------------------------------------------------------------
  localparam int AW = 16;
  localparam int DW = 16;
  localparam int FW = 16;

  localparam logic [AW-1:0] MEM_BASE  = 16'h0800;
  localparam int             MEM_WORDS = 1024;

  // -------------------------------------------------------------------------
  // Clocks — separate core and IO, different frequencies
  // -------------------------------------------------------------------------
  bit   core_clk;
  bit   io_clk;
  logic rst_i = 1'b1;

  initial forever #(CORE_CLK_HALF_NS * 1ns) core_clk = ~core_clk;
  initial forever #(IO_CLK_HALF_NS   * 1ns) io_clk   = ~io_clk;

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
  logic        enq_op_0   = 1'b0;

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
  // bsg_link reset/control
  // -------------------------------------------------------------------------
  logic dut_upstream_io_link_reset   = 1'b1;
  logic dut_async_token_reset        = 1'b0;
  logic dut_downstream_io_link_reset = 1'b1;

  logic ep_upstream_io_link_reset    = 1'b1;
  logic ep_async_token_reset         = 1'b0;
  logic ep_downstream_io_link_reset  = 1'b1;

  // -------------------------------------------------------------------------
  // DDR physical pins — raw outputs from DUT upstream / EP upstream
  // -------------------------------------------------------------------------
  logic       dut_up_clk_r_raw;
  logic [7:0]  dut_up_data_r_raw;
  logic        dut_up_valid_r_raw;
  logic        dut_dn_token_r_raw;   // DUT downstream → EP token_clk

  logic        ep_up_clk_r_raw;
  logic [7:0]  ep_up_data_r_raw;
  logic       ep_up_valid_r_raw;
  logic       ep_dn_token_r_raw;    // EP downstream → DUT token_clk

  // -------------------------------------------------------------------------
  // DDR physical pins — delayed signals arriving at the receiver
  //
  // DUT→EP path: DUT upstream output, delayed, → EP downstream input
  // EP→DUT path: EP upstream output, delayed, → DUT downstream input
  // -------------------------------------------------------------------------
  logic       dut_up_clk_r_d;
  logic [7:0]  dut_up_data_r_d;
  logic        dut_up_valid_r_d;
  logic        ep_dn_token_r_d;     // delayed token back to DUT

  logic        ep_up_clk_r_d;
  logic [7:0]  ep_up_data_r_d;
  logic       ep_up_valid_r_d;
  logic       dut_dn_token_r_d;    // delayed token back to EP

  // --- DUT→EP: apply clock delay, per-bit data skew, valid/token delays ---
  assign #(CLK_WIRE_DELAY_NS   ) dut_up_clk_r_d   = dut_up_clk_r_raw;
  assign #(VALID_WIRE_DELAY_NS ) dut_up_valid_r_d  = dut_up_valid_r_raw;
  assign #(TOKEN_WIRE_DELAY_NS ) ep_dn_token_r_d   = ep_dn_token_r_raw;

  generate
    for (genvar i = 0; i < 8; i++) begin : dut_data_delay
      assign #(DATA_BASE_NS + i * DATA_SKEW_STEP_NS) dut_up_data_r_d[i]
             = dut_up_data_r_raw[i];
    end
  endgenerate

  // --- EP→DUT: symmetric delays ---
  assign #(CLK_WIRE_DELAY_NS   ) ep_up_clk_r_d    = ep_up_clk_r_raw;
  assign #(VALID_WIRE_DELAY_NS ) ep_up_valid_r_d   = ep_up_valid_r_raw;
  assign #(TOKEN_WIRE_DELAY_NS ) dut_dn_token_r_d  = dut_dn_token_r_raw;

  generate
    for (genvar j = 0; j < 8; j++) begin : ep_data_delay
      assign #(DATA_BASE_NS + j * DATA_SKEW_STEP_NS) ep_up_data_r_d[j]
             = ep_up_data_r_raw[j];
    end
  endgenerate

  // =========================================================================
  // DUT: cgra_io_axi4_top
  //   core_clk_i = core_clk (100 MHz)
  //   io_master_clk_i = io_clk (~103 MHz)  ← different!
  // =========================================================================
  cgra_io_axi4_top #(
    .ADDR_WIDTH         ( AW ),
    .DATA_WIDTH         ( DW ),
    .FLIT_WIDTH         ( FW ),
    .BYPASS_GEARBOX     ( 1  ),
    .BYPASS_TWOFER_FIFO ( 1  )
  ) dut (
    .clk_i                      ( core_clk                    ),
    .rst_i                      ( rst_i                       ),

    .fpga_axi_i_aw_addr         ( fpga_aw_addr                ),
    .fpga_axi_i_aw_prot         ( fpga_aw_prot                ),
    .fpga_axi_i_aw_valid        ( fpga_aw_valid               ),
    .fpga_axi_i_aw_ready        ( fpga_aw_ready               ),
    .fpga_axi_i_w_data          ( fpga_w_data                 ),
    .fpga_axi_i_w_strb          ( fpga_w_strb                 ),
    .fpga_axi_i_w_valid         ( fpga_w_valid                ),
    .fpga_axi_i_w_ready         ( fpga_w_ready                ),
    .fpga_axi_i_b_resp          ( fpga_b_resp                 ),
    .fpga_axi_i_b_valid         ( fpga_b_valid                ),
    .fpga_axi_i_b_ready         ( fpga_b_ready                ),
    .fpga_axi_i_ar_addr         ( fpga_ar_addr                ),
    .fpga_axi_i_ar_prot         ( fpga_ar_prot                ),
    .fpga_axi_i_ar_valid        ( fpga_ar_valid               ),
    .fpga_axi_i_ar_ready        ( fpga_ar_ready               ),
    .fpga_axi_i_r_data          ( fpga_r_data                 ),
    .fpga_axi_i_r_resp          ( fpga_r_resp                 ),
    .fpga_axi_i_r_valid         ( fpga_r_valid                ),
    .fpga_axi_i_r_ready         ( fpga_r_ready                ),

    .enq_valid_i_0              ( enq_valid_0                 ),
    .enq_valid_i_1              ( 1'b0                        ),
    .enq_valid_i_2              ( 1'b0                        ),
    .enq_valid_i_3              ( 1'b0                        ),
    .enq_ready_o                ( enq_ready                   ),
    .enq_tid_i                  ( enq_tid                     ),
    .enq_addr_i_0               ( enq_addr_0                  ),
    .enq_addr_i_1               ( '0                          ),
    .enq_addr_i_2               ( '0                          ),
    .enq_addr_i_3               ( '0                          ),
    .enq_data_i_0               ( enq_data_0                  ),
    .enq_data_i_1               ( '0                          ),
    .enq_data_i_2               ( '0                          ),
    .enq_data_i_3               ( '0                          ),
    .enq_op_i_0                 ( enq_op_0                    ),
    .enq_op_i_1                 ( 1'b0                        ),
    .enq_op_i_2                 ( 1'b0                        ),
    .enq_op_i_3                 ( 1'b0                        ),

    .rsp_data_ready_i           ( rsp_data_ready              ),
    .pop_o                      ( pop_out                     ),
    .rsp_valid_o                ( rsp_valid                   ),
    .rsp_tid_o                  ( rsp_tid                     ),
    .rsp_addr_o                 ( rsp_addr                    ),
    .rsp_data_o                 ( rsp_data                    ),

    // bsg_link upstream — uses io_clk (not core_clk)
    .io_master_clk_i            ( io_clk                      ),
    .upstream_io_link_reset_i   ( dut_upstream_io_link_reset  ),
    .async_token_reset_i        ( dut_async_token_reset       ),
    .token_clk_i                ( ep_dn_token_r_d             ),
    .upstream_io_clk_r_o        ( dut_up_clk_r_raw            ),
    .upstream_io_data_r_o       ( dut_up_data_r_raw           ),
    .upstream_io_valid_r_o      ( dut_up_valid_r_raw          ),

    // bsg_link downstream — receives delayed EP upstream signals
    .downstream_io_link_reset_i ( dut_downstream_io_link_reset ),
    .downstream_io_clk_i        ( ep_up_clk_r_d               ),
    .downstream_io_data_i       ( ep_up_data_r_d              ),
    .downstream_io_valid_i      ( ep_up_valid_r_d             ),
    .downstream_core_token_r_o  ( dut_dn_token_r_raw          ),

    .cgra_csr_req_o             ( csr_req                     ),
    .cgra_csr_resp_i            ( csr_resp                    )
  );

  // =========================================================================
  // FPGA endpoint: second top_level_io, back-to-back with DUT
  //   Also uses io_clk as its IO master clock.
  //   Receives DUT upstream output through the delay model.
  // =========================================================================
  logic        ep_tx_rvalid  = 1'b0;
  logic [DW-1:0] ep_tx_rdata  = '0;
  logic        ep_tx_rlast   = 1'b0;
  logic [1:0]  ep_tx_rresp   = '0;
  logic        ep_tx_rready;

  logic        ep_tx_bvalid  = 1'b0;
  logic [1:0]  ep_tx_bresp   = '0;
  logic        ep_tx_bready;

  logic        ep_rx_arvalid;
  logic [AW-1:0] ep_rx_araddr;
  logic        ep_rx_awvalid;
  logic [AW-1:0] ep_rx_awaddr;
  logic        ep_rx_wvalid;
  logic [DW-1:0] ep_rx_wdata;

  top_level_io #(
    .flit_width_p                    ( FW ),
    .addr_width_p                    ( AW ),
    .channel_width_p                 ( 8  ),
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
    .core_clk_i                 ( core_clk                    ),
    .reset_i                    ( rst_i                       ),

    // bsg_link upstream — EP→DUT, uses io_clk
    .io_master_clk_i            ( io_clk                      ),
    .upstream_io_link_reset_i   ( ep_upstream_io_link_reset   ),
    .async_token_reset_i        ( ep_async_token_reset        ),
    .token_clk_i                ( dut_dn_token_r_d            ),
    .upstream_io_clk_r_o        ( ep_up_clk_r_raw             ),
    .upstream_io_data_r_o       ( ep_up_data_r_raw            ),
    .upstream_io_valid_r_o      ( ep_up_valid_r_raw           ),

    // bsg_link downstream — receives DUT upstream output through delay model
    .downstream_io_link_reset_i ( ep_downstream_io_link_reset ),
    .downstream_io_clk_i        ( dut_up_clk_r_d              ),
    .downstream_io_data_i       ( dut_up_data_r_d             ),
    .downstream_io_valid_i      ( dut_up_valid_r_d            ),
    .downstream_core_token_r_o  ( ep_dn_token_r_raw           ),

    // TX: FPGA ep sends R/B responses back to chip
    .tx_awvalid_i   ( 1'b0          ),
    .tx_awready_o   (               ),
    .tx_awaddr_i    ( '0            ),
    .tx_awlen_i     ( '0            ),
    .tx_awsize_i    ( '0            ),
    .tx_awburst_i   ( '0            ),
    .tx_wvalid_i    ( 1'b0          ),
    .tx_wready_o    (               ),
    .tx_wdata_i     ( '0            ),
    .tx_wlast_i     ( 1'b0          ),
    .tx_arvalid_i   ( 1'b0          ),
    .tx_arready_o   (               ),
    .tx_araddr_i    ( '0            ),
    .tx_arlen_i     ( '0            ),
    .tx_arsize_i    ( '0            ),
    .tx_arburst_i   ( '0            ),
    .tx_rvalid_i    ( ep_tx_rvalid  ),
    .tx_rready_o    ( ep_tx_rready  ),
    .tx_rdata_i     ( ep_tx_rdata   ),
    .tx_rresp_i     ( ep_tx_rresp   ),
    .tx_rlast_i     ( ep_tx_rlast   ),
    .tx_bvalid_i    ( ep_tx_bvalid  ),
    .tx_bready_o    ( ep_tx_bready  ),
    .tx_bresp_i     ( ep_tx_bresp   ),

    // RX: decoded AW/W/AR requests from chip
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

  logic        ep_aw_pending  = 1'b0;
  logic [AW-1:0] ep_aw_addr_lat = '0;

  always_ff @(posedge core_clk) begin
    if (rst_i) begin
      ep_tx_rvalid  <= 1'b0;
      ep_tx_bvalid  <= 1'b0;
      ep_aw_pending <= 1'b0;
      foreach (fpga_sram[i]) fpga_sram[i] <= 16'(i + 16'hA000);
    end else begin
      if (ep_tx_rvalid && ep_tx_rready) ep_tx_rvalid <= 1'b0;
      if (ep_tx_bvalid && ep_tx_bready) ep_tx_bvalid <= 1'b0;

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

      if (ep_rx_awvalid && !ep_aw_pending) begin
        ep_aw_addr_lat <= ep_rx_awaddr;
        ep_aw_pending  <= 1'b1;
      end

      if (ep_rx_wvalid && ep_aw_pending && !ep_tx_bvalid) begin
        begin : wr_blk
          int idx;
          idx = int'((ep_aw_addr_lat - AW'(MEM_BASE)) >> 1);
          if (idx >= 0 && idx < MEM_WORDS)
            fpga_sram[idx] <= ep_rx_wdata[15:0];
        end
        ep_aw_pending <= 1'b0;
        ep_tx_bresp   <= 2'b00;
        ep_tx_bvalid  <= 1'b1;
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
  // Stimulus helpers (use core_clk for enqueue — same domain as mem_req_fifo)
  // =========================================================================
  task automatic cgra_load(input logic [15:0] addr);
    @(posedge core_clk); #1;
    enq_valid_0 = 1'b1;
    enq_addr_0  = addr;
    enq_data_0  = '0;
    enq_op_0    = 1'b0;
    while (!enq_ready) @(posedge core_clk);
    @(posedge core_clk); #1;
    enq_valid_0 = 1'b0;
  endtask

  task automatic cgra_store(input logic [15:0] addr, input logic [15:0] data);
    @(posedge core_clk); #1;
    enq_valid_0 = 1'b1;
    enq_addr_0  = addr;
    enq_data_0  = data;
    enq_op_0    = 1'b1;
    while (!enq_ready) @(posedge core_clk);
    @(posedge core_clk); #1;
    enq_valid_0 = 1'b0;
  endtask

  task automatic wait_rsp(output logic [15:0] data);
    @(posedge core_clk);
    while (!rsp_valid) @(posedge core_clk);
    data = rsp_data;
    @(posedge core_clk);
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

    // -- bsg_link reset sequence (same staged approach as RTL TB) --

    // Step 1: assert all resets
    rst_i                        = 1'b1;
    dut_upstream_io_link_reset   = 1'b1;
    dut_downstream_io_link_reset = 1'b1;
    ep_upstream_io_link_reset    = 1'b1;
    ep_downstream_io_link_reset  = 1'b1;
    dut_async_token_reset        = 1'b0;
    ep_async_token_reset         = 1'b0;
    repeat(4) @(posedge core_clk);

    // Step 2: toggle async_token_reset while io_link_resets are still high
    @(posedge core_clk); #1;
    dut_async_token_reset = 1'b1;
    ep_async_token_reset  = 1'b1;
    @(posedge core_clk); #1;
    dut_async_token_reset = 1'b0;
    ep_async_token_reset  = 1'b0;

    // Step 3: let clocks run (io_clk may be at a different phase from core_clk)
    repeat(8) @(posedge core_clk);

    // Step 4a: deassert upstream io_link_resets → ODDR clock outputs start
    @(posedge core_clk); #1;
    dut_upstream_io_link_reset = 1'b0;
    ep_upstream_io_link_reset  = 1'b0;

    // Step 4b: wait for ODDR PHY pipeline + wire delay to propagate
    // Use extra cycles here because io_clk ≠ core_clk and the forwarded
    // clock has an additional 2 ns board delay.
    repeat(12) @(posedge core_clk);

    // Step 4c: deassert downstream io_link_resets — forwarded clocks now valid
    @(posedge core_clk); #1;
    dut_downstream_io_link_reset = 1'b0;
    ep_downstream_io_link_reset  = 1'b0;

    // Step 5: deassert core reset
    repeat(4) @(posedge core_clk);
    @(posedge core_clk); #1;
    rst_i = 1'b0;
    repeat(10) @(posedge core_clk);

    // -----------------------------------------------------------------------
    $display("\n=== Skew/Drift stress test: core=%.1f ns half, io=%.1f ns half ===",
             CORE_CLK_HALF_NS, IO_CLK_HALF_NS);
    $display("    CLK wire delay=%.2f ns, data skew 0-%.2f ns, token delay=%.2f ns\n",
             CLK_WIRE_DELAY_NS,
             DATA_BASE_NS + 7 * DATA_SKEW_STEP_NS,
             TOKEN_WIRE_DELAY_NS);

    // -----------------------------------------------------------------------
    $display("--- T1: Single load (drifted clocks, skewed data bus) ---");
    begin
      logic [15:0] got_data;
      cgra_load(MEM_BASE);
      wait_rsp(got_data);
      check16(got_data, 16'hA000, "T1: load SRAM[0] through skewed DDR link");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T2: Single store then load (round-trip with drift) ---");
    begin
      cgra_store(MEM_BASE + 16'h0002, 16'hBEEF);
      repeat(100) @(posedge core_clk);
      cgra_load(MEM_BASE + 16'h0002);
      begin
        logic [15:0] got_data;
        wait_rsp(got_data);
        check16(got_data, 16'hBEEF, "T2: store-load round-trip");
      end
    end

    // -----------------------------------------------------------------------
    $display("\n--- T3: 8 back-to-back loads (exercises drift accumulation) ---");
    // 8 loads instead of 4: more transactions = more clock drift accumulated
    begin
      logic [15:0] got_data;
      logic [15:0] expected;
      for (int i = 0; i < 8; i++) begin
        cgra_load(MEM_BASE + 16'(i * 2));
        wait_rsp(got_data);
        // SRAM[1] was written by T2, rest are initial values
        expected = (i == 1) ? 16'hBEEF : 16'(16'hA000 + i);
        check16(got_data, expected,
                $sformatf("T3: back-to-back load SRAM[%0d]", i));
      end
    end

    // -----------------------------------------------------------------------
    $display("\n========================================");
    $display("  PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("  ALL TESTS PASSED!");
    $display("========================================\n");

    if (fail_cnt > 0) $stop;
    repeat(10) @(posedge core_clk);
    $finish;
  end

  // Debug monitor
  initial begin
    forever begin
      repeat(100) @(posedge core_clk);
      $display("[DBG t=%0t] enq_v=%b rdy=%b op=%b | rsp_v=%b | ep_rx_ar=%b aw=%b w=%b | ep_tx_r=%b b=%b",
               $time,
               enq_valid_0, enq_ready, enq_op_0,
               rsp_valid,
               ep_rx_arvalid, ep_rx_awvalid, ep_rx_wvalid,
               ep_tx_rvalid,  ep_tx_bvalid);
    end
  end

  // Watchdog — extended for drift accumulation over many transactions
  initial begin
    #200_000_000;
    $error("TIMEOUT: simulation exceeded 200 us");
    $finish;
  end

endmodule : tb_cgra_io_axi4_link_skew
