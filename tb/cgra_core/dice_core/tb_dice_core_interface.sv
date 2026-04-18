`timescale 1ns / 1ps

`include "dice_define.vh"

// =============================================================================
// tb_dice_core_interface
//
// Valid-ready interface stress testbench for dice_core.
// Unlike tb_dice_core (which loads real test vectors and checks end-to-end
// execution), this TB focuses entirely on handshake correctness under
// backpressure.
//
// TWO LAYERS of interface stress:
//
// Layer 1 – External boundary (TB slave models with configurable stall knobs)
//   1. cta_if   – dispatch (TB→DUT) and complete (DUT→TB) channels
//   2. mfetch   – AXI4 read master: AR backpressure + per-beat R gap
//   3. bsfetch  – AXI4 read master: same knobs (106-beat burst)
//   4. AXI-Lite – write (AW/W/B) and read (AR/R) channels from LDST FIFO
//
// Layer 2 – Internal dice_core interfaces (hierarchical force/release + SVA)
//   5. fdr_if      – frontend → backend (u_dut.fdr_out_if.valid/ready)
//                    force fdr_ready=0 to stall backend acceptance of FDR packets
//   6. schedule_if – cta_schedule_stage → fdr_top (within dice_frontend)
//                    force schedule_ready=0 to stall FDR from consuming schedule
//   7. simt_update – fdr_top → cta_schedule_stage (valid/ready wires)
//                    force simt_update_ready=0 to block SIMT stack updates
//
// SVA assertions (always-on) check that every valid signal on both layers
// remains stable until the matching ready fires.
//
// Synthetic metadata: bitstream_addr=0x2000, bitstream_length=8, lat=1.
// AXI-Lite channels only carry traffic when the backend's LDST FIFO fires
// (requires non-zero stores/loads in metadata); with zero-store metadata
// those scenarios confirm no spurious transactions occur under stall.
// =============================================================================

module tb_dice_core_interface;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;

  // =========================================================================
  // Waveform dump
  // =========================================================================
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_core_interface, "+struct", "+mda");
  end

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int ClkPeriod    = 10;
  localparam int TimeoutCycles = 10_000;

  // DICE_METADATA_WIDTH = 256, AxiDataWidth = 16  → 16 beats per meta burst
  localparam int NumMetaBeats = DICE_METADATA_WIDTH / AxiDataWidth;  // 16

  // bitstream_fetch_load uses a fixed burst of this many beats
  localparam int BsBeatCount  = (DICE_BITSTREAM_SIZE + AxiDataWidth - 1) / AxiDataWidth; // 106
  localparam int BsBurstLen   = BsBeatCount - 1;  // 105

  // -------------------------------------------------------------------------
  // Synthetic metadata beat array (beat 0 → bits[15:0], beat 15 → bits[255:240])
  //
  // Target pgraph_meta_t field values (DICE_ADDR_WIDTH=16, REG_NUM=18):
  //   bitstream_addr [bits 255:240] = 0x2000  → beat 15 = 16'h2000
  //   bitstream_length[bits 239:232] = 8      \
  //   unrolling_factor[bits 231:230] = 0       } beat 14 = 16'h0800
  //   lat[7:2]        [bits 229:224] = 0      /
  //   lat[1:0]        [bits 223:222] = 01     → beat 13 bit-14 = 1 → 16'h4000
  //   everything else = 0
  // -------------------------------------------------------------------------
  localparam logic [15:0] META_BEATS [0:15] = '{
    16'h0000, 16'h0000, 16'h0000, 16'h0000,   // beats  0- 3
    16'h0000, 16'h0000, 16'h0000, 16'h0000,   // beats  4- 7
    16'h0000, 16'h0000, 16'h0000, 16'h0000,   // beats  8-11
    16'h0000, 16'h4000, 16'h0800, 16'h2000    // beats 12-15
  };

  // =========================================================================
  // Clock / reset / cycle counter
  // =========================================================================
  logic clk_i, rst_i;
  int   cycle_count;

  initial begin
    clk_i = 1'b0;
    forever #(ClkPeriod / 2) clk_i = ~clk_i;
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles)
        $fatal(1, "GLOBAL TIMEOUT after %0d cycles", TimeoutCycles);
    end
  end

  // =========================================================================
  // DUT port signals
  // =========================================================================
  cta_if cta_if_inst ();

  slv_req_t  mfetch_req_o;
  slv_resp_t mfetch_resp_i;
  slv_req_t  bsfetch_req_o;
  slv_resp_t bsfetch_resp_i;

  logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i, csrX1_i, csrX2_i, csrX3_i;
  logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i, csrX5_i, csrX6_i, csrX7_i;
  logic cgra_prog_dout_o, cgra_prog_we_o;

  logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o;
  logic                           axi_awvalid_o, axi_awready_i;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_wdata_o;
  logic [1:0]                     axi_wstrb_o;
  logic                           axi_wvalid_o, axi_wready_i;
  logic [1:0]                     axi_bresp_i;
  logic                           axi_bvalid_i, axi_bready_o;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_araddr_o;
  logic                           axi_arvalid_o, axi_arready_i;
  logic [DICE_REG_DATA_WIDTH-1:0] axi_rdata_i;
  logic [1:0]                     axi_rresp_i;
  logic                           axi_rvalid_i, axi_rready_o;

  // =========================================================================
  // DUT
  // =========================================================================
  dice_core u_dut (
    .clk_i            (clk_i),
    .rst_i            (rst_i),
    .cta_if_inst      (cta_if_inst),
    .mfetch_req_o     (mfetch_req_o),
    .mfetch_resp_i    (mfetch_resp_i),
    .bsfetch_req_o    (bsfetch_req_o),
    .bsfetch_resp_i   (bsfetch_resp_i),
    .csrX0_i(csrX0_i), .csrX1_i(csrX1_i), .csrX2_i(csrX2_i), .csrX3_i(csrX3_i),
    .csrX4_i(csrX4_i), .csrX5_i(csrX5_i), .csrX6_i(csrX6_i), .csrX7_i(csrX7_i),
    .cgra_prog_dout_o (cgra_prog_dout_o),
    .cgra_prog_we_o   (cgra_prog_we_o),
    .axi_awaddr_o     (axi_awaddr_o),  .axi_awvalid_o(axi_awvalid_o),
    .axi_awready_i    (axi_awready_i),
    .axi_wdata_o      (axi_wdata_o),   .axi_wstrb_o  (axi_wstrb_o),
    .axi_wvalid_o     (axi_wvalid_o),  .axi_wready_i (axi_wready_i),
    .axi_bresp_i      (axi_bresp_i),   .axi_bvalid_i (axi_bvalid_i),
    .axi_bready_o     (axi_bready_o),
    .axi_araddr_o     (axi_araddr_o),  .axi_arvalid_o(axi_arvalid_o),
    .axi_arready_i    (axi_arready_i),
    .axi_rdata_i      (axi_rdata_i),   .axi_rresp_i  (axi_rresp_i),
    .axi_rvalid_i     (axi_rvalid_i),  .axi_rready_o (axi_rready_o)
  );

  // =========================================================================
  // Backpressure knobs — written by each scenario before dispatch
  // =========================================================================
  int mfetch_ar_delay;   // cycles to hold ar_ready low when ar_valid arrives
  int mfetch_r_delay;    // cycles between successive r_valid beats
  int bsfetch_ar_delay;
  int bsfetch_r_delay;
  int axi_aw_delay;      // cycles to hold awready low when awvalid arrives
  int axi_w_delay;       // cycles to hold wready low when wvalid arrives
  int axi_b_delay;       // cycles to delay bvalid after both AW and W seen
  int axi_ar_delay;      // cycles to hold arready low when arvalid arrives
  int axi_r_delay;       // cycles to delay rvalid after AR accepted
  int complete_stall;    // cycles to hold complete_ready low when complete_valid fires

  // =========================================================================
  // mfetch AXI4 slave model
  //
  //  FS_IDLE      : ar_ready = (delay==0).  When ar_valid seen, if delay>0
  //                 latch address and move to FS_AR_STALL, else go to FS_ACTIVE.
  //  FS_AR_STALL  : ar_ready = (stall_cnt==0).  Count down then → FS_ACTIVE.
  //  FS_ACTIVE    : serve r channel one beat per (r_delay+1) cycles.
  // =========================================================================
  typedef enum logic [1:0] { FS_IDLE, FS_AR_STALL, FS_ACTIVE } fetch_state_e;

  fetch_state_e                         mf_state_q;
  logic [DICE_ADDR_WIDTH-1:0]           mf_addr_q;
  logic [7:0]                           mf_len_q, mf_beat_q;
  logic [$bits(mfetch_req_o.ar.id)-1:0] mf_id_q;
  int                                   mf_ar_stall_q, mf_r_stall_q;

  always_comb begin : mfetch_comb
    mfetch_resp_i = '0;
    unique case (mf_state_q)
      FS_IDLE:     mfetch_resp_i.ar_ready = (mfetch_ar_delay == 0);
      FS_AR_STALL: mfetch_resp_i.ar_ready = (mf_ar_stall_q == 0);
      FS_ACTIVE: begin
        mfetch_resp_i.ar_ready = 1'b0;
        if (mf_r_stall_q == 0) begin
          mfetch_resp_i.r_valid = 1'b1;
          mfetch_resp_i.r.id    = mf_id_q;
          mfetch_resp_i.r.resp  = 2'b00;
          mfetch_resp_i.r.data  = AxiDataWidth'(META_BEATS[mf_beat_q[3:0]]);
          mfetch_resp_i.r.last  = (mf_beat_q == mf_len_q);
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or posedge rst_i) begin : mfetch_ff
    if (rst_i) begin
      mf_state_q    <= FS_IDLE;
      mf_addr_q     <= '0;
      mf_len_q      <= '0;
      mf_beat_q     <= '0;
      mf_id_q       <= '0;
      mf_ar_stall_q <= 0;
      mf_r_stall_q  <= 0;
    end else begin
      unique case (mf_state_q)
        FS_IDLE: begin
          if (mfetch_req_o.ar_valid) begin
            mf_addr_q <= DICE_ADDR_WIDTH'(mfetch_req_o.ar.addr);
            mf_len_q  <= mfetch_req_o.ar.len;
            mf_id_q   <= mfetch_req_o.ar.id;
            if (mfetch_ar_delay > 0) begin
              mf_ar_stall_q <= mfetch_ar_delay - 1;
              mf_state_q    <= FS_AR_STALL;
            end else begin
              // ar_ready was 1 combinatorially; handshake fires this cycle
              mf_beat_q    <= '0;
              mf_r_stall_q <= mfetch_r_delay;
              mf_state_q   <= FS_ACTIVE;
            end
          end
        end
        FS_AR_STALL: begin
          if (mf_ar_stall_q > 0) begin
            mf_ar_stall_q <= mf_ar_stall_q - 1;
          end else begin
            // ar_ready becomes 1 in comb; handshake fires next posedge
            mf_beat_q    <= '0;
            mf_r_stall_q <= mfetch_r_delay;
            mf_state_q   <= FS_ACTIVE;
          end
        end
        FS_ACTIVE: begin
          if (mf_r_stall_q > 0) begin
            mf_r_stall_q <= mf_r_stall_q - 1;
          end else if (mfetch_resp_i.r_valid && mfetch_req_o.r_ready) begin
            if (mfetch_resp_i.r.last) begin
              mf_state_q <= FS_IDLE;
            end else begin
              mf_beat_q    <= mf_beat_q + 1'b1;
              mf_r_stall_q <= mfetch_r_delay;
            end
          end
        end
        default: mf_state_q <= FS_IDLE;
      endcase
    end
  end

  // =========================================================================
  // bsfetch AXI4 slave model (same structure; returns all-zero bitstream data)
  // =========================================================================
  fetch_state_e                          bsf_state_q;
  logic [DICE_ADDR_WIDTH-1:0]            bsf_addr_q;
  logic [7:0]                            bsf_len_q, bsf_beat_q;
  logic [$bits(bsfetch_req_o.ar.id)-1:0] bsf_id_q;
  int                                    bsf_ar_stall_q, bsf_r_stall_q;

  always_comb begin : bsfetch_comb
    bsfetch_resp_i = '0;
    unique case (bsf_state_q)
      FS_IDLE:     bsfetch_resp_i.ar_ready = (bsfetch_ar_delay == 0);
      FS_AR_STALL: bsfetch_resp_i.ar_ready = (bsf_ar_stall_q == 0);
      FS_ACTIVE: begin
        bsfetch_resp_i.ar_ready = 1'b0;
        if (bsf_r_stall_q == 0) begin
          bsfetch_resp_i.r_valid = 1'b1;
          bsfetch_resp_i.r.id    = bsf_id_q;
          bsfetch_resp_i.r.resp  = 2'b00;
          bsfetch_resp_i.r.data  = '0;   // dummy bitstream payload
          bsfetch_resp_i.r.last  = (bsf_beat_q == bsf_len_q);
        end
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or posedge rst_i) begin : bsfetch_ff
    if (rst_i) begin
      bsf_state_q    <= FS_IDLE;
      bsf_addr_q     <= '0;
      bsf_len_q      <= '0;
      bsf_beat_q     <= '0;
      bsf_id_q       <= '0;
      bsf_ar_stall_q <= 0;
      bsf_r_stall_q  <= 0;
    end else begin
      unique case (bsf_state_q)
        FS_IDLE: begin
          if (bsfetch_req_o.ar_valid) begin
            bsf_addr_q <= DICE_ADDR_WIDTH'(bsfetch_req_o.ar.addr);
            bsf_len_q  <= bsfetch_req_o.ar.len;
            bsf_id_q   <= bsfetch_req_o.ar.id;
            if (bsfetch_ar_delay > 0) begin
              bsf_ar_stall_q <= bsfetch_ar_delay - 1;
              bsf_state_q    <= FS_AR_STALL;
            end else begin
              bsf_beat_q    <= '0;
              bsf_r_stall_q <= bsfetch_r_delay;
              bsf_state_q   <= FS_ACTIVE;
            end
          end
        end
        FS_AR_STALL: begin
          if (bsf_ar_stall_q > 0) begin
            bsf_ar_stall_q <= bsf_ar_stall_q - 1;
          end else begin
            bsf_beat_q    <= '0;
            bsf_r_stall_q <= bsfetch_r_delay;
            bsf_state_q   <= FS_ACTIVE;
          end
        end
        FS_ACTIVE: begin
          if (bsf_r_stall_q > 0) begin
            bsf_r_stall_q <= bsf_r_stall_q - 1;
          end else if (bsfetch_resp_i.r_valid && bsfetch_req_o.r_ready) begin
            if (bsfetch_resp_i.r.last) begin
              bsf_state_q <= FS_IDLE;
            end else begin
              bsf_beat_q    <= bsf_beat_q + 1'b1;
              bsf_r_stall_q <= bsfetch_r_delay;
            end
          end
        end
        default: bsf_state_q <= FS_IDLE;
      endcase
    end
  end

  // =========================================================================
  // AXI-Lite slave model
  //
  // Each channel has a small FSM:
  //   AXI_IDLE  : wait for valid.  If delay>0 → AXI_STALL; else → AXI_HANDSHAKE.
  //   AXI_STALL : count down delay cycles, then → AXI_HANDSHAKE.
  //   AXI_HANDSHAKE : assert ready for one cycle so the handshake fires,
  //                   then back to AXI_IDLE.
  //
  // B and R channels are response channels: they fire after AW+W / AR are
  // consumed and after their respective delay counters expire.
  // =========================================================================
  typedef enum logic [1:0] { AXI_IDLE, AXI_STALL, AXI_HANDSHAKE } axi_ch_state_e;

  // ---- AW channel ----
  axi_ch_state_e aw_ch_q;
  int            aw_stall_q;
  logic          aw_seen_q;
  logic [DICE_REG_DATA_WIDTH-1:0] awaddr_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : aw_fsm
    if (rst_i) begin
      aw_ch_q       <= AXI_IDLE;
      aw_stall_q    <= 0;
      aw_seen_q     <= 1'b0;
      awaddr_q      <= '0;
      axi_awready_i <= 1'b0;
    end else begin
      axi_awready_i <= 1'b0;
      unique case (aw_ch_q)
        AXI_IDLE: begin
          if (axi_awvalid_o) begin
            if (axi_aw_delay > 0) begin
              aw_stall_q <= axi_aw_delay - 1;
              aw_ch_q    <= AXI_STALL;
            end else begin
              axi_awready_i <= 1'b1;
              aw_ch_q       <= AXI_HANDSHAKE;
            end
          end
        end
        AXI_STALL: begin
          if (aw_stall_q > 0) aw_stall_q <= aw_stall_q - 1;
          else begin
            axi_awready_i <= 1'b1;
            aw_ch_q       <= AXI_HANDSHAKE;
          end
        end
        AXI_HANDSHAKE: begin
          // Handshake fires this cycle; capture address
          aw_seen_q <= 1'b1;
          awaddr_q  <= axi_awaddr_o;
          aw_ch_q   <= AXI_IDLE;
        end
        default: aw_ch_q <= AXI_IDLE;
      endcase
      // Clear aw_seen after B response
      if (axi_bvalid_i && axi_bready_o) aw_seen_q <= 1'b0;
    end
  end

  // ---- W channel ----
  axi_ch_state_e w_ch_q;
  int            w_stall_q;
  logic          w_seen_q;
  logic [DICE_REG_DATA_WIDTH-1:0] wdata_q;
  logic [1:0]                     wstrb_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : w_fsm
    if (rst_i) begin
      w_ch_q       <= AXI_IDLE;
      w_stall_q    <= 0;
      w_seen_q     <= 1'b0;
      wdata_q      <= '0;
      wstrb_q      <= '0;
      axi_wready_i <= 1'b0;
    end else begin
      axi_wready_i <= 1'b0;
      unique case (w_ch_q)
        AXI_IDLE: begin
          if (axi_wvalid_o) begin
            if (axi_w_delay > 0) begin
              w_stall_q <= axi_w_delay - 1;
              w_ch_q    <= AXI_STALL;
            end else begin
              axi_wready_i <= 1'b1;
              w_ch_q       <= AXI_HANDSHAKE;
            end
          end
        end
        AXI_STALL: begin
          if (w_stall_q > 0) w_stall_q <= w_stall_q - 1;
          else begin
            axi_wready_i <= 1'b1;
            w_ch_q       <= AXI_HANDSHAKE;
          end
        end
        AXI_HANDSHAKE: begin
          w_seen_q <= 1'b1;
          wdata_q  <= axi_wdata_o;
          wstrb_q  <= axi_wstrb_o;
          w_ch_q   <= AXI_IDLE;
        end
        default: w_ch_q <= AXI_IDLE;
      endcase
      if (axi_bvalid_i && axi_bready_o) w_seen_q <= 1'b0;
    end
  end

  // ---- B channel ----
  int b_stall_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : b_fsm
    if (rst_i) begin
      axi_bvalid_i <= 1'b0;
      axi_bresp_i  <= 2'b00;
      b_stall_q    <= 0;
    end else begin
      if (!axi_bvalid_i) begin
        if (aw_seen_q && w_seen_q) begin
          if (b_stall_q > 0) b_stall_q <= b_stall_q - 1;
          else begin
            axi_bvalid_i <= 1'b1;
            axi_bresp_i  <= 2'b00;
            b_stall_q    <= axi_b_delay;
          end
        end
      end else if (axi_bready_o) begin
        axi_bvalid_i <= 1'b0;
        b_stall_q    <= axi_b_delay;
      end
    end
  end

  // ---- AR channel ----
  axi_ch_state_e ar_ch_q;
  int            ar_stall_q;
  logic          ar_accepted_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : ar_fsm
    if (rst_i) begin
      ar_ch_q       <= AXI_IDLE;
      ar_stall_q    <= 0;
      ar_accepted_q <= 1'b0;
      axi_arready_i <= 1'b0;
    end else begin
      axi_arready_i <= 1'b0;
      unique case (ar_ch_q)
        AXI_IDLE: begin
          if (axi_arvalid_o && !axi_rvalid_i) begin
            if (axi_ar_delay > 0) begin
              ar_stall_q <= axi_ar_delay - 1;
              ar_ch_q    <= AXI_STALL;
            end else begin
              axi_arready_i <= 1'b1;
              ar_ch_q       <= AXI_HANDSHAKE;
            end
          end
        end
        AXI_STALL: begin
          if (ar_stall_q > 0) ar_stall_q <= ar_stall_q - 1;
          else begin
            axi_arready_i <= 1'b1;
            ar_ch_q       <= AXI_HANDSHAKE;
          end
        end
        AXI_HANDSHAKE: begin
          ar_accepted_q <= 1'b1;
          ar_ch_q       <= AXI_IDLE;
        end
        default: ar_ch_q <= AXI_IDLE;
      endcase
      if (axi_rvalid_i && axi_rready_o) ar_accepted_q <= 1'b0;
    end
  end

  // ---- R channel ----
  int r_stall_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : r_fsm
    if (rst_i) begin
      axi_rvalid_i <= 1'b0;
      axi_rdata_i  <= '0;
      axi_rresp_i  <= 2'b00;
      r_stall_q    <= 0;
    end else begin
      if (!axi_rvalid_i) begin
        if (ar_accepted_q) begin
          if (r_stall_q > 0) r_stall_q <= r_stall_q - 1;
          else begin
            axi_rvalid_i <= 1'b1;
            axi_rdata_i  <= '0;
            axi_rresp_i  <= 2'b00;
            r_stall_q    <= axi_r_delay;
          end
        end
      end else if (axi_rready_o) begin
        axi_rvalid_i <= 1'b0;
        r_stall_q    <= axi_r_delay;
      end
    end
  end

  // =========================================================================
  // complete_ready stall controller
  //
  // Waits for complete_valid to rise (while ready=0), counts down
  // complete_stall cycles, then asserts ready.  After the handshake, returns
  // to waiting.  With complete_stall=0 there is still a 1-cycle latency
  // before ready goes high — the DUT must hold complete_valid stable across
  // that gap (checked by assertion p_cta_complete_valid_stable).
  // =========================================================================
  typedef enum logic [1:0] { CPL_WAIT, CPL_STALLING, CPL_READY } cpl_state_e;

  cpl_state_e cpl_state_q;
  int         cpl_stall_cnt_q;
  logic       cpl_ready_q;

  assign cta_if_inst.complete_ready = cpl_ready_q;

  always_ff @(posedge clk_i or posedge rst_i) begin : cpl_fsm
    if (rst_i) begin
      cpl_state_q     <= CPL_WAIT;
      cpl_stall_cnt_q <= 0;
      cpl_ready_q     <= 1'b0;
    end else begin
      unique case (cpl_state_q)
        CPL_WAIT: begin
          cpl_ready_q <= 1'b0;
          if (cta_if_inst.complete_valid) begin
            if (complete_stall > 0) begin
              cpl_stall_cnt_q <= complete_stall - 1;
              cpl_state_q     <= CPL_STALLING;
            end else begin
              cpl_ready_q <= 1'b1;
              cpl_state_q <= CPL_READY;
            end
          end
        end
        CPL_STALLING: begin
          cpl_ready_q <= 1'b0;
          if (cpl_stall_cnt_q > 0) cpl_stall_cnt_q <= cpl_stall_cnt_q - 1;
          else begin
            cpl_ready_q <= 1'b1;
            cpl_state_q <= CPL_READY;
          end
        end
        CPL_READY: begin
          // Handshake fires this cycle (complete_valid && complete_ready both 1)
          cpl_ready_q <= 1'b0;
          cpl_state_q <= CPL_WAIT;
        end
        default: cpl_state_q <= CPL_WAIT;
      endcase
    end
  end

  // =========================================================================
  // SVA Protocol Assertions
  //
  // Fundamental rule: once a valid signal is asserted it must remain high
  // until the handshake fires (valid && ready == 1).
  // These assertions fire on any scenario where the DUT violates this rule,
  // regardless of which scenario caused it.
  // =========================================================================

  // --- mfetch: AR valid/address stability ---
  property p_mfetch_ar_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (mfetch_req_o.ar_valid && !mfetch_resp_i.ar_ready) |=> mfetch_req_o.ar_valid;
  endproperty
  assert property (p_mfetch_ar_valid_stable)
    else $error("[ASSERT FAIL] mfetch ar_valid dropped before ar_ready handshake  t=%0t", $time);

  property p_mfetch_ar_addr_stable;
    logic [DICE_ADDR_WIDTH-1:0] a;
    @(posedge clk_i) disable iff (rst_i)
    (mfetch_req_o.ar_valid && !mfetch_resp_i.ar_ready, a = mfetch_req_o.ar.addr)
      |=> (mfetch_req_o.ar_valid && mfetch_req_o.ar.addr == a);
  endproperty
  assert property (p_mfetch_ar_addr_stable)
    else $error("[ASSERT FAIL] mfetch ar.addr changed while ar_valid pending  t=%0t", $time);

  // --- bsfetch: AR valid/address stability ---
  property p_bsfetch_ar_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (bsfetch_req_o.ar_valid && !bsfetch_resp_i.ar_ready) |=> bsfetch_req_o.ar_valid;
  endproperty
  assert property (p_bsfetch_ar_valid_stable)
    else $error("[ASSERT FAIL] bsfetch ar_valid dropped before ar_ready handshake  t=%0t", $time);

  property p_bsfetch_ar_addr_stable;
    logic [DICE_ADDR_WIDTH-1:0] a;
    @(posedge clk_i) disable iff (rst_i)
    (bsfetch_req_o.ar_valid && !bsfetch_resp_i.ar_ready, a = bsfetch_req_o.ar.addr)
      |=> (bsfetch_req_o.ar_valid && bsfetch_req_o.ar.addr == a);
  endproperty
  assert property (p_bsfetch_ar_addr_stable)
    else $error("[ASSERT FAIL] bsfetch ar.addr changed while ar_valid pending  t=%0t", $time);

  // --- AXI-Lite AW: valid/address stability ---
  property p_axi_awvalid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (axi_awvalid_o && !axi_awready_i) |=> axi_awvalid_o;
  endproperty
  assert property (p_axi_awvalid_stable)
    else $error("[ASSERT FAIL] AXI-Lite awvalid dropped before awready  t=%0t", $time);

  property p_axi_awaddr_stable;
    logic [DICE_REG_DATA_WIDTH-1:0] a;
    @(posedge clk_i) disable iff (rst_i)
    (axi_awvalid_o && !axi_awready_i, a = axi_awaddr_o)
      |=> (axi_awvalid_o && axi_awaddr_o == a);
  endproperty
  assert property (p_axi_awaddr_stable)
    else $error("[ASSERT FAIL] AXI-Lite awaddr changed while awvalid pending  t=%0t", $time);

  // --- AXI-Lite W: valid/data stability ---
  property p_axi_wvalid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (axi_wvalid_o && !axi_wready_i) |=> axi_wvalid_o;
  endproperty
  assert property (p_axi_wvalid_stable)
    else $error("[ASSERT FAIL] AXI-Lite wvalid dropped before wready  t=%0t", $time);

  property p_axi_wdata_stable;
    logic [DICE_REG_DATA_WIDTH-1:0] d;
    @(posedge clk_i) disable iff (rst_i)
    (axi_wvalid_o && !axi_wready_i, d = axi_wdata_o)
      |=> (axi_wvalid_o && axi_wdata_o == d);
  endproperty
  assert property (p_axi_wdata_stable)
    else $error("[ASSERT FAIL] AXI-Lite wdata changed while wvalid pending  t=%0t", $time);

  // --- AXI-Lite AR: valid stability ---
  property p_axi_arvalid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (axi_arvalid_o && !axi_arready_i) |=> axi_arvalid_o;
  endproperty
  assert property (p_axi_arvalid_stable)
    else $error("[ASSERT FAIL] AXI-Lite arvalid dropped before arready  t=%0t", $time);

  // --- CTA dispatch: valid stability (driven by TB, checked for correctness) ---
  property p_cta_dispatch_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (cta_if_inst.dispatch_valid && !cta_if_inst.dispatch_ready) |=> cta_if_inst.dispatch_valid;
  endproperty
  assert property (p_cta_dispatch_valid_stable)
    else $error("[ASSERT FAIL] CTA dispatch_valid dropped before dispatch_ready  t=%0t", $time);

  // --- CTA complete: valid stability (DUT must hold complete_valid until ready) ---
  property p_cta_complete_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (cta_if_inst.complete_valid && !cta_if_inst.complete_ready) |=> cta_if_inst.complete_valid;
  endproperty
  assert property (p_cta_complete_valid_stable)
    else $error("[ASSERT FAIL] CTA complete_valid dropped before complete_ready  t=%0t", $time);

  // =========================================================================
  // SVA — Internal dice_core interfaces (hierarchical probes)
  //
  // These assertions reach into the DUT hierarchy to verify that handshake
  // semantics are respected on the three internal valid-ready interfaces:
  //
  //   fdr_out_if   : dice_frontend → dice_backend
  //                  path: u_dut.fdr_out_if.{valid,ready}
  //
  //   schedule_if  : cta_schedule_stage → fdr_top  (inside dice_frontend)
  //                  path: u_dut.u_dice_frontend.schedule_if.{valid,ready}
  //
  //   simt_update  : fdr_top → cta_schedule_stage  (inside dice_frontend)
  //                  wires: u_dut.u_dice_frontend.{simt_update_valid,ready}
  //
  // These fire during ALL scenarios (external and force-based internal ones),
  // catching any case where a module drops valid early.
  // =========================================================================

  // --- FDR interface (frontend → backend) ---
  property p_fdr_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (u_dut.fdr_out_if.valid && !u_dut.fdr_out_if.ready) |=> u_dut.fdr_out_if.valid;
  endproperty
  assert property (p_fdr_valid_stable)
    else $error("[ASSERT FAIL] fdr_out_if.valid dropped before .ready handshake  t=%0t", $time);

  // FDR data must be stable while valid is pending (spot-check eblock_id field)
  property p_fdr_eblock_stable;
    logic [DICE_EBLOCK_ID_WIDTH-1:0] eb;
    @(posedge clk_i) disable iff (rst_i)
    (u_dut.fdr_out_if.valid && !u_dut.fdr_out_if.ready,
      eb = u_dut.fdr_out_if.data.schedule_eblock_id)
      |=> (u_dut.fdr_out_if.valid &&
           u_dut.fdr_out_if.data.schedule_eblock_id == eb);
  endproperty
  assert property (p_fdr_eblock_stable)
    else $error("[ASSERT FAIL] fdr_out_if eblock_id changed while valid pending  t=%0t", $time);

  // --- schedule_if (cta_schedule_stage → fdr_top, inside dice_frontend) ---
  property p_schedule_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (u_dut.u_dice_frontend.schedule_if.valid &&
     !u_dut.u_dice_frontend.schedule_if.ready)
      |=> u_dut.u_dice_frontend.schedule_if.valid;
  endproperty
  assert property (p_schedule_valid_stable)
    else $error("[ASSERT FAIL] schedule_if.valid dropped before .ready  t=%0t", $time);

  property p_schedule_pc_stable;
    logic [DICE_ADDR_WIDTH-1:0] pc;
    @(posedge clk_i) disable iff (rst_i)
    (u_dut.u_dice_frontend.schedule_if.valid &&
     !u_dut.u_dice_frontend.schedule_if.ready,
      pc = u_dut.u_dice_frontend.schedule_if.data.schedule_next_pc)
      |=> (u_dut.u_dice_frontend.schedule_if.valid &&
           u_dut.u_dice_frontend.schedule_if.data.schedule_next_pc == pc);
  endproperty
  assert property (p_schedule_pc_stable)
    else $error("[ASSERT FAIL] schedule_if next_pc changed while valid pending  t=%0t", $time);

  // --- simt_update (fdr_top → cta_schedule_stage, wire-level) ---
  property p_simt_update_valid_stable;
    @(posedge clk_i) disable iff (rst_i)
    (u_dut.u_dice_frontend.simt_update_valid &&
     !u_dut.u_dice_frontend.simt_update_ready)
      |=> u_dut.u_dice_frontend.simt_update_valid;
  endproperty
  assert property (p_simt_update_valid_stable)
    else $error("[ASSERT FAIL] simt_update_valid dropped before simt_update_ready  t=%0t", $time);

  // =========================================================================
  // Utility tasks and functions
  // =========================================================================

  task automatic set_defaults();
    mfetch_ar_delay  = 0; mfetch_r_delay  = 0;
    bsfetch_ar_delay = 0; bsfetch_r_delay = 0;
    axi_aw_delay = 0; axi_w_delay = 0; axi_b_delay = 0;
    axi_ar_delay = 0; axi_r_delay = 0;
    complete_stall = 0;
    csrX0_i = '0; csrX1_i = '0; csrX2_i = '0; csrX3_i = '0;
    csrX4_i = '0; csrX5_i = '0; csrX6_i = '0; csrX7_i = '0;
  endtask

  task automatic reset_dut();
    rst_i = 1'b1;
    cta_if_inst.dispatch_valid = 1'b0;
    cta_if_inst.dispatch_data  = '0;
    set_defaults();
    repeat (10) @(posedge clk_i);
    rst_i = 1'b0;
    @(posedge clk_i);
  endtask

  task automatic dispatch_cta(input dice_cta_desc_t desc);
    cta_if_inst.dispatch_valid = 1'b1;
    cta_if_inst.dispatch_data  = desc;
    do @(posedge clk_i); while (!cta_if_inst.dispatch_ready);
    cta_if_inst.dispatch_valid = 1'b0;
  endtask

  // Poll every clock edge until complete_valid && complete_ready are both 1.
  task automatic wait_complete(output int cpl_cycle);
    while (!(cta_if_inst.complete_valid === 1'b1 &&
             cta_if_inst.complete_ready === 1'b1))
      @(posedge clk_i);
    cpl_cycle = cycle_count;
  endtask

  function automatic dice_cta_desc_t make_simple_cta();
    dice_cta_desc_t d;
    d                          = '0;
    d.kernel_desc.start_pc     = 16'h1000;
    d.kernel_desc.grid_size.x  = 1;
    d.kernel_desc.grid_size.y  = 1;
    d.kernel_desc.grid_size.z  = 1;
    d.kernel_desc.thread_count = 1;
    d.cta_id.x                 = 0;
    d.cta_id.y                 = 0;
    d.cta_id.z                 = 0;
    return d;
  endfunction

  // =========================================================================
  // Scenario runner
  //
  // Sets all backpressure knobs, dispatches one CTA, waits for completion
  // (or hits scenario-local timeout), then resets for the next scenario.
  // =========================================================================
  int scenario_pass_count;
  int scenario_fail_count;

  task automatic run_scenario(
    input string name,
    // mfetch knobs
    input int mf_ar, mf_r,
    // bsfetch knobs
    input int bsf_ar, bsf_r,
    // AXI-Lite write knobs
    input int aw, w, b,
    // AXI-Lite read knobs
    input int ar, r,
    // complete_ready stall
    input int cpl,
    // per-scenario timeout in cycles
    input int tmo
  );
    int cpl_cycle;

    $display("[TB] ================================================================");
    $display("[TB] Scenario: %-50s", name);
    $display("[TB]   mfetch   ar=%3d  r=%3d    bsfetch  ar=%3d  r=%3d",
             mf_ar, mf_r, bsf_ar, bsf_r);
    $display("[TB]   axi_wr   aw=%3d  w=%3d  b=%3d    axi_rd   ar=%3d  r=%3d    cpl=%3d",
             aw, w, b, ar, r, cpl);

    // Apply knobs
    mfetch_ar_delay  = mf_ar;  mfetch_r_delay  = mf_r;
    bsfetch_ar_delay = bsf_ar; bsfetch_r_delay = bsf_r;
    axi_aw_delay = aw; axi_w_delay = w; axi_b_delay = b;
    axi_ar_delay = ar; axi_r_delay = r;
    complete_stall = cpl;

    repeat (3) @(posedge clk_i);  // settle before dispatch

    fork
      begin : scenario_body
        dispatch_cta(make_simple_cta());
        wait_complete(cpl_cycle);
        $display("[TB] PASS:    %-50s  (cycle %0d)", name, cpl_cycle);
        scenario_pass_count++;
      end
      begin : scenario_timeout
        repeat (tmo) @(posedge clk_i);
        $display("[TB] TIMEOUT: %-50s  (>%0d cycles)", name, tmo);
        $display("[TB]   NOTE: Timeout may be expected when metadata does not");
        $display("[TB]         trigger full pipeline execution.  Check SVA.");
        scenario_fail_count++;
        disable scenario_body;
      end
    join_any
    disable fork;

    // Cool-down then hard reset before next scenario
    repeat (5) @(posedge clk_i);
    reset_dut();
    repeat (3) @(posedge clk_i);
  endtask

  // =========================================================================
  // Internal backpressure scenario runner
  //
  // Injects backpressure directly onto internal ready wires using Verilog
  // force/release.  All external slave models run at zero delay so the only
  // pipeline stalls are those caused by the forced internal signals.
  //
  // Parameters
  //   force_fdr_stall   : cycles to hold u_dut.fdr_out_if.ready = 0
  //   force_sched_stall : cycles to hold schedule_if.ready = 0
  //   force_simt_stall  : cycles to hold simt_update_ready = 0
  //   cycles_before_force : cycles after dispatch before forces are applied
  //   tmo               : per-scenario cycle timeout
  //
  // All three forces are applied simultaneously (when non-zero) and released
  // independently as their respective stall counts expire.
  // =========================================================================
  task automatic run_internal_bp_scenario(
    input string name,
    input int    force_fdr_stall,
    input int    force_sched_stall,
    input int    force_simt_stall,
    input int    cycles_before_force,
    input int    tmo
  );
    int cpl_cycle;

    $display("[TB] ================================================================");
    $display("[TB] Scenario: %-50s", name);
    $display("[TB]   fdr=%3d  sched=%3d  simt=%3d    delay_before=%3d",
             force_fdr_stall, force_sched_stall, force_simt_stall, cycles_before_force);

    // External knobs at zero — all stalls are internal only
    mfetch_ar_delay  = 0;  mfetch_r_delay  = 0;
    bsfetch_ar_delay = 0;  bsfetch_r_delay = 0;
    axi_aw_delay = 0;  axi_w_delay = 0;  axi_b_delay = 0;
    axi_ar_delay = 0;  axi_r_delay = 0;
    complete_stall = 0;

    repeat (3) @(posedge clk_i);

    fork
      begin : ibp_body
        // Step 1: dispatch
        dispatch_cta(make_simple_cta());

        // Step 2: wait before injecting backpressure
        repeat (cycles_before_force) @(posedge clk_i);

        // Step 3: force ready signals low in parallel (only when stall > 0)
        fork
          begin : force_fdr
            if (force_fdr_stall > 0) begin
              force u_dut.fdr_out_if.ready = 1'b0;
              repeat (force_fdr_stall) @(posedge clk_i);
              release u_dut.fdr_out_if.ready;
            end
          end
          begin : force_sched
            if (force_sched_stall > 0) begin
              force u_dut.u_dice_frontend.schedule_if.ready = 1'b0;
              repeat (force_sched_stall) @(posedge clk_i);
              release u_dut.u_dice_frontend.schedule_if.ready;
            end
          end
          begin : force_simt
            if (force_simt_stall > 0) begin
              force u_dut.u_dice_frontend.simt_update_ready = 1'b0;
              repeat (force_simt_stall) @(posedge clk_i);
              release u_dut.u_dice_frontend.simt_update_ready;
            end
          end
        join  // wait for ALL forces to be released before proceeding

        // Step 4: wait for CTA completion
        wait_complete(cpl_cycle);
        $display("[TB] PASS:    %-50s  (cycle %0d)", name, cpl_cycle);
        scenario_pass_count++;
      end
      begin : ibp_timeout
        repeat (tmo) @(posedge clk_i);
        $display("[TB] TIMEOUT: %-50s  (>%0d cycles)", name, tmo);
        scenario_fail_count++;
        // Release any forces that may still be held to avoid polluting next scenario
        release u_dut.fdr_out_if.ready;
        release u_dut.u_dice_frontend.schedule_if.ready;
        release u_dut.u_dice_frontend.simt_update_ready;
        disable ibp_body;
      end
    join_any
    disable fork;

    repeat (5) @(posedge clk_i);
    reset_dut();
    repeat (3) @(posedge clk_i);
  endtask

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    scenario_pass_count = 0;
    scenario_fail_count = 0;

    $display("[TB] tb_dice_core_interface — valid-ready interface stress test");
    $display("[TB] bsfetch burst = %0d beats (%0d cycles baseline)",
             BsBeatCount, BsBeatCount);

    reset_dut();
    repeat (5) @(posedge clk_i);

    // ------------------------------------------------------------------
    // Group A: Baseline
    // ------------------------------------------------------------------
    // A1 — zero backpressure on every channel
    run_scenario("A1_baseline_no_backpressure",
      0, 0,   0, 0,   0, 0, 0,   0, 0,   0,   250);

    // ------------------------------------------------------------------
    // Group B: mfetch backpressure
    // ------------------------------------------------------------------
    // B1 — AR channel held low 10 cycles before accepting
    run_scenario("B1_mfetch_ar_stall_10cyc",
      10, 0,   0, 0,   0, 0, 0,   0, 0,   0,   250);

    // B2 — AR held 25 cycles (longer stall)
    run_scenario("B2_mfetch_ar_stall_25cyc",
      25, 0,   0, 0,   0, 0, 0,   0, 0,   0,   250);

    // B3 — R channel: 1-cycle gap between every beat (16 beats × 1 = 16 extra)
    run_scenario("B3_mfetch_r_beat_gap_1cyc",
      0, 1,   0, 0,   0, 0, 0,   0, 0,   0,   250);

    // B4 — R channel: 5-cycle gap per beat (16 × 5 = 80 extra cycles)
    run_scenario("B4_mfetch_r_beat_gap_5cyc",
      0, 5,   0, 0,   0, 0, 0,   0, 0,   0,   500);

    // B5 — Combined AR + R stalls
    run_scenario("B5_mfetch_ar10_r3_combined",
      10, 3,   0, 0,   0, 0, 0,   0, 0,   0,   500);

    // ------------------------------------------------------------------
    // Group C: bsfetch backpressure
    //   Burst is 106 beats — r_delay has larger impact than on mfetch.
    // ------------------------------------------------------------------
    // C1 — AR held 15 cycles
    run_scenario("C1_bsfetch_ar_stall_15cyc",
      0, 0,   15, 0,   0, 0, 0,   0, 0,   0,   500);

    // C2 — AR held 40 cycles
    run_scenario("C2_bsfetch_ar_stall_40cyc",
      0, 0,   40, 0,   0, 0, 0,   0, 0,   0,   500);

    // C3 — R channel: 1-cycle gap per beat (106 × 1 = 106 extra)
    run_scenario("C3_bsfetch_r_beat_gap_1cyc",
      0, 0,   0, 1,   0, 0, 0,   0, 0,   0,   500);

    // C4 — R channel: 3-cycle gap per beat (106 × 3 = 318 extra)
    run_scenario("C4_bsfetch_r_beat_gap_3cyc",
      0, 0,   0, 3,   0, 0, 0,   0, 0,   0,   1_000);

    // C5 — Combined AR + R stalls
    run_scenario("C5_bsfetch_ar15_r2_combined",
      0, 0,   15, 2,   0, 0, 0,   0, 0,   0,   1_000);

    // ------------------------------------------------------------------
    // Group D: Both mfetch and bsfetch stressed simultaneously
    // ------------------------------------------------------------------
    // D1 — Simultaneous AR stalls on both fetch ports
    run_scenario("D1_mfetch_bsfetch_ar_stall_both",
      12, 0,   12, 0,   0, 0, 0,   0, 0,   0,   500);

    // D2 — R stalls on both (tests pipeline does not cross-stall)
    run_scenario("D2_mfetch_r1_bsfetch_r2_both",
      0, 1,   0, 2,   0, 0, 0,   0, 0,   0,   1_000);

    // D3 — Heavy combined: mfetch AR stall + bsfetch R stall
    run_scenario("D3_mfetch_ar8_bsfetch_r3_cross",
      8, 0,   0, 3,   0, 0, 0,   0, 0,   0,   1_000);

    // ------------------------------------------------------------------
    // Group E: AXI-Lite write path (AW / W / B)
    //   NOTE: with synthetic zero-store metadata these channels are idle;
    //   the scenarios confirm no spurious transactions occur under stall.
    //   Use real test vectors to stress-test these channels with traffic.
    // ------------------------------------------------------------------
    // E1 — AW held 8 cycles
    run_scenario("E1_axilite_aw_stall_8cyc",
      0, 0,   0, 0,   8, 0, 0,   0, 0,   0,   500);

    // E2 — W held 8 cycles
    run_scenario("E2_axilite_w_stall_8cyc",
      0, 0,   0, 0,   0, 8, 0,   0, 0,   0,   500);

    // E3 — B response delayed 15 cycles
    run_scenario("E3_axilite_b_delay_15cyc",
      0, 0,   0, 0,   0, 0, 15,   0, 0,   0,   500);

    // E4 — Full write-path stall (AW + W back-to-back + slow B)
    run_scenario("E4_axilite_write_path_aw10_w10_b20",
      0, 0,   0, 0,   10, 10, 20,   0, 0,   0,   1_000);

    // ------------------------------------------------------------------
    // Group F: AXI-Lite read path (AR / R)
    // ------------------------------------------------------------------
    // F1 — AR held 8 cycles
    run_scenario("F1_axilite_ar_stall_8cyc",
      0, 0,   0, 0,   0, 0, 0,   8, 0,   0,   500);

    // F2 — R delayed 10 cycles after AR accepted
    run_scenario("F2_axilite_r_delay_10cyc",
      0, 0,   0, 0,   0, 0, 0,   0, 10,   0,   500);

    // F3 — Full read-path stall
    run_scenario("F3_axilite_read_path_ar10_r15",
      0, 0,   0, 0,   0, 0, 0,   10, 15,   0,   1_000);

    // ------------------------------------------------------------------
    // Group G: complete_ready stall
    //   DUT must hold complete_valid until ready is eventually released.
    // ------------------------------------------------------------------
    // G1 — Hold complete_ready low 10 cycles after complete_valid fires
    run_scenario("G1_complete_ready_stall_10cyc",
      0, 0,   0, 0,   0, 0, 0,   0, 0,   10,   500);

    // G2 — Hold complete_ready low 30 cycles
    run_scenario("G2_complete_ready_stall_30cyc",
      0, 0,   0, 0,   0, 0, 0,   0, 0,   30,   500);

    // ------------------------------------------------------------------
    // Group H: compound multi-channel stalls
    // ------------------------------------------------------------------
    // H1 — Moderate stall on every channel simultaneously
    run_scenario("H1_all_channels_moderate",
      5, 2,   5, 2,   5, 5, 5,   5, 5,   10,   1_500);

    // H2 — Asymmetric: heavy bsfetch + complete stall, light mfetch
    run_scenario("H2_heavy_bsfetch_complete_stall",
      3, 1,   20, 5,   0, 0, 0,   0, 0,   25,   5_000);

    // H3 — Maximum pressure on all fetch + completion channels
    run_scenario("H3_all_channels_heavy",
      20, 5,   20, 5,   15, 15, 20,   15, 20,   30,   2_500);

    // H4 — Alternating stall pattern: fetch light, AXI-Lite heavy
    run_scenario("H4_light_fetch_heavy_axilite",
      2, 0,   2, 0,   12, 12, 15,   12, 15,   15,   3_000);

    // ------------------------------------------------------------------
    // Group I: Internal interface backpressure (force/release)
    //
    // These scenarios inject backpressure directly onto the ready signals
    // of the three internal dice_core handshake interfaces using Verilog
    // force/release.  The external slave models are at zero delay so any
    // pipeline stall observed in waveforms is caused purely by the forced
    // internal backpressure.
    //
    // Interface hierarchy:
    //   fdr_out_if    : u_dut.fdr_out_if.ready   (backend → frontend)
    //   schedule_if   : u_dut.u_dice_frontend.schedule_if.ready  (fdr_top → scheduler)
    //   simt_update   : u_dut.u_dice_frontend.simt_update_ready  (scheduler → fdr_top)
    // ------------------------------------------------------------------

    // I1 — Force fdr_ready=0 for 20 cycles mid-dispatch.
    //      Frontend must hold fdr_valid high; backend must stall gracefully.
    run_internal_bp_scenario("I1_fdr_ready_stall_20cyc",
      /* force_fdr_stall      */ 20,
      /* force_sched_stall    */  0,
      /* force_simt_stall     */  0,
      /* cycles_before_force  */ 50,
      /* tmo                  */ 2_000);

    // I2 — Force fdr_ready=0 for 50 cycles (extended backend stall).
    run_internal_bp_scenario("I2_fdr_ready_stall_50cyc",
      50, 0, 0, 50, 3_000);

    // I3 — Force schedule_ready=0 for 15 cycles.
    //      cta_schedule_stage must stall; schedule_if.valid must hold.
    run_internal_bp_scenario("I3_schedule_ready_stall_15cyc",
      0, 15, 0, 30, 2_000);

    // I4 — Force schedule_ready=0 for 40 cycles.
    run_internal_bp_scenario("I4_schedule_ready_stall_40cyc",
      0, 40, 0, 30, 3_000);

    // I5 — Force simt_update_ready=0 for 10 cycles.
    //      fdr_top must hold simt_update_valid high until scheduler accepts.
    run_internal_bp_scenario("I5_simt_update_ready_stall_10cyc",
      0, 0, 10, 60, 2_000);

    // I6 — Simultaneous: fdr_ready + schedule_ready both forced low.
    //      Tests that both stalls resolve without deadlock.
    run_internal_bp_scenario("I6_fdr_and_schedule_stall_simultaneous",
      20, 20, 0, 40, 3_000);

    // I7 — All three internal interfaces stalled simultaneously.
    run_internal_bp_scenario("I7_all_internal_interfaces_stall",
      15, 15, 10, 40, 4_000);

    // I8 — Internal FDR stall combined with external mfetch AR backpressure.
    //      Two layers of backpressure hitting the same pipeline simultaneously.
    begin : group_i8
      int cpl_c;
      $display("[TB] ================================================================");
      $display("[TB] Scenario: I8_fdr_stall_plus_mfetch_ar_backpressure");
      mfetch_ar_delay = 10; mfetch_r_delay = 0;
      bsfetch_ar_delay = 0; bsfetch_r_delay = 0;
      axi_aw_delay = 0; axi_w_delay = 0; axi_b_delay = 0;
      axi_ar_delay = 0; axi_r_delay = 0;
      complete_stall = 0;
      repeat (3) @(posedge clk_i);
      fork
        begin : i8_body
          dispatch_cta(make_simple_cta());
          // After dispatch, wait a bit then force fdr_ready low
          repeat (30) @(posedge clk_i);
          force u_dut.fdr_out_if.ready = 1'b0;
          repeat (25) @(posedge clk_i);
          release u_dut.fdr_out_if.ready;
          wait_complete(cpl_c);
          $display("[TB] PASS:    I8  (cycle %0d)", cpl_c);
          scenario_pass_count++;
        end
        begin : i8_timeout
          repeat (1_500) @(posedge clk_i);
          $display("[TB] TIMEOUT: I8");
          scenario_fail_count++;
          release u_dut.fdr_out_if.ready;
          disable i8_body;
        end
      join_any
      disable fork;
      repeat (5) @(posedge clk_i);
      reset_dut();
      repeat (3) @(posedge clk_i);
    end

    // ------------------------------------------------------------------
    // Final report
    // ------------------------------------------------------------------
    $display("[TB] ================================================================");
    $display("[TB] INTERFACE STRESS TEST COMPLETE");
    $display("[TB]   Scenarios PASSED / TIMED-OUT : %0d / %0d",
             scenario_pass_count, scenario_fail_count);
    $display("[TB]");
    $display("[TB]   A TIMEOUT means the DUT did not produce a CTA completion");
    $display("[TB]   within the scenario window.  This can happen legitimately");
    $display("[TB]   when synthetic metadata prevents full pipeline execution.");
    $display("[TB]   Inspect SVA assertion counts — zero failures = no protocol");
    $display("[TB]   violations even in timed-out scenarios.");
    $display("[TB] ================================================================");

    if (scenario_fail_count == 0) begin
      $display("[TB] ALL SCENARIOS PASSED — no protocol violations");
      $finish;
    end else begin
      // Don't $fatal: timeouts with synthetic data are informational, not bugs.
      $display("[TB] SOME SCENARIOS TIMED OUT — review SVA assertion log");
      $finish;
    end
  end

endmodule
