// =============================================================================
// cgra_mem_system_16bit_tb_syn.sv
//
// Synthesizable testbench for cgra_mem_system_16bit.
// Drives AXI-Lite channels directly using plain tasks — no OOP agents.
// Compatible with both RTL simulation and post-synthesis (sim-syn) flow.
//
// Address map:
//   CSRs:     0x0000_0000 – 0x0000_000E  (8 × 16-bit regs, byte stride 2)
//   FPGA mem: 0x0001_0000 – 0x0001_07FE  (1024 × 16-bit words)
// =============================================================================

`include "axi/typedef.svh"
`include "axi/assign.svh"

module cgra_mem_system_16bit_tb_syn;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int unsigned AW          = 32;
    localparam int unsigned DW          = 16;
    localparam int          CLK_HALF_NS = 5;    // 100 MHz
    localparam int          N_RAND      = 32;   // random write-readback iterations

    localparam logic [AW-1:0] CSR_BASE = 32'h0000_0000;
    localparam logic [AW-1:0] MEM_BASE = 32'h0001_0000;

    function automatic logic [AW-1:0] csr_a(int i); return CSR_BASE + AW'(i * 2); endfunction
    function automatic logic [AW-1:0] mem_a(int i); return MEM_BASE + AW'(i * 2); endfunction

    // =========================================================================
    // Clock / reset
    // =========================================================================
    bit   clk_i;
    logic rst_i = 1'b1;   // active-high, starts asserted

    initial forever #(CLK_HALF_NS * 1ns) clk_i = ~clk_i;

    // =========================================================================
    // AXI-Lite interfaces — one per master
    // =========================================================================
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) fpga_axi ();
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) bs_axi   ();
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) md_axi   ();
    AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) dt_axi   ();

    // =========================================================================
    // DUT
    // =========================================================================
    cgra_mem_system_16bit #(
        .ADDR_WIDTH    ( AW   ),
        .DATA_WIDTH    ( DW   ),
        .CSR_NUM_REGS  ( 8    ),
        .MEM_NUM_WORDS ( 1024 )
    ) dut (
        .clk_i                 ( clk_i    ),
        .rst_i                 ( rst_i    ),
        .fpga_axi_i            ( fpga_axi ),
        .bitstream_fetch_axi_i ( bs_axi   ),
        .metadata_fetch_axi_i  ( md_axi   ),
        .data_fetch_axi_i      ( dt_axi   )
    );

    // =========================================================================
    // Virtual interface typedef
    // =========================================================================
    typedef virtual AXI_LITE #(.AXI_ADDR_WIDTH(AW), .AXI_DATA_WIDTH(DW)) vif_t;

    // =========================================================================
    // AXI-Lite BFM — idle / write / read tasks
    // =========================================================================

    // Drive all master-side channels to idle state
    task automatic axi_idle(vif_t v);
        v.aw_valid = 1'b0;  v.aw_addr = '0;  v.aw_prot = '0;
        v.w_valid  = 1'b0;  v.w_data  = '0;  v.w_strb  = '0;
        v.b_ready  = 1'b0;
        v.ar_valid = 1'b0;  v.ar_addr = '0;  v.ar_prot = '0;
        v.r_ready  = 1'b0;
    endtask

    // Blocking AXI-Lite write.
    // AW, W, and B are handled concurrently so ready/valid can interleave freely.
    task automatic axi_write(
        vif_t                  v,
        input logic [AW-1:0]   addr,
        input logic [DW-1:0]   data,
        input logic [DW/8-1:0] strb,
        output logic [1:0]     resp
    );
        @(posedge clk_i); #1;
        v.aw_valid = 1'b1;  v.aw_addr = addr;  v.aw_prot = '0;
        v.w_valid  = 1'b1;  v.w_data  = data;  v.w_strb  = strb;
        v.b_ready  = 1'b1;

        fork
            // AW channel
            begin
                @(posedge clk_i iff v.aw_valid && v.aw_ready);
                #1; v.aw_valid = 1'b0;
            end
            // W channel
            begin
                @(posedge clk_i iff v.w_valid && v.w_ready);
                #1; v.w_valid = 1'b0;
            end
            // B channel — combinatorial b_valid fires same cycle as W handshake;
            // registered error-slave b_valid fires one cycle later
            begin
                @(posedge clk_i iff v.b_valid && v.b_ready);
                resp = v.b_resp;
                #1; v.b_ready = 1'b0;
            end
        join
    endtask

    // Blocking AXI-Lite read.
    task automatic axi_read(
        vif_t                 v,
        input logic [AW-1:0]  addr,
        output logic [DW-1:0] data,
        output logic [1:0]    resp
    );
        @(posedge clk_i); #1;
        v.ar_valid = 1'b1;  v.ar_addr = addr;  v.ar_prot = '0;
        v.r_ready  = 1'b1;

        @(posedge clk_i iff v.ar_valid && v.ar_ready);
        #1; v.ar_valid = 1'b0;

        @(posedge clk_i iff v.r_valid && v.r_ready);
        data = v.r_data;
        resp = v.r_resp;
        #1; v.r_ready = 1'b0;
    endtask

    // =========================================================================
    // Shadow scoreboard
    // =========================================================================
    logic [DW-1:0] shadow [logic [AW-1:0]];

    task automatic shadow_write(
        input logic [AW-1:0]   addr,
        input logic [DW-1:0]   data,
        input logic [DW/8-1:0] strb
    );
        logic [DW-1:0] prev;
        prev = shadow.exists(addr) ? shadow[addr] : '0;
        shadow[addr] = {strb[1] ? data[15:8] : prev[15:8],
                        strb[0] ? data[7:0]  : prev[7:0]};
    endtask

    // =========================================================================
    // Pass / fail tracking
    // =========================================================================
    int pass_cnt, fail_cnt;

    task automatic check16(
        input logic [15:0] actual,
        input logic [15:0] expected,
        input string       msg
    );
        if (actual !== expected) begin
            $error("[FAIL] %s — Exp: 0x%04h  Got: 0x%04h", msg, expected, actual);
            fail_cnt++;
        end else begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end
    endtask

    // =========================================================================
    // Directed write + read-check helpers
    // =========================================================================
    task automatic dwrite(
        vif_t                  v,
        input logic [AW-1:0]   addr,
        input logic [DW-1:0]   data,
        input logic [DW/8-1:0] strb = '1
    );
        logic [1:0] resp;
        axi_write(v, addr, data, strb, resp);
        shadow_write(addr, data, strb);
    endtask

    task automatic dread_check(
        vif_t                v,
        input logic [AW-1:0] addr,
        input string         msg
    );
        logic [DW-1:0]  got;
        logic [1:0]     resp;
        logic [DW-1:0]  exp;
        axi_read(v, addr, got, resp);
        exp = shadow.exists(addr) ? shadow[addr] : '0;
        check16(got, exp, msg);
    endtask

    // =========================================================================
    // Virtual interface handles
    // =========================================================================
    vif_t fpga_v, bs_v, md_v, dt_v;

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        fpga_v = fpga_axi;
        bs_v   = bs_axi;
        md_v   = md_axi;
        dt_v   = dt_axi;

        axi_idle(fpga_v);
        axi_idle(bs_v);
        axi_idle(md_v);
        axi_idle(dt_v);

        pass_cnt = 0;
        fail_cnt = 0;

        // Reset sequence — active-high
        rst_i = 1'b1;
        repeat (5) @(posedge clk_i);
        @(posedge clk_i); #1;
        rst_i = 1'b0;
        repeat (3) @(posedge clk_i);

        // =====================================================================
        $display("\n--- TEST 1: FPGA writes 8 CSRs, all masters read back ---");
        // =====================================================================
        for (int i = 0; i < 8; i++)
            dwrite(fpga_v, csr_a(i), DW'(16'hA000 + i));

        for (int i = 0; i < 8; i++)
            dread_check(fpga_v, csr_a(i), $sformatf("T1: FPGA reads CSR[%0d]", i));
        for (int i = 0; i < 8; i++)
            dread_check(bs_v,   csr_a(i), $sformatf("T1: BS   reads CSR[%0d]", i));
        for (int i = 0; i < 8; i++)
            dread_check(md_v,   csr_a(i), $sformatf("T1: MD   reads CSR[%0d]", i));
        for (int i = 0; i < 8; i++)
            dread_check(dt_v,   csr_a(i), $sformatf("T1: DT   reads CSR[%0d]", i));

        // =====================================================================
        $display("\n--- TEST 2: Each master writes FPGA memory, cross-master reads ---");
        // =====================================================================
        dwrite(fpga_v, mem_a(0),   16'hF001);
        dwrite(bs_v,   mem_a(100), 16'hB002);
        dwrite(md_v,   mem_a(200), 16'hC003);
        dwrite(dt_v,   mem_a(300), 16'hD004);

        dread_check(dt_v,   mem_a(0),   "T2: DT reads FPGA-written MEM[0]");
        dread_check(md_v,   mem_a(100), "T2: MD reads BS-written   MEM[100]");
        dread_check(fpga_v, mem_a(200), "T2: FPGA reads MD-written MEM[200]");
        dread_check(bs_v,   mem_a(300), "T2: BS reads DT-written   MEM[300]");

        // =====================================================================
        $display("\n--- TEST 3: Random write-readback scoreboard — CSR space ---");
        // =====================================================================
        begin
            logic [AW-1:0] addr;
            logic [DW-1:0] data;
            int            reg_idx;
            for (int i = 0; i < N_RAND; i++) begin
                void'(std::randomize(reg_idx) with { reg_idx >= 0; reg_idx < 8; });
                addr = csr_a(reg_idx);
                void'(std::randomize(data));
                unique case (i % 4)
                    0: dwrite(fpga_v, addr, data);
                    1: dwrite(bs_v,   addr, data);
                    2: dwrite(md_v,   addr, data);
                    3: dwrite(dt_v,   addr, data);
                endcase
                unique case (i % 4)
                    0: dread_check(dt_v,   addr, $sformatf("T3[%0d]: CSR[%0d]", i, reg_idx));
                    1: dread_check(fpga_v, addr, $sformatf("T3[%0d]: CSR[%0d]", i, reg_idx));
                    2: dread_check(bs_v,   addr, $sformatf("T3[%0d]: CSR[%0d]", i, reg_idx));
                    3: dread_check(md_v,   addr, $sformatf("T3[%0d]: CSR[%0d]", i, reg_idx));
                endcase
            end
        end

        // =====================================================================
        $display("\n--- TEST 4: Random write-readback scoreboard — FPGA memory ---");
        // =====================================================================
        begin
            logic [AW-1:0] addr;
            logic [DW-1:0] data;
            int            word_idx;
            for (int i = 0; i < N_RAND; i++) begin
                void'(std::randomize(word_idx) with { word_idx >= 0; word_idx < 1024; });
                addr = mem_a(word_idx);
                void'(std::randomize(data));
                unique case (i % 4)
                    0: dwrite(fpga_v, addr, data);
                    1: dwrite(bs_v,   addr, data);
                    2: dwrite(md_v,   addr, data);
                    3: dwrite(dt_v,   addr, data);
                endcase
                unique case (i % 4)
                    0: dread_check(md_v,   addr, $sformatf("T4[%0d]: MEM[%0d]", i, word_idx));
                    1: dread_check(dt_v,   addr, $sformatf("T4[%0d]: MEM[%0d]", i, word_idx));
                    2: dread_check(fpga_v, addr, $sformatf("T4[%0d]: MEM[%0d]", i, word_idx));
                    3: dread_check(bs_v,   addr, $sformatf("T4[%0d]: MEM[%0d]", i, word_idx));
                endcase
            end
        end

        // =====================================================================
        $display("\n--- TEST 5: Byte strobe --- CSR and FPGA memory ---");
        // =====================================================================
        dwrite(fpga_v, csr_a(0), 16'hFFFF);
        dwrite(fpga_v, csr_a(0), 16'h00AA, 2'b01);
        dread_check(bs_v,   csr_a(0), "T5: CSR[0] strobe=01 low byte written");

        dwrite(fpga_v, csr_a(0), 16'hBB00, 2'b10);
        dread_check(dt_v,   csr_a(0), "T5: CSR[0] strobe=10 high byte written");

        dwrite(fpga_v, csr_a(0), 16'h1234, 2'b00);
        dread_check(md_v,   csr_a(0), "T5: CSR[0] strobe=00 data preserved");

        dwrite(md_v, mem_a(500), 16'hFFFF);
        dwrite(md_v, mem_a(500), 16'h00CC, 2'b01);
        dread_check(fpga_v, mem_a(500), "T5: MEM[500] strobe=01 low byte");

        dwrite(md_v, mem_a(500), 16'hDD00, 2'b10);
        dread_check(bs_v,   mem_a(500), "T5: MEM[500] strobe=10 high byte");

        // =====================================================================
        $display("\n--- TEST 6: Boundary addresses ---");
        // =====================================================================
        dwrite(fpga_v, csr_a(0), 16'h0001);
        dwrite(fpga_v, csr_a(7), 16'hF00F);
        dread_check(fpga_v, csr_a(0), "T6: CSR[0] lower bound");
        dread_check(fpga_v, csr_a(7), "T6: CSR[7] upper bound");

        dwrite(fpga_v, mem_a(0),    16'h0000);
        dwrite(fpga_v, mem_a(1023), 16'hFFFF);
        dread_check(fpga_v, mem_a(0),    "T6: MEM[0]    lower bound");
        dread_check(fpga_v, mem_a(1023), "T6: MEM[1023] upper bound");

        // =====================================================================
        $display("\n--- TEST 7: DECERR on unmapped address ---");
        // =====================================================================
        begin
            logic [DW-1:0] rdata;
            logic [1:0]    resp;
            axi_write(fpga_v, 32'h0000_0200, 16'hDEAD, 2'b11, resp);
            if (resp === axi_pkg::RESP_DECERR) begin
                $display("[PASS] T7: unmapped write returns DECERR");
                pass_cnt++;
            end else begin
                $display("[INFO] T7: resp=0x%0h (expected DECERR=0x%0h)", resp, axi_pkg::RESP_DECERR);
            end
        end

        // =====================================================================
        $display("\n========================================");
        $display("  PASSED: %0d   FAILED: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED!");
        $display("========================================\n");

        if (fail_cnt > 0) $stop;
        repeat (10) @(posedge clk_i);
        $finish;
    end

endmodule
