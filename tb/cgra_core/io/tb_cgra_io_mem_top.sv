// =============================================================================
// tb_cgra_io_mem_top.sv
//
// Integration testbench for cgra_io_mem_top.
//
// Full hierarchy under test:
//   cgra_io_mem_top
//     ├── io_rx_tx_adapter    (bsg_fifo-backed link ↔ flit converter)
//     ├── flit_axil_bridge    (LEN-framed flit ↔ AXI-Lite)
//     └── cgra_mem_system_16bit (crossbar + CSR bank + FPGA SRAM)
//
// ─── Address map (16-bit) ────────────────────────────────────────────────────
//   CSRs:     0x0000 – 0x000E  (8 × 16-bit regs, 2-byte stride)
//   FPGA mem: 0x0800 – 0x0FFE  (1024 × 16-bit words)
//
// ─── Flit protocol (flit_axil_bridge) ───────────────────────────────────────
//   Header: [15:13]=opcode  [12:0]=LEN (payload flits after header)
//   OP_AR = 0: payload = [addr, count]          LEN=2
//   OP_AW = 1: payload = [addr, data0, ...]     LEN = 1 + N_data
//   OP_R  = 2: payload = [status, data0, ...]   LEN = 1 + count
//   OP_B  = 3: payload = [status]               LEN=1
//   status flit: [1:0] = AXI RESP code (0=OKAY)
//
// ─── Test plan ──────────────────────────────────────────────────────────────
//   T1  — CGRA writes FPGA memory; FPGA reads back           (directed)
//   T2  — FPGA writes CSRs; CGRA reads end-to-end            (directed)
//   T3  — CGRA read-after-write round-trip through pipeline  (directed)
//   T4  — Multi-data-flit AW packet (N=3, same-address mode) (directed)
//   T5  — Multi-read AR packet (count=4, same-address reads) (directed)
//   T6  — Backpressure: link_tx_ready_i deasserted mid-rsp   (directed)
//   T7  — Stress: 32 consecutive writes then readback        (directed)
// =============================================================================

`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "axi_test.sv"

module tb_cgra_io_mem_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int unsigned AW          = 16;   // 16-bit addresses
    localparam int unsigned DW          = 16;
    localparam int unsigned LW          = 16;
    localparam time         TA          = 2ns;
    localparam time         TT          = 8ns;
    localparam int          CLK_HALF_NS = 5;    // 100 MHz

    localparam logic [AW-1:0] CSR_BASE = 16'h0000;
    localparam logic [AW-1:0] MEM_BASE = 16'h0800;

    localparam int unsigned MEM_MIN = 16'h0800;
    localparam int unsigned MEM_MAX = 16'h0FFE;   // 1024 words × 2 bytes − 2

    // Flit opcode constants (must match flit_axil_bridge)
    localparam logic [2:0] OP_AR = 3'd0;
    localparam logic [2:0] OP_AW = 3'd1;
    localparam logic [2:0] OP_R  = 3'd2;
    localparam logic [2:0] OP_B  = 3'd3;

    // =========================================================================
    // Clock / reset
    // =========================================================================
    bit   clk_i;
    logic rst_i = 1'b1;

    initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

    // =========================================================================
    // CGRA link-side signals
    // =========================================================================
    logic          link_rx_v;
    logic [LW-1:0] link_rx_data;
    logic          link_rx_ready;

    logic          link_tx_v;
    logic [LW-1:0] link_tx_data;
    logic          link_tx_ready;

    // =========================================================================
    // AXI-Lite interfaces
    // =========================================================================
    AXI_LITE_DV #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_dv (clk_i);
    AXI_LITE    #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_axi ();
    `AXI_LITE_ASSIGN(fpga_axi, fpga_dv)

    // =========================================================================
    // DUT: cgra_io_mem_top
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
    ) dut (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .link_rx_v_i     (link_rx_v),
        .link_rx_data_i  (link_rx_data),
        .link_rx_ready_o (link_rx_ready),
        .link_tx_v_o     (link_tx_v),
        .link_tx_data_o  (link_tx_data),
        .link_tx_ready_i (link_tx_ready),
        .fpga_axi_i_aw_addr  (fpga_axi.aw_addr),
        .fpga_axi_i_aw_prot  (fpga_axi.aw_prot),
        .fpga_axi_i_aw_valid (fpga_axi.aw_valid),
        .fpga_axi_i_aw_ready (fpga_axi.aw_ready),
        .fpga_axi_i_w_data   (fpga_axi.w_data),
        .fpga_axi_i_w_strb   (fpga_axi.w_strb),
        .fpga_axi_i_w_valid  (fpga_axi.w_valid),
        .fpga_axi_i_w_ready  (fpga_axi.w_ready),
        .fpga_axi_i_b_resp   (fpga_axi.b_resp),
        .fpga_axi_i_b_valid  (fpga_axi.b_valid),
        .fpga_axi_i_b_ready  (fpga_axi.b_ready),
        .fpga_axi_i_ar_addr  (fpga_axi.ar_addr),
        .fpga_axi_i_ar_prot  (fpga_axi.ar_prot),
        .fpga_axi_i_ar_valid (fpga_axi.ar_valid),
        .fpga_axi_i_ar_ready (fpga_axi.ar_ready),
        .fpga_axi_i_r_data   (fpga_axi.r_data),
        .fpga_axi_i_r_resp   (fpga_axi.r_resp),
        .fpga_axi_i_r_valid  (fpga_axi.r_valid),
        .fpga_axi_i_r_ready  (fpga_axi.r_ready)
    );

    // =========================================================================
    // FPGA AXI agent
    // =========================================================================
    typedef axi_test::axi_lite_rand_master #(
        .AW (AW), .DW (DW), .TA (TA), .TT (TT),
        .MIN_ADDR (MEM_MIN), .MAX_ADDR (MEM_MAX),
        .AX_MIN_WAIT_CYCLES(0), .AX_MAX_WAIT_CYCLES(2),
        .W_MIN_WAIT_CYCLES (0), .W_MAX_WAIT_CYCLES (1),
        .RESP_MIN_WAIT_CYCLES(0), .RESP_MAX_WAIT_CYCLES(2)
    ) rand_master_t;

    rand_master_t fpga_agent;

    // =========================================================================
    // Scoreboard
    // =========================================================================
    logic [DW-1:0] shadow [logic [AW-1:0]];

    task automatic shadow_write(
        input logic [AW-1:0]   addr,
        input logic [DW-1:0]   data,
        input logic [DW/8-1:0] strb = '1
    );
        logic [DW-1:0] prev;
        prev = shadow.exists(addr) ? shadow[addr] : '0;
        shadow[addr] = {strb[1] ? data[15:8] : prev[15:8],
                        strb[0] ? data[7:0]  : prev[7:0]};
    endtask

    int cyc, pass_cnt, fail_cnt;
    always @(posedge clk_i) cyc <= cyc + 1;

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

    task automatic fpga_write(
        input logic [AW-1:0]   addr,
        input logic [DW-1:0]   data,
        input logic [DW/8-1:0] strb = '1
    );
        axi_pkg::resp_t resp;
        fpga_agent.write(addr, axi_pkg::prot_t'(0), data, strb, resp);
        shadow_write(addr, data, strb);
    endtask

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
    // CGRA link-side primitives
    // =========================================================================

    // Send one 16-bit word onto the link (drives link_rx_v/data, waits for ready).
    task automatic send_link_word(input logic [LW-1:0] word);
        @(posedge clk_i); #1;
        link_rx_v    = 1'b1;
        link_rx_data = word;
        while (!link_rx_ready) @(posedge clk_i);
        @(posedge clk_i); #1;
        link_rx_v    = 1'b0;
        link_rx_data = '0;
    endtask

    // Receive one 16-bit word from the link (drives link_tx_ready, waits for valid).
    task automatic recv_link_word(output logic [LW-1:0] word);
        link_tx_ready = 1'b1;
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        word = link_tx_data;
        @(posedge clk_i); #1;
        link_tx_ready = 1'b0;
    endtask

    // =========================================================================
    // CGRA flit-protocol helpers (flit_axil_bridge packet format)
    // =========================================================================

    // Send a single AXI write: OP_AW header + addr flit + 1 data flit (LEN=2).
    // flit_axil_bridge always uses full wstrb; byte-lane control is not available
    // from the flit path.
    task automatic cgra_send_write(
        input logic [AW-1:0] addr,
        input logic [DW-1:0] data
    );
        send_link_word({OP_AW, 13'd2});  // LEN=2: addr + 1 data flit
        send_link_word(LW'(addr));
        send_link_word(data);
    endtask

    // Send an AXI write with N data flits to the same address (same-address mode).
    // The bridge issues N writes to addr; the last data value is the one that persists.
    task automatic cgra_send_write_n(
        input logic [AW-1:0] addr,
        input logic [DW-1:0] data_arr [],  // dynamic array, length = N
        input int             n
    );
        send_link_word({OP_AW, 13'(1 + n)});  // LEN = 1(addr) + N(data)
        send_link_word(LW'(addr));
        for (int i = 0; i < n; i++)
            send_link_word(data_arr[i]);
    endtask

    // Send an AXI read request: OP_AR header + addr flit + count flit (LEN=2).
    task automatic cgra_send_read(
        input logic [AW-1:0]  addr,
        input int unsigned     count = 1  // number of same-address reads
    );
        send_link_word({OP_AR, 13'd2});  // LEN always 2 for AR
        send_link_word(LW'(addr));
        send_link_word(LW'(count));
    endtask

    // Receive a write response (OP_B): header + status flit.
    task automatic cgra_recv_bresp(output logic [1:0] resp);
        logic [LW-1:0] hdr, stat;
        link_tx_ready = 1'b1;
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        hdr = link_tx_data;          // {OP_B, 13'd1}
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        stat = link_tx_data;         // {14'b0, bresp[1:0]}
        resp = stat[1:0];
        @(posedge clk_i);
        link_tx_ready = 1'b0;
    endtask

    // Receive a read response (OP_R) with count=1: header + status flit + 1 data flit.
    task automatic cgra_recv_rresp(
        output logic [DW-1:0] rdata,
        output logic [1:0]    resp
    );
        logic [LW-1:0] hdr, stat;
        link_tx_ready = 1'b1;
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        hdr   = link_tx_data;        // {OP_R, LEN}
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        stat  = link_tx_data;        // {14'b0, rresp[1:0]}
        resp  = stat[1:0];
        @(posedge clk_i);
        while (!link_tx_v) @(posedge clk_i);
        rdata = link_tx_data;
        @(posedge clk_i);
        link_tx_ready = 1'b0;
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        link_rx_v     = 1'b0;
        link_rx_data  = '0;
        link_tx_ready = 1'b0;

        fpga_agent = new(fpga_dv, "FPGA");
        fpga_agent.reset();
        pass_cnt = 0;
        fail_cnt = 0;
        cyc      = 0;

        rst_i = 1'b1;
        repeat (5) @(posedge clk_i);
        @(posedge clk_i); #1;
        rst_i = 1'b0;
        repeat (3) @(posedge clk_i);

        // =====================================================================
        $display("\n--- T1: CGRA writes FPGA memory; FPGA reads back ---");
        // =====================================================================
        begin
            logic [1:0] resp;

            cgra_send_write(mem_a(0), 16'hA5A5);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(0), 16'hA5A5);

            cgra_send_write(mem_a(1), 16'h5A5A);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(1), 16'h5A5A);

            fpga_read_check(mem_a(0), "T1: FPGA reads CGRA-written mem[0]");
            fpga_read_check(mem_a(1), "T1: FPGA reads CGRA-written mem[1]");
        end

        // =====================================================================
        $display("\n--- T2: FPGA writes CSRs; CGRA reads end-to-end ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;

            fpga_write(csr_a(0), 16'h1234);
            fpga_write(csr_a(4), 16'h5678);

            cgra_send_read(csr_a(0));
            cgra_recv_rresp(rdata, resp);
            check16(rdata, 16'h1234, "T2: CGRA reads CSR[0] via full pipeline");

            cgra_send_read(csr_a(4));
            cgra_recv_rresp(rdata, resp);
            check16(rdata, 16'h5678, "T2: CGRA reads CSR[4] via full pipeline");
        end

        // =====================================================================
        $display("\n--- T3: CGRA read-after-write round-trip ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;

            cgra_send_write(mem_a(50), 16'hDEAD);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(50), 16'hDEAD);

            cgra_send_read(mem_a(50));
            cgra_recv_rresp(rdata, resp);
            check16(rdata, 16'hDEAD, "T3: CGRA read-after-write mem[50]");
            check16({14'b0, resp}, 16'd0, "T3: OKAY response on read");
        end

        // =====================================================================
        $display("\n--- T4: Multi-data-flit AW packet (N=3, same-address mode) ---");
        // Same-address semantics: all 3 data flits write to the same address.
        // Bridge emits one OP_B after the final write completes.
        // Last data value wins.
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [DW-1:0] dvals [];
            dvals = new[3];
            dvals[0] = 16'hAAAA;
            dvals[1] = 16'hBBBB;
            dvals[2] = 16'hCCCC;   // last write — persists

            cgra_send_write_n(mem_a(10), dvals, 3);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(10), 16'hCCCC);   // last write wins
            check16({14'b0, resp}, 16'd0, "T4: OKAY bresp from multi-flit AW");

            // Verify last value persists
            cgra_send_read(mem_a(10));
            cgra_recv_rresp(rdata, resp);
            check16(rdata, 16'hCCCC, "T4: multi-flit AW last value persists");
        end

        // =====================================================================
        $display("\n--- T5: Multi-read AR packet (count=4, same address) ---");
        // Bridge issues 4 AXI reads to the same address and aggregates into
        // one OP_R response with 4 data flits.
        // =====================================================================
        begin
            logic [LW-1:0] hdr, stat, w0, w1, w2, w3;
            logic [1:0]    resp;

            // Write a known value first
            cgra_send_write(mem_a(20), 16'hF0F0);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(20), 16'hF0F0);

            cgra_send_read(mem_a(20), 4);

            // Manually receive OP_R with count=4: header + status + 4 data flits
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
            check16({14'b0, resp}, 16'd0, "T5: OKAY rresp from multi-read");
            check16(w0, 16'hF0F0, "T5: multi-read data[0]");
            check16(w1, 16'hF0F0, "T5: multi-read data[1]");
            check16(w2, 16'hF0F0, "T5: multi-read data[2]");
            check16(w3, 16'hF0F0, "T5: multi-read data[3]");
        end

        // =====================================================================
        $display("\n--- T6: Backpressure — link_tx_ready_i deasserted mid-response ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;

            cgra_send_write(mem_a(300), 16'hBEEF);
            cgra_recv_bresp(resp);
            shadow_write(mem_a(300), 16'hBEEF);

            cgra_send_read(mem_a(300));

            // Hold tx_ready low; wait for first response flit then stall 8 cycles.
            link_tx_ready = 1'b0;
            while (!link_tx_v) @(posedge clk_i);
            repeat (8) @(posedge clk_i);

            cgra_recv_rresp(rdata, resp);
            check16(rdata, 16'hBEEF, "T6: correct data after backpressure stall");
            check16({14'b0, resp}, 16'd0, "T6: OKAY resp after backpressure stall");
            $display("[PASS] T6: response received after link_tx backpressure");
            pass_cnt++;
        end

        // =====================================================================
        $display("\n--- T7: Stress — 32 consecutive writes then readback ---");
        // =====================================================================
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
                        $sformatf("T7: stress readback mem[%0d]", 400 + i));
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

endmodule
