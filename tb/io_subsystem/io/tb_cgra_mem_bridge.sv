// =============================================================================
// tb_cgra_mem_bridge.sv
//
// Unit testbench for cgra_mem_bridge + cgra_mem_system_16bit.
//
// The bridge is the DUT.  The testbench acts as both:
//   - the CGRA master: drives 4-flit request packets on rx_v_i / rx_data_i
//     and receives 2-flit response packets on tx_v_o / tx_data_o.
//   - the FPGA AXI master: uses axi_test::axi_lite_rand_master / directed
//     writes to the FPGA AXI-Lite port.
//
// cgra_mem_system_16bit is instantiated as the downstream slave.
//
// ─── Address map (16-bit) ────────────────────────────────────────────────────
//   CSRs:     0x0000 – 0x000E  (8 × 16-bit regs, 2-byte stride)
//   FPGA mem: 0x0800 – 0x0FFE  (1024 × 16-bit words)
//
// ─── Test plan ──────────────────────────────────────────────────────────────
//   T1  — CGRA writes to FPGA memory, reads back via CGRA
//   T2  — FPGA master writes CSRs; CGRA reads them back via bridge
//   T3  — Byte strobe: CGRA partial write + read-back
//   T4  — Tag echo: correct tag returned across all 32 tag values
//   T5  — Interleaved CGRA read + FPGA write to same address
//   T6  — Back-to-back CGRA transactions (no idle gaps)
// =============================================================================

`include "axi/typedef.svh"
`include "axi/assign.svh"
`include "axi_test.sv"

module tb_cgra_mem_bridge;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int unsigned AW          = 16;   // 16-bit addresses
    localparam int unsigned DW          = 16;
    localparam int unsigned FW          = 16;
    localparam time         TA          = 2ns;
    localparam time         TT          = 8ns;
    localparam int          CLK_HALF_NS = 5;    // 100 MHz

    localparam logic [AW-1:0] CSR_BASE = 16'h0000;
    localparam logic [AW-1:0] MEM_BASE = 16'h0800;

    localparam int unsigned CSR_MIN = 16'h0000;
    localparam int unsigned CSR_MAX = 16'h000E;   // 8 regs × 2 bytes − 2
    localparam int unsigned MEM_MIN = 16'h0800;
    localparam int unsigned MEM_MAX = 16'h0FFE;   // 1024 words × 2 bytes − 2

    // =========================================================================
    // Clock / reset
    // =========================================================================
    bit   clk_i;
    logic rst_i = 1'b1;

    initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

    // =========================================================================
    // AXI-Lite DV interface for FPGA master
    // =========================================================================
    AXI_LITE_DV #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_dv (clk_i);
    AXI_LITE    #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_axi ();
    `AXI_LITE_ASSIGN(fpga_axi, fpga_dv)

    // Unused DMA ports — driven idle
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) bs_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) md_axi ();

    // AXI-Lite wire for bridge → mem_system data_fetch port
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) cgra_axi ();

    // =========================================================================
    // Flit stimulus signals
    // =========================================================================
    logic          rx_v;
    logic [FW-1:0] rx_data;
    logic          rx_ready;
    logic          tx_v;
    logic [FW-1:0] tx_data;
    logic          tx_ready;

    // =========================================================================
    // DUT: cgra_mem_bridge
    // =========================================================================
    cgra_mem_bridge #(
        .ADDR_WIDTH (AW),
        .DATA_WIDTH (DW),
        .FLIT_WIDTH (FW),
        .TAG_WIDTH  (5)
    ) dut (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .rx_v_i     (rx_v),
        .rx_data_i  (rx_data),
        .rx_ready_o (rx_ready),
        .tx_v_o     (tx_v),
        .tx_data_o  (tx_data),
        .tx_ready_i (tx_ready),
        .axi_m      (cgra_axi)
    );

    // =========================================================================
    // Downstream slave: cgra_mem_system_16bit
    // =========================================================================
    assign bs_axi.aw_valid = 1'b0; assign bs_axi.aw_addr = '0; assign bs_axi.aw_prot = '0;
    assign bs_axi.w_valid  = 1'b0; assign bs_axi.w_data  = '0; assign bs_axi.w_strb  = '0;
    assign bs_axi.b_ready  = 1'b1;
    assign bs_axi.ar_valid = 1'b0; assign bs_axi.ar_addr = '0; assign bs_axi.ar_prot = '0;
    assign bs_axi.r_ready  = 1'b1;

    assign md_axi.aw_valid = 1'b0; assign md_axi.aw_addr = '0; assign md_axi.aw_prot = '0;
    assign md_axi.w_valid  = 1'b0; assign md_axi.w_data  = '0; assign md_axi.w_strb  = '0;
    assign md_axi.b_ready  = 1'b1;
    assign md_axi.ar_valid = 1'b0; assign md_axi.ar_addr = '0; assign md_axi.ar_prot = '0;
    assign md_axi.r_ready  = 1'b1;

    cgra_mem_system_16bit #(
        .ADDR_WIDTH    (AW),
        .DATA_WIDTH    (DW),
        .CSR_NUM_REGS  (8),
        .MEM_NUM_WORDS (1024)
    ) u_mem_sys (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),
        .fpga_axi_i            (fpga_axi),
        .bitstream_fetch_axi_i (bs_axi),
        .metadata_fetch_axi_i  (md_axi),
        .data_fetch_axi_i      (cgra_axi)
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

    // =========================================================================
    // Address helpers
    // =========================================================================
    function automatic logic [AW-1:0] csr_a(int i);
        return CSR_BASE + AW'(i * 2);
    endfunction
    function automatic logic [AW-1:0] mem_a(int i);
        return MEM_BASE + AW'(i * 2);
    endfunction

    // =========================================================================
    // FPGA directed-write helper
    // =========================================================================
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
    // CGRA flit driver tasks
    // =========================================================================

    // Send one 16-bit flit; waits for rx_ready.
    task automatic send_flit(input logic [FW-1:0] flit);
        @(posedge clk_i); #1;
        rx_v    = 1'b1;
        rx_data = flit;
        while (!rx_ready) @(posedge clk_i);
        @(posedge clk_i); #1;
        rx_v    = 1'b0;
        rx_data = '0;
    endtask

    // Send a complete 4-flit request packet.
    // ADDR_HI flit is always 0 for 16-bit address space.
    task automatic cgra_send_req(
        input logic          rw,
        input logic [1:0]    byteen,
        input logic [4:0]    tag,
        input logic [AW-1:0] addr,
        input logic [DW-1:0] data = '0
    );
        send_flit({rw, byteen, tag, 8'b0});     // HDR
        send_flit(AW'(addr));                    // ADDR_LO  (full 16-bit addr)
        send_flit(16'h0000);                     // ADDR_HI  (always 0)
        send_flit(data);                         // DATA
    endtask

    // Receive a 2-flit response.
    task automatic cgra_recv_rsp(
        output logic [DW-1:0] rsp_data,
        output logic [4:0]    rsp_tag,
        output logic [1:0]    rsp_resp
    );
        tx_ready = 1'b1;
        @(posedge clk_i);
        while (!tx_v) @(posedge clk_i);
        rsp_data = tx_data;
        @(posedge clk_i);
        while (!tx_v) @(posedge clk_i);
        rsp_tag  = tx_data[15:11];
        rsp_resp = tx_data[10:9];
        @(posedge clk_i);
        tx_ready = 1'b0;
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        rx_v     = 1'b0;
        rx_data  = '0;
        tx_ready = 1'b0;

        fpga_agent = new(fpga_dv, "FPGA");
        fpga_agent.reset();
        pass_cnt = 0;
        fail_cnt = 0;
        cyc      = 0;

        // Reset
        rst_i = 1'b1;
        repeat (5) @(posedge clk_i);
        @(posedge clk_i); #1;
        rst_i = 1'b0;
        repeat (3) @(posedge clk_i);

        // =====================================================================
        $display("\n--- T1: CGRA writes FPGA memory; reads back via CGRA ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    tag;

            cgra_send_req(1'b1, 2'b11, 5'd1, mem_a(0), 16'hBEEF);
            cgra_recv_rsp(rdata, tag, resp);
            shadow_write(mem_a(0), 16'hBEEF);
            check16(rdata, 16'h0000, "T1: write response data = 0");
            check16({11'b0, tag}, {11'b0, 5'd1}, "T1: write tag echo");

            cgra_send_req(1'b1, 2'b11, 5'd2, mem_a(1), 16'hCAFE);
            cgra_recv_rsp(rdata, tag, resp);
            shadow_write(mem_a(1), 16'hCAFE);

            cgra_send_req(1'b0, 2'b11, 5'd3, mem_a(0));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'hBEEF, "T1: read mem[0]");
            check16({11'b0, tag}, {11'b0, 5'd3}, "T1: read tag echo");

            cgra_send_req(1'b0, 2'b11, 5'd4, mem_a(1));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'hCAFE, "T1: read mem[1]");
        end

        // =====================================================================
        $display("\n--- T2: FPGA writes CSRs; CGRA reads via bridge ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    tag;

            fpga_write(csr_a(0), 16'h1111);
            fpga_write(csr_a(3), 16'hABCD);
            fpga_write(csr_a(7), 16'hF00F);

            cgra_send_req(1'b0, 2'b11, 5'd5, csr_a(0));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'h1111, "T2: CGRA reads CSR[0]");
            check16({11'b0, tag}, {11'b0, 5'd5}, "T2: CSR[0] tag echo");

            cgra_send_req(1'b0, 2'b11, 5'd6, csr_a(7));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'hF00F, "T2: CGRA reads CSR[7]");
        end

        // =====================================================================
        $display("\n--- T3: Byte strobe --- CGRA partial write + read-back ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    tag;

            cgra_send_req(1'b1, 2'b11, 5'd7, mem_a(10), 16'hFFFF);
            cgra_recv_rsp(rdata, tag, resp);
            shadow_write(mem_a(10), 16'hFFFF, 2'b11);

            // Low byte only
            cgra_send_req(1'b1, 2'b01, 5'd8, mem_a(10), 16'h00AA);
            cgra_recv_rsp(rdata, tag, resp);
            shadow_write(mem_a(10), 16'h00AA, 2'b01);
            cgra_send_req(1'b0, 2'b11, 5'd9, mem_a(10));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, shadow[mem_a(10)], "T3: strobe=01 low byte");

            // High byte only
            cgra_send_req(1'b1, 2'b10, 5'd10, mem_a(10), 16'hBB00);
            cgra_recv_rsp(rdata, tag, resp);
            shadow_write(mem_a(10), 16'hBB00, 2'b10);
            cgra_send_req(1'b0, 2'b11, 5'd11, mem_a(10));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, shadow[mem_a(10)], "T3: strobe=10 high byte");
        end

        // =====================================================================
        $display("\n--- T4: Tag echo across all 32 tag values ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    got_tag;

            for (int t = 0; t < 32; t++) begin
                cgra_send_req(1'b1, 2'b11, 5'(t), mem_a(20 + t), DW'(16'h0100 + t));
                cgra_recv_rsp(rdata, got_tag, resp);
                shadow_write(mem_a(20 + t), DW'(16'h0100 + t));
                check16({11'b0, got_tag}, {11'b0, 5'(t)},
                        $sformatf("T4: tag echo t=%0d", t));
            end
        end

        // =====================================================================
        $display("\n--- T5: Interleaved CGRA read + FPGA write to same address ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    tag;

            fpga_write(mem_a(100), 16'hDEAD);
            cgra_send_req(1'b0, 2'b11, 5'd0, mem_a(100));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'hDEAD, "T5: CGRA reads FPGA-written mem[100]");

            fpga_write(mem_a(100), 16'h1234);
            cgra_send_req(1'b0, 2'b11, 5'd1, mem_a(100));
            cgra_recv_rsp(rdata, tag, resp);
            check16(rdata, 16'h1234, "T5: CGRA reads updated mem[100]");
        end

        // =====================================================================
        $display("\n--- T6: Back-to-back CGRA writes with no idle gap ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            logic [4:0]    tag;

            for (int i = 0; i < 4; i++) begin
                cgra_send_req(1'b1, 2'b11, 5'(i), mem_a(200 + i), DW'(16'hA000 + i));
                cgra_recv_rsp(rdata, tag, resp);
                shadow_write(mem_a(200 + i), DW'(16'hA000 + i));
            end
            for (int i = 0; i < 4; i++) begin
                cgra_send_req(1'b0, 2'b11, 5'(i), mem_a(200 + i));
                cgra_recv_rsp(rdata, tag, resp);
                check16(rdata, shadow[mem_a(200 + i)],
                        $sformatf("T6: back-to-back readback mem[%0d]", 200 + i));
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

endmodule
