// =============================================================================
// tb_cgra_io_axi4_top.sv
//
// Integration testbench for cgra_io_axi4_top.
//
// Hierarchy under test
// --------------------
//   cgra_io_axi4_top
//     ├── io_rx_tx_adapter    (link ↔ flit FIFO converter)
//     ├── flit_axil_bridge    (LEN-framed flit ↔ AXI-Lite → AXI4 promotion)
//     └── axi4_full_crossbar  (4→2 full AXI4 crossbar)
//
// Behavioral slaves  (outside DUT, connected to crossbar master ports)
//   fpga_mem : 1024 × 16-bit SRAM   0x0800 – 0x0FFE
//   cgra_csr :    8 × 16-bit regs   0x0000 – 0x000E
//
// Address map  (16-bit, matches axi4_full_crossbar)
// ---------
//   CSRs     : 0x0000 – 0x00FF  (8 regs × 16 b, 2-byte stride)
//   FPGA mem : 0x0800 – 0x0FFF  (1024 × 16-bit words)
//
// Flit protocol  (flit_axil_bridge)
// ----------
//   Header : [15:13]=opcode  [12:0]=LEN (payload flits after header)
//   OP_AR=0 : payload = [addr, count]        LEN=2
//   OP_AW=1 : payload = [addr, data0, ...]   LEN = 1 + N
//   OP_R =2 : payload = [status, data0, ...] LEN = 1 + count
//   OP_B =3 : payload = [status]             LEN=1
//
// Test plan  (mirrors tb_cgra_io_mem_top, adapted for full AXI4 path)
// ----------
//   T1 : CGRA writes FPGA SRAM; FPGA reads back
//   T2 : FPGA writes CSRs; CGRA reads end-to-end
//   T3 : CGRA read-after-write round-trip through full pipeline
//   T4 : Multi-data-flit AW packet (N=3, same-address mode)
//   T5 : Multi-read AR packet (count=4, same address)
//   T6 : Backpressure – link_tx_ready_i deasserted mid-response
//   T7 : Stress – 32 consecutive CGRA writes then readback
// =============================================================================

`timescale 1ns/1ps

`include "dice_define.vh"

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif
`include "axi/assign.svh"

// axi_test.sv must be on the include path (already in axi/src/)
`include "axi_test.sv"

module tb_cgra_io_axi4_top;

  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import dice_pkg::*;
  import DE_pkg::*;

  // -------------------------------------------------------------------------
  // Parameters
  // -------------------------------------------------------------------------
  localparam int AW           = 16;
  localparam int DW           = 16;
  localparam int LW           = 16;
  localparam time TA          = 2ns;
  localparam time TT          = 8ns;
  localparam int  CLK_HALF_NS = 5;    // 100 MHz

  localparam logic [AW-1:0] CSR_BASE = 16'h0000;
  localparam logic [AW-1:0] MEM_BASE = 16'h0800;

  localparam int MEM_WORDS   = 1024;
  localparam int CSR_NUM_REG = 8;

  // flit opcodes (must match flit_axil_bridge)
  localparam logic [2:0] OP_AR = 3'd0;
  localparam logic [2:0] OP_AW = 3'd1;
  localparam logic [2:0] OP_R  = 3'd2;
  localparam logic [2:0] OP_B  = 3'd3;

  // -------------------------------------------------------------------------
  // Clock / reset  (active-high)
  // -------------------------------------------------------------------------
  bit   clk_i;
  logic rst_i = 1'b1;

  initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

  // -------------------------------------------------------------------------
  // CGRA link-side signals
  // -------------------------------------------------------------------------
  logic          link_rx_v;
  logic [LW-1:0] link_rx_data;
  logic          link_rx_ready;

  logic          link_tx_v;
  logic [LW-1:0] link_tx_data;
  logic          link_tx_ready;

  // -------------------------------------------------------------------------
  // FPGA AXI-Lite agent  (flat-pin DV interface, same as original tb)
  // -------------------------------------------------------------------------
  AXI_LITE_DV #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_dv (clk_i);
  AXI_LITE    #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_axi ();
  `AXI_LITE_ASSIGN(fpga_axi, fpga_dv)

  // -------------------------------------------------------------------------
  // mem_req_fifo enqueue / response signals
  // -------------------------------------------------------------------------
  logic                                                              enq_valid;
  logic                                                              enq_ready;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                enq_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                      enq_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                   enq_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] enq_address_map;
  logic [15:0]                                                       enq_addr;
  logic [15:0]                                                       enq_data;
  logic                                                              enq_write_en;

  logic                                                              rsp_valid;
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                rsp_base_tid;
  logic [TID_BITMAP_WIDTH-1:0]                                      rsp_tid_bitmap;
  logic [DICE_REG_ADDR_WIDTH-1:0]                                   rsp_ld_dest_reg;
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0] rsp_address_map;
  logic [(CACHE_LINE_SIZE*8)-1:0]                                   rsp_data;

  // -------------------------------------------------------------------------
  // AXI4 slave port signals  (crossbar master ports → behavioral slaves)
  // -------------------------------------------------------------------------
  mst_req_t  fpga_mem_req,  cgra_csr_req;
  mst_resp_t fpga_mem_resp, cgra_csr_resp;

  // -------------------------------------------------------------------------
  // DUT: cgra_io_axi4_top
  // -------------------------------------------------------------------------
  cgra_io_axi4_top #(
    .ADDR_WIDTH   ( AW ),
    .DATA_WIDTH   ( DW ),
    .FLIT_WIDTH   ( 16 ),
    .LINK_WIDTH   ( LW ),
    .RX_FIFO_ELS  ( 16 ),
    .TX_FIFO_ELS  ( 16 )
  ) dut (
    .clk_i                ( clk_i           ),
    .rst_i                ( rst_i           ),

    .link_rx_v_i          ( link_rx_v       ),
    .link_rx_data_i       ( link_rx_data    ),
    .link_rx_ready_o      ( link_rx_ready   ),
    .link_tx_v_o          ( link_tx_v       ),
    .link_tx_data_o       ( link_tx_data    ),
    .link_tx_ready_i      ( link_tx_ready   ),

    .fpga_axi_i_aw_addr   ( fpga_axi.aw_addr  ),
    .fpga_axi_i_aw_prot   ( fpga_axi.aw_prot  ),
    .fpga_axi_i_aw_valid  ( fpga_axi.aw_valid ),
    .fpga_axi_i_aw_ready  ( fpga_axi.aw_ready ),
    .fpga_axi_i_w_data    ( fpga_axi.w_data   ),
    .fpga_axi_i_w_strb    ( fpga_axi.w_strb   ),
    .fpga_axi_i_w_valid   ( fpga_axi.w_valid  ),
    .fpga_axi_i_w_ready   ( fpga_axi.w_ready  ),
    .fpga_axi_i_b_resp    ( fpga_axi.b_resp   ),
    .fpga_axi_i_b_valid   ( fpga_axi.b_valid  ),
    .fpga_axi_i_b_ready   ( fpga_axi.b_ready  ),
    .fpga_axi_i_ar_addr   ( fpga_axi.ar_addr  ),
    .fpga_axi_i_ar_prot   ( fpga_axi.ar_prot  ),
    .fpga_axi_i_ar_valid  ( fpga_axi.ar_valid ),
    .fpga_axi_i_ar_ready  ( fpga_axi.ar_ready ),
    .fpga_axi_i_r_data    ( fpga_axi.r_data   ),
    .fpga_axi_i_r_resp    ( fpga_axi.r_resp   ),
    .fpga_axi_i_r_valid   ( fpga_axi.r_valid  ),
    .fpga_axi_i_r_ready   ( fpga_axi.r_ready  ),

    .enq_valid_i          ( enq_valid         ),
    .enq_ready_o          ( enq_ready         ),
    .enq_base_tid_i       ( enq_base_tid      ),
    .enq_tid_bitmap_i     ( enq_tid_bitmap    ),
    .enq_ld_dest_reg_i    ( enq_ld_dest_reg   ),
    .enq_address_map_i    ( enq_address_map   ),
    .enq_addr_i           ( enq_addr          ),
    .enq_data_i           ( enq_data          ),
    .enq_write_en_i       ( enq_write_en      ),

    .rsp_valid_o          ( rsp_valid         ),
    .rsp_base_tid_o       ( rsp_base_tid      ),
    .rsp_tid_bitmap_o     ( rsp_tid_bitmap    ),
    .rsp_ld_dest_reg_o    ( rsp_ld_dest_reg   ),
    .rsp_address_map_o    ( rsp_address_map   ),
    .rsp_data_o           ( rsp_data          ),

    .fpga_mem_req_o       ( fpga_mem_req    ),
    .fpga_mem_resp_i      ( fpga_mem_resp   ),
    .cgra_csr_req_o       ( cgra_csr_req    ),
    .cgra_csr_resp_i      ( cgra_csr_resp   )
  );

  // =========================================================================
  // Behavioral slave – FPGA SRAM  (mst port [0])
  // =========================================================================
  logic [15:0] sram [0:MEM_WORDS-1];

  typedef enum logic [2:0] {
    MEM_IDLE, MEM_W_WAIT, MEM_B_RESP, MEM_R_BEAT
  } mem_st_t;
  mem_st_t mem_st;

  logic [MstIdWidth-1:0] mem_aw_id, mem_ar_id;
  logic [15:0]           mem_aw_addr, mem_ar_addr;
  logic [7:0]            mem_ar_len;
  logic [7:0]            mem_beat_cnt;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      foreach (sram[i]) sram[i] <= '0;
      mem_st        <= MEM_IDLE;
      fpga_mem_resp <= '0;
    end else begin
      fpga_mem_resp.aw_ready <= 1'b0;
      fpga_mem_resp.w_ready  <= 1'b0;
      fpga_mem_resp.b_valid  <= 1'b0;
      fpga_mem_resp.ar_ready <= 1'b0;
      fpga_mem_resp.r_valid  <= 1'b0;

      unique case (mem_st)
        MEM_IDLE: begin
          if (fpga_mem_req.aw_valid) begin
            fpga_mem_resp.aw_ready <= 1'b1;
            mem_aw_addr            <= fpga_mem_req.aw.addr;
            mem_aw_id              <= fpga_mem_req.aw.id;
            mem_beat_cnt           <= '0;
            mem_st                 <= MEM_W_WAIT;  // always wait for W beats
          end else if (fpga_mem_req.ar_valid) begin
            fpga_mem_resp.ar_ready <= 1'b1;
            mem_ar_addr            <= fpga_mem_req.ar.addr;
            mem_ar_id              <= fpga_mem_req.ar.id;
            mem_ar_len             <= fpga_mem_req.ar.len;
            mem_beat_cnt           <= '0;
            mem_st                 <= MEM_R_BEAT;
          end
        end
        MEM_W_WAIT: begin
          fpga_mem_resp.w_ready <= 1'b1;
          // Handshake fires only when BOTH w_valid and (registered) w_ready are high
          if (fpga_mem_req.w_valid && fpga_mem_resp.w_ready) begin
            automatic int wa = int'((mem_aw_addr - MEM_BASE) >> 1) + int'(mem_beat_cnt);
            if (wa >= 0 && wa < MEM_WORDS) begin
              if (fpga_mem_req.w.strb[0]) sram[wa][ 7:0] <= fpga_mem_req.w.data[ 7:0];
              if (fpga_mem_req.w.strb[1]) sram[wa][15:8] <= fpga_mem_req.w.data[15:8];
            end
            if (fpga_mem_req.w.last) mem_st <= MEM_B_RESP;
            else mem_beat_cnt <= mem_beat_cnt + 8'd1;
          end
        end
        MEM_B_RESP: begin
          fpga_mem_resp.b_valid <= 1'b1;
          fpga_mem_resp.b.id    <= mem_aw_id;
          fpga_mem_resp.b.resp  <= RESP_OKAY;
          fpga_mem_resp.b.user  <= '0;
          if (fpga_mem_req.b_ready) mem_st <= MEM_IDLE;
        end
        MEM_R_BEAT: begin
          fpga_mem_resp.r_valid <= 1'b1;
          begin
            automatic int ra = int'((mem_ar_addr - MEM_BASE) >> 1) + int'(mem_beat_cnt);
            fpga_mem_resp.r.data <= (ra >= 0 && ra < MEM_WORDS) ? sram[ra] : 16'hDEAD;
          end
          fpga_mem_resp.r.id   <= mem_ar_id;
          fpga_mem_resp.r.resp <= RESP_OKAY;
          fpga_mem_resp.r.user <= '0;
          fpga_mem_resp.r.last <= (mem_beat_cnt == mem_ar_len);
          if (fpga_mem_req.r_ready) begin
            if (mem_beat_cnt == mem_ar_len) mem_st <= MEM_IDLE;
            else mem_beat_cnt <= mem_beat_cnt + 1;
          end
        end
        default: mem_st <= MEM_IDLE;
      endcase
    end
  end

  // =========================================================================
  // Behavioral slave – CGRA CSR bank  (mst port [1])
  // =========================================================================
  logic [15:0] csr_regs [0:CSR_NUM_REG-1];

  typedef enum logic [1:0] {
    CSR_IDLE, CSR_W_WAIT, CSR_B_RESP, CSR_R_RESP
  } csr_st_t;
  csr_st_t csr_st;

  logic [MstIdWidth-1:0] csr_aw_id, csr_ar_id;
  logic [15:0]           csr_aw_addr, csr_ar_addr;

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      foreach (csr_regs[i]) csr_regs[i] <= '0;
      csr_st        <= CSR_IDLE;
      cgra_csr_resp <= '0;
    end else begin
      cgra_csr_resp.aw_ready <= 1'b0;
      cgra_csr_resp.w_ready  <= 1'b0;
      cgra_csr_resp.b_valid  <= 1'b0;
      cgra_csr_resp.ar_ready <= 1'b0;
      cgra_csr_resp.r_valid  <= 1'b0;

      unique case (csr_st)
        CSR_IDLE: begin
          if (cgra_csr_req.aw_valid) begin
            cgra_csr_resp.aw_ready <= 1'b1;
            csr_aw_addr            <= cgra_csr_req.aw.addr;
            csr_aw_id              <= cgra_csr_req.aw.id;
            csr_st                 <= CSR_W_WAIT;  // always wait for W
          end else if (cgra_csr_req.ar_valid) begin
            cgra_csr_resp.ar_ready <= 1'b1;
            csr_ar_addr            <= cgra_csr_req.ar.addr;
            csr_ar_id              <= cgra_csr_req.ar.id;
            csr_st                 <= CSR_R_RESP;
          end
        end
        CSR_W_WAIT: begin
          cgra_csr_resp.w_ready <= 1'b1;
          if (cgra_csr_req.w_valid) begin
            automatic int ci = int'((csr_aw_addr - CSR_BASE) >> 1);
            if (ci >= 0 && ci < CSR_NUM_REG) begin
              if (cgra_csr_req.w.strb[0]) csr_regs[ci][ 7:0] <= cgra_csr_req.w.data[ 7:0];
              if (cgra_csr_req.w.strb[1]) csr_regs[ci][15:8] <= cgra_csr_req.w.data[15:8];
            end
            csr_st <= CSR_B_RESP;
          end
        end
        CSR_B_RESP: begin
          cgra_csr_resp.b_valid <= 1'b1;
          cgra_csr_resp.b.id    <= csr_aw_id;
          cgra_csr_resp.b.resp  <= RESP_OKAY;
          cgra_csr_resp.b.user  <= '0;
          if (cgra_csr_req.b_ready) csr_st <= CSR_IDLE;
        end
        CSR_R_RESP: begin
          cgra_csr_resp.r_valid <= 1'b1;
          begin
            automatic int ci = int'((csr_ar_addr - CSR_BASE) >> 1);
            cgra_csr_resp.r.data <= (ci >= 0 && ci < CSR_NUM_REG) ?
                                    csr_regs[ci] : 16'hDEAD;
          end
          cgra_csr_resp.r.id   <= csr_ar_id;
          cgra_csr_resp.r.resp <= RESP_OKAY;
          cgra_csr_resp.r.user <= '0;
          cgra_csr_resp.r.last <= 1'b1;
          if (cgra_csr_req.r_ready) csr_st <= CSR_IDLE;
        end
        default: csr_st <= CSR_IDLE;
      endcase
    end
  end

  // =========================================================================
  // FPGA AXI-Lite agent  (same as tb_cgra_io_mem_top)
  // =========================================================================
  typedef axi_test::axi_lite_rand_master #(
    .AW(AW), .DW(DW), .TA(TA), .TT(TT),
    .MIN_ADDR(16'h0800), .MAX_ADDR(16'h0FFE),
    .AX_MIN_WAIT_CYCLES(0), .AX_MAX_WAIT_CYCLES(2),
    .W_MIN_WAIT_CYCLES (0), .W_MAX_WAIT_CYCLES (1),
    .RESP_MIN_WAIT_CYCLES(0), .RESP_MAX_WAIT_CYCLES(2)
  ) rand_master_t;

  rand_master_t fpga_agent;

  // =========================================================================
  // Scoreboard  (shadow memory for verification)
  // =========================================================================
  logic [DW-1:0] shadow [logic [AW-1:0]];

  task automatic shadow_write(
    input logic [AW-1:0]   addr,
    input logic [DW-1:0]   data,
    input logic [DW/8-1:0] strb = '1
  );
    logic [DW-1:0] prev;
    prev         = shadow.exists(addr) ? shadow[addr] : '0;
    shadow[addr] = {strb[1] ? data[15:8] : prev[15:8],
                    strb[0] ? data[ 7:0] : prev[ 7:0]};
  endtask

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

  function automatic logic [AW-1:0] csr_a(int i);
    return CSR_BASE + AW'(i * 2);
  endfunction
  function automatic logic [AW-1:0] mem_a(int i);
    return MEM_BASE + AW'(i * 2);
  endfunction

  // FPGA write + scoreboard update
  task automatic fpga_write(
    input logic [AW-1:0]   addr,
    input logic [DW-1:0]   data,
    input logic [DW/8-1:0] strb = '1
  );
    axi_pkg::resp_t resp;
    fpga_agent.write(addr, axi_pkg::prot_t'(0), data, strb, resp);
    shadow_write(addr, data, strb);
  endtask

  // FPGA read + scoreboard check
  task automatic fpga_read_check(
    input logic [AW-1:0] addr,
    input string         msg
  );
    logic [DW-1:0]  got;
    axi_pkg::resp_t resp;
    fpga_agent.read(addr, axi_pkg::prot_t'(0), got, resp);
    check16(got, shadow.exists(addr) ? shadow[addr] : '0, msg);
  endtask

  // =========================================================================
  // CGRA link-side helpers  (identical to tb_cgra_io_mem_top)
  // =========================================================================

  task automatic send_link_word(input logic [LW-1:0] word);
    @(posedge clk_i); #1;
    link_rx_v    = 1'b1;
    link_rx_data = word;
    while (!link_rx_ready) @(posedge clk_i);
    @(posedge clk_i); #1;
    link_rx_v    = 1'b0;
    link_rx_data = '0;
  endtask

  task automatic recv_link_word(output logic [LW-1:0] word);
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    word = link_tx_data;
    @(posedge clk_i); #1;
    link_tx_ready = 1'b0;
  endtask

  // =========================================================================
  // CGRA flit-protocol helpers  (identical to tb_cgra_io_mem_top)
  // =========================================================================

  task automatic cgra_send_write(
    input logic [AW-1:0] addr,
    input logic [DW-1:0] data
  );
    send_link_word({OP_AW, 13'd2});
    send_link_word(LW'(addr));
    send_link_word(data);
  endtask

  task automatic cgra_send_write_n(
    input logic [AW-1:0] addr,
    input logic [DW-1:0] data_arr [],
    input int             n
  );
    send_link_word({OP_AW, 13'(1 + n)});
    send_link_word(LW'(addr));
    for (int i = 0; i < n; i++)
      send_link_word(data_arr[i]);
  endtask

  task automatic cgra_send_read(
    input logic [AW-1:0]  addr,
    input int unsigned     count = 1
  );
    send_link_word({OP_AR, 13'd2});
    send_link_word(LW'(addr));
    send_link_word(LW'(count));
  endtask

  task automatic cgra_recv_bresp(output logic [1:0] resp);
    logic [LW-1:0] hdr, stat;
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    hdr = link_tx_data;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    stat = link_tx_data;
    resp = stat[1:0];
    @(posedge clk_i);
    link_tx_ready = 1'b0;
  endtask

  task automatic cgra_recv_rresp(
    output logic [DW-1:0] rdata,
    output logic [1:0]    resp
  );
    logic [LW-1:0] hdr, stat;
    link_tx_ready = 1'b1;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    hdr  = link_tx_data;
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    stat = link_tx_data;
    resp = stat[1:0];
    @(posedge clk_i);
    while (!link_tx_v) @(posedge clk_i);
    rdata = link_tx_data;
    @(posedge clk_i);
    link_tx_ready = 1'b0;
  endtask

  // =========================================================================
  // Stimulus  (same test cases as tb_cgra_io_mem_top)
  // =========================================================================
  initial begin
    link_rx_v     = 1'b0;
    link_rx_data  = '0;
    link_tx_ready = 1'b0;

    enq_valid       = 1'b0;
    enq_base_tid    = '0;
    enq_tid_bitmap  = '0;
    enq_ld_dest_reg = '0;
    enq_address_map = '0;
    enq_addr        = '0;
    enq_data        = '0;
    enq_write_en    = 1'b0;

    fpga_agent = new(fpga_dv, "FPGA");
    fpga_agent.reset();
    pass_cnt = 0;
    fail_cnt = 0;

    rst_i = 1'b1;
    repeat(5) @(posedge clk_i);
    @(posedge clk_i); #1;
    rst_i = 1'b0;
    repeat(3) @(posedge clk_i);

    // -----------------------------------------------------------------------
    $display("\n--- T1: CGRA writes FPGA SRAM; FPGA reads back ---");
    begin
      logic [1:0] resp;
      cgra_send_write(mem_a(0), 16'hA5A5);
      cgra_recv_bresp(resp);
      shadow_write(mem_a(0), 16'hA5A5);

      cgra_send_write(mem_a(1), 16'h5A5A);
      cgra_recv_bresp(resp);
      shadow_write(mem_a(1), 16'h5A5A);

      fpga_read_check(mem_a(0), "T1: FPGA reads CGRA-written SRAM[0]");
      fpga_read_check(mem_a(1), "T1: FPGA reads CGRA-written SRAM[1]");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T2: FPGA writes CSRs; CGRA reads end-to-end ---");
    begin
      logic [DW-1:0] rdata;
      logic [1:0]    resp;

      fpga_write(csr_a(0), 16'h1234);
      fpga_write(csr_a(4), 16'h5678);

      cgra_send_read(csr_a(0));
      cgra_recv_rresp(rdata, resp);
      check16(rdata, 16'h1234, "T2: CGRA reads CSR[0]");

      cgra_send_read(csr_a(4));
      cgra_recv_rresp(rdata, resp);
      check16(rdata, 16'h5678, "T2: CGRA reads CSR[4]");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T3: CGRA read-after-write round-trip ---");
    begin
      logic [DW-1:0] rdata;
      logic [1:0]    resp;

      cgra_send_write(mem_a(50), 16'hDEAD);
      cgra_recv_bresp(resp);
      shadow_write(mem_a(50), 16'hDEAD);

      cgra_send_read(mem_a(50));
      cgra_recv_rresp(rdata, resp);
      check16(rdata, 16'hDEAD, "T3: CGRA read-after-write SRAM[50]");
      check16({14'b0, resp}, 16'd0, "T3: OKAY response on read");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T4: Multi-data-flit AW packet (N=3, same-address) ---");
    begin
      logic [DW-1:0] rdata;
      logic [1:0]    resp;
      logic [DW-1:0] dvals [];
      dvals    = new[3];
      dvals[0] = 16'hAAAA;
      dvals[1] = 16'hBBBB;
      dvals[2] = 16'hCCCC;

      // Bridge sends one INCR burst (AWLEN=2): beats go to mem_a(10), (11), (12)
      cgra_send_write_n(mem_a(10), dvals, 3);
      cgra_recv_bresp(resp);
      shadow_write(mem_a(10), 16'hAAAA);
      shadow_write(mem_a(11), 16'hBBBB);
      shadow_write(mem_a(12), 16'hCCCC);
      check16({14'b0, resp}, 16'd0, "T4: OKAY bresp from multi-flit AW");

      cgra_send_read(mem_a(12));
      cgra_recv_rresp(rdata, resp);
      check16(rdata, 16'hCCCC, "T4: burst last beat at mem_a(12)");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T5: Multi-read AR packet (count=4) ---");
    begin
      logic [LW-1:0] hdr, stat, w0, w1, w2, w3;
      logic [1:0]    resp;

      // 4-beat INCR burst read: addresses mem_a(20..23); write all first
      for (int i = 0; i < 4; i++) begin
        cgra_send_write(mem_a(20 + i), 16'hF0F0);
        cgra_recv_bresp(resp);
        shadow_write(mem_a(20 + i), 16'hF0F0);
      end

      cgra_send_read(mem_a(20), 4);

      link_tx_ready = 1'b1;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); hdr  = link_tx_data;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); stat = link_tx_data;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); w0   = link_tx_data;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); w1   = link_tx_data;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); w2   = link_tx_data;
      @(posedge clk_i);
      while (!link_tx_v) @(posedge clk_i); w3   = link_tx_data;
      @(posedge clk_i);
      link_tx_ready = 1'b0;

      resp = stat[1:0];
      check16({14'b0, resp}, 16'd0,   "T5: OKAY from multi-read");
      check16(w0, 16'hF0F0, "T5: multi-read data[0]");
      check16(w1, 16'hF0F0, "T5: multi-read data[1]");
      check16(w2, 16'hF0F0, "T5: multi-read data[2]");
      check16(w3, 16'hF0F0, "T5: multi-read data[3]");
    end

    // -----------------------------------------------------------------------
    $display("\n--- T6: Backpressure – link_tx_ready deasserted mid-response ---");
    begin
      logic [DW-1:0] rdata;
      logic [1:0]    resp;

      cgra_send_write(mem_a(300), 16'hBEEF);
      cgra_recv_bresp(resp);
      shadow_write(mem_a(300), 16'hBEEF);

      cgra_send_read(mem_a(300));

      link_tx_ready = 1'b0;
      while (!link_tx_v) @(posedge clk_i);
      repeat(8) @(posedge clk_i);

      cgra_recv_rresp(rdata, resp);
      check16(rdata, 16'hBEEF, "T6: correct data after backpressure stall");
      check16({14'b0, resp}, 16'd0, "T6: OKAY after backpressure stall");
      $display("[PASS] T6: response received after link_tx backpressure");
      pass_cnt++;
    end

    // -----------------------------------------------------------------------
    $display("\n--- T7: Stress – 32 CGRA writes then readback ---");
    begin
      logic [DW-1:0] rdata;
      logic [1:0]    resp;

      for (int i = 0; i < 32; i++) begin
        cgra_send_write(mem_a(400 + i), DW'(16'hE000 + i));
        cgra_recv_bresp(resp);
        shadow_write(mem_a(400 + i), DW'(16'hE000 + i));
      end
      for (int i = 0; i < 32; i++) begin
        cgra_send_read(mem_a(400 + i));
        cgra_recv_rresp(rdata, resp);
        check16(rdata, shadow[mem_a(400 + i)],
                $sformatf("T7: stress readback SRAM[%0d]", 400 + i));
      end
    end

    // -----------------------------------------------------------------------
    $display("\n--- T8: mem_req_fifo load via mfetch port ---");
    begin
      // Pre-load a value into SRAM via the FPGA AXI path
      fpga_write(mem_a(100), 16'hCAFE);
      shadow_write(mem_a(100), 16'hCAFE);

      // Enqueue a load request (thread 0, address mem_a(100))
      @(posedge clk_i); #1;
      enq_valid       = 1'b1;
      enq_base_tid    = '0;
      enq_tid_bitmap  = 8'b0000_0001;   // thread slot 0
      enq_ld_dest_reg = '0;
      enq_address_map = '0;
      enq_addr        = mem_a(100);
      enq_data        = '0;
      enq_write_en    = 1'b0;
      while (!enq_ready) @(posedge clk_i);
      @(posedge clk_i); #1;
      enq_valid = 1'b0;

      // Wait for rsp_valid to pulse
      while (!rsp_valid) @(posedge clk_i);
      // slot = lowest set bit of tid_bitmap = 0, so rsp_data[15:0]
      check16(rsp_data[15:0], 16'hCAFE, "T8: mfetch load returns correct data");
      check16({{(16-TID_BITMAP_WIDTH){1'b0}}, rsp_tid_bitmap}, 16'h0001, "T8: tid_bitmap passthrough");
      @(posedge clk_i);
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

  // Watchdog
  initial begin
    #500_000_000;
    $error("TIMEOUT: simulation exceeded 500 us");
    $finish;
  end

endmodule : tb_cgra_io_axi4_top
