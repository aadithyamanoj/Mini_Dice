// =============================================================================
// cgra_mem_bridge.sv
//
// Bridges a 16-bit flit stream (io_rx_tx_adapter PHY side) to an AXI-Lite
// master port on cgra_mem_system_16bit.
//
// The CGRA master packetises its request into exactly 4 × 16-bit flits,
// always in the order HDR → ADDR_LO → ADDR_HI → DATA.  The bridge decodes
// that packet, issues a single AXI-Lite transaction (read or write), and
// returns a 2-flit response packet (DATA → TAG).
//
// ─── Request packet (4 × 16-bit flits) ─────────────────────────────────────
//   Flit 0 [HDR]:     [15]=rw, [14:13]=byteen[1:0], [12:8]=tag[4:0], [7:0]=0
//   Flit 1 [ADDR_LO]: addr[15:0]
//   Flit 2 [ADDR_HI]: addr[31:16]  (send 0 for 16-bit address spaces)
//   Flit 3 [DATA]:    data[15:0]   (don't-care on reads; still must be sent)
//
// ─── Response packet (2 × 16-bit flits) ─────────────────────────────────────
//   Flit 0 [DATA]:    data[15:0]  (read return data; 0x0000 on writes)
//   Flit 1 [TAG]:     [15:11]=tag[4:0], [10:9]=resp[1:0], [8:0]=0
//
// ─── Address width ───────────────────────────────────────────────────────────
//   ADDR_WIDTH controls how many address bits are driven onto the AXI bus.
//   The internal address register is always 32 bits (two 16-bit flit slots);
//   only the lower ADDR_WIDTH bits are forwarded to axi_m.aw_addr / ar_addr.
//   For 16-bit address spaces send ADDR_HI = 0.
//
// ─── Restrictions ────────────────────────────────────────────────────────────
//   • One outstanding transaction at a time.  rx_ready_o deasserts while an
//     AXI-Lite transaction is in-flight or a response is being sent.
//   • FLIT_WIDTH and DATA_WIDTH must both be 16.
//   • TAG_WIDTH must be ≤ 5 (occupies flit bits [12:8] / [15:11]).
//   • ADDR_WIDTH must be ≤ 32 (two 16-bit address flits = 32 bits max).
// =============================================================================

`include "axi/typedef.svh"

module cgra_mem_bridge #(
    parameter int ADDR_WIDTH = 16,   // AXI address bits forwarded to slave
    parameter int DATA_WIDTH = 16,
    parameter int FLIT_WIDTH = 16,
    parameter int TAG_WIDTH  = 5     // must be ≤ 5
)(
    input  logic clk_i,
    input  logic rst_i,

    // ---- Incoming request flits (from io_rx_tx_adapter phy_rx_* side) ------
    input  logic                  rx_v_i,
    input  logic [FLIT_WIDTH-1:0] rx_data_i,
    output logic                  rx_ready_o,

    // ---- Outgoing response flits (to io_rx_tx_adapter phy_tx_* side) -------
    output logic                  tx_v_o,
    output logic [FLIT_WIDTH-1:0] tx_data_o,
    input  logic                  tx_ready_i,

    // ---- AXI-Lite master toward cgra_mem_system_16bit -----------------------
    AXI_LITE.Master               axi_m
);

    // -------------------------------------------------------------------------
    // Compile-time sanity checks
    // -------------------------------------------------------------------------
    initial begin
        if (FLIT_WIDTH !== 16)
            $error("cgra_mem_bridge: FLIT_WIDTH must be 16, got %0d", FLIT_WIDTH);
        if (DATA_WIDTH !== 16)
            $error("cgra_mem_bridge: DATA_WIDTH must be 16, got %0d", DATA_WIDTH);
        if (TAG_WIDTH > 5)
            $error("cgra_mem_bridge: TAG_WIDTH must be ≤5, got %0d", TAG_WIDTH);
        if (ADDR_WIDTH > 32)
            $error("cgra_mem_bridge: ADDR_WIDTH must be ≤32, got %0d", ADDR_WIDTH);
    end

    // -------------------------------------------------------------------------
    // State machine encoding
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE,           // waiting for HDR flit
        RECV_ADDR_LO,   // HDR captured; waiting for addr[15:0] flit
        RECV_ADDR_HI,   // addr_lo captured; waiting for addr[31:16] flit
        RECV_DATA,      // addr_hi captured; waiting for data flit
        AXI_WR_BOTH,    // issue AW+W simultaneously; both pending
        AXI_WR_AW,      // W accepted; waiting for AW acceptance
        AXI_WR_W,       // AW accepted; waiting for W acceptance
        AXI_WR_B,       // AW+W done; waiting for B response
        AXI_RD_AR,      // issue AR; waiting for acceptance
        AXI_RD_R,       // AR accepted; waiting for R response
        SEND_RSP_DATA,  // emit response flit 0 (data)
        SEND_RSP_TAG    // emit response flit 1 (tag/resp)
    } state_e;

    state_e state_q, state_d;

    // -------------------------------------------------------------------------
    // Captured transaction fields
    // Internal address register is always 32 bits so both 16-bit flit slots
    // can be stored regardless of ADDR_WIDTH.  Only [ADDR_WIDTH-1:0] is driven
    // onto the AXI bus.
    // -------------------------------------------------------------------------
    logic        tr_rw_q;
    logic [1:0]  tr_byteen_q;
    logic [4:0]  tr_tag_q;
    logic [31:0] tr_addr_q;       // always 32-bit internal store
    logic [15:0] tr_wdata_q;

    logic [15:0] tr_rsp_data_q;
    logic [1:0]  tr_rsp_resp_q;

    logic flit_accepted;
    assign flit_accepted = rx_v_i & rx_ready_o;

    // -------------------------------------------------------------------------
    // Next-state combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            IDLE:         if (flit_accepted)                              state_d = RECV_ADDR_LO;
            RECV_ADDR_LO: if (flit_accepted)                              state_d = RECV_ADDR_HI;
            RECV_ADDR_HI: if (flit_accepted)                              state_d = RECV_DATA;
            RECV_DATA: begin
                if (flit_accepted)
                    state_d = tr_rw_q ? AXI_WR_BOTH : AXI_RD_AR;
            end
            AXI_WR_BOTH: begin
                if      ( axi_m.aw_ready &  axi_m.w_ready) state_d = AXI_WR_B;
                else if ( axi_m.aw_ready & ~axi_m.w_ready) state_d = AXI_WR_W;
                else if (~axi_m.aw_ready &  axi_m.w_ready) state_d = AXI_WR_AW;
            end
            AXI_WR_AW:   if (axi_m.aw_ready)              state_d = AXI_WR_B;
            AXI_WR_W:    if (axi_m.w_ready)               state_d = AXI_WR_B;
            AXI_WR_B:    if (axi_m.b_valid)               state_d = SEND_RSP_DATA;
            AXI_RD_AR:   if (axi_m.ar_ready)              state_d = AXI_RD_R;
            AXI_RD_R:    if (axi_m.r_valid)               state_d = SEND_RSP_DATA;
            SEND_RSP_DATA: if (tx_v_o & tx_ready_i)       state_d = SEND_RSP_TAG;
            SEND_RSP_TAG:  if (tx_v_o & tx_ready_i)       state_d = IDLE;
            default:                                        state_d = IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) state_q <= IDLE;
        else        state_q <= state_d;
    end

    // -------------------------------------------------------------------------
    // Capture flit fields into transaction registers
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tr_rw_q     <= 1'b0;
            tr_byteen_q <= '0;
            tr_tag_q    <= '0;
            tr_addr_q   <= '0;
            tr_wdata_q  <= '0;
        end else begin
            if (state_q == IDLE && flit_accepted) begin
                tr_rw_q     <= rx_data_i[15];
                tr_byteen_q <= rx_data_i[14:13];
                tr_tag_q    <= rx_data_i[12:8];
            end
            if (state_q == RECV_ADDR_LO && flit_accepted)
                tr_addr_q[15:0]  <= rx_data_i;
            if (state_q == RECV_ADDR_HI && flit_accepted)
                tr_addr_q[31:16] <= rx_data_i;   // 0 for 16-bit address spaces
            if (state_q == RECV_DATA && flit_accepted)
                tr_wdata_q <= rx_data_i;
        end
    end

    // -------------------------------------------------------------------------
    // Capture AXI response (one cycle before SEND_RSP_DATA)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            tr_rsp_data_q <= '0;
            tr_rsp_resp_q <= '0;
        end else begin
            if (state_q == AXI_WR_B && axi_m.b_valid) begin
                tr_rsp_data_q <= '0;
                tr_rsp_resp_q <= axi_m.b_resp;
            end
            if (state_q == AXI_RD_R && axi_m.r_valid) begin
                tr_rsp_data_q <= axi_m.r_data;
                tr_rsp_resp_q <= axi_m.r_resp;
            end
        end
    end

    // -------------------------------------------------------------------------
    // RX flit ready: accept only during the four receive phases
    // -------------------------------------------------------------------------
    always_comb begin
        unique case (state_q)
            IDLE, RECV_ADDR_LO, RECV_ADDR_HI, RECV_DATA: rx_ready_o = 1'b1;
            default:                                       rx_ready_o = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // TX flit output: emit 2-flit response packet
    // -------------------------------------------------------------------------
    always_comb begin
        tx_v_o    = 1'b0;
        tx_data_o = '0;
        unique case (state_q)
            SEND_RSP_DATA: begin
                tx_v_o    = 1'b1;
                tx_data_o = tr_rsp_data_q;
            end
            SEND_RSP_TAG: begin
                tx_v_o    = 1'b1;
                // [15:11]=tag[4:0]  [10:9]=resp[1:0]  [8:0]=0
                tx_data_o = {tr_tag_q, tr_rsp_resp_q, 9'b0};
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // AXI-Lite master channel outputs
    // Only the lower ADDR_WIDTH bits of the internal 32-bit register are
    // forwarded to the AXI bus.
    // -------------------------------------------------------------------------

    // Write address channel
    assign axi_m.aw_valid = (state_q == AXI_WR_BOTH) | (state_q == AXI_WR_AW);
    assign axi_m.aw_addr  = ADDR_WIDTH'(tr_addr_q[ADDR_WIDTH-1:0]);
    assign axi_m.aw_prot  = 3'b000;

    // Write data channel
    assign axi_m.w_valid  = (state_q == AXI_WR_BOTH) | (state_q == AXI_WR_W);
    assign axi_m.w_data   = tr_wdata_q;
    assign axi_m.w_strb   = tr_byteen_q;

    // Write response channel
    assign axi_m.b_ready  = (state_q == AXI_WR_B);

    // Read address channel
    assign axi_m.ar_valid = (state_q == AXI_RD_AR);
    assign axi_m.ar_addr  = ADDR_WIDTH'(tr_addr_q[ADDR_WIDTH-1:0]);
    assign axi_m.ar_prot  = 3'b000;

    // Read data channel
    assign axi_m.r_ready  = (state_q == AXI_RD_R);

    // -------------------------------------------------------------------------
    // Simulation-only assertions
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    always_ff @(posedge clk_i) begin
        if (!rst_i) begin
            if (tx_v_o && !tx_ready_i && $past(tx_v_o && !tx_ready_i))
                assert (tx_data_o === $past(tx_data_o))
                    else $error("cgra_mem_bridge: tx_data_o changed while stalled");
        end
    end
`endif

endmodule
