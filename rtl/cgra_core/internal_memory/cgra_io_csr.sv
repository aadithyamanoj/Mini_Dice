// cgra_io_csr.sv
//
// Purpose-built CSR bank for the CGRA IO subsystem.
// Sits on the crossbar's cgra_csr master port (0x0000–0x00FF).
//
// Register map (byte-addressed, 16-bit words, stride = 2):
//
//   Offset  Name              Dir   Description
//   0x00    CTRL              R/W   [0] start (self-clearing 1-cycle pulse)
//                                   [1] cgra_reset (level, active-high)
//                                   [2] bsload_en  (level)
//   0x02    START_PC          R/W   16-bit warp entry PC
//   0x04    STATUS            RO    [0] complete   (sticky, clears on next start)
//                                   [1] busy       (live from hardware)
//                                   [2] dispatching(live from hardware)
//                                   [3] stack_overflow (sticky, clears on next start)
//   0x06    BSLOAD_CNT        RO    Bitstream load word counter (from hardware)
//   0x08    SIMT_STACK_DEPTH  RO    Current SIMT stack depth (from hardware)
//   0x0A    ERROR_INFO        RO    Error address / code (sticky, clears on reset or start)
//   0x0C    RSVD_6            R/W   Reserved
//   0x0E    RSVD_7            R/W   Reserved
//   0x10    CSRX0             RO    Input-only CSR source 0 (from hardware)
//   0x12    CSRX1             RO    Input-only CSR source 1 (from hardware)
//   0x14    CSRX2             RO    Input-only CSR source 2 (from hardware)
//   0x16    CSRX3             RO    Input-only CSR source 3 (from hardware)
//   0x18    CSRX4             RO    Input-only CSR source 4 (from hardware)
//   0x1A    CSRX5             RO    Input-only CSR source 5 (from hardware)
//   0x1C    CSRX6             RO    Input-only CSR source 6 (from hardware)
//   0x1E    CSRX7             RO    Input-only CSR source 7 (from hardware)
//
// AXI4 notes:
//   - Treats all accesses as single-beat (ignores AWLEN/ARLEN).
//   - Echoes IDs on B and R channels so the crossbar can route responses correctly.
//   - Writes to RO registers are silently ignored.

`ifndef AXI_TYPEDEF_SVH_
`include "axi/typedef.svh"
`endif

module cgra_io_csr
  import axi4_xbar_pkg::*;
  import axi_pkg::*;
  import DE_pkg::*;
(
  input  logic clk_i,
  input  logic rst_i,

  // --------------------------------------------------------------------------
  // AXI4 slave port — driven by the crossbar's cgra_csr master port
  // --------------------------------------------------------------------------
  input  mst_req_t  axi_req_i,
  output mst_resp_t axi_resp_o,

  // --------------------------------------------------------------------------
  // Hardware outputs (CSR → CGRA core)
  // --------------------------------------------------------------------------
  output logic        start_o,             // 1-cycle pulse: begin execution
  output logic [15:0] start_pc_o,          // warp entry PC
  output logic        cgra_reset_o,        // active-high reset to CGRA core
  output logic        bsload_en_o,         // initiate bitstream load

  // --------------------------------------------------------------------------
  // Hardware inputs (CGRA core → CSR)
  // --------------------------------------------------------------------------
  input  logic        hw_busy_i,           // CGRA is running
  input  logic        hw_complete_i,       // pulse: execution finished
  input  logic        hw_dispatching_i,    // dispatcher is active
  input  logic        hw_stack_overflow_i, // pulse: SIMT stack overflow detected
  input  logic [15:0] hw_stack_depth_i,    // current SIMT stack entries
  input  logic [15:0] hw_error_info_i,     // error address or code (valid on overflow)
  input  logic [15:0] hw_bsload_cnt_i,     // bitstream load word counter

  // --------------------------------------------------------------------------
  // Input-only CSR sources exposed to the CGRA input crossbar
  // --------------------------------------------------------------------------
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX1_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX2_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX3_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX5_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX6_i,
  input logic [DICE_REG_DATA_WIDTH-1:0] csrX7_i
);

  // --------------------------------------------------------------------------
  // Register indices
  // --------------------------------------------------------------------------
  localparam int NUM_REGS   = 16;
  localparam int REG_CTRL   = 0;  // 0x00
  localparam int REG_PC     = 1;  // 0x02
  localparam int REG_STATUS = 2;  // 0x04
  localparam int REG_BSLOAD = 3;  // 0x06
  localparam int REG_STACK  = 4;  // 0x08
  localparam int REG_ERROR  = 5;  // 0x0A
  localparam int REG_RSVD6  = 6;  // 0x0C
  localparam int REG_RSVD7  = 7;  // 0x0E
  localparam int REG_CSRX0  = 8;  // 0x10
  localparam int REG_CSRX1  = 9;  // 0x12
  localparam int REG_CSRX2  = 10; // 0x14
  localparam int REG_CSRX3  = 11; // 0x16
  localparam int REG_CSRX4  = 12; // 0x18
  localparam int REG_CSRX5  = 13; // 0x1A
  localparam int REG_CSRX6  = 14; // 0x1C
  localparam int REG_CSRX7  = 15; // 0x1E

  // --------------------------------------------------------------------------
  // R/W register storage (CTRL, START_PC, RSVD6, RSVD7)
  // --------------------------------------------------------------------------
  logic [15:0] ctrl_r;
  logic [15:0] start_pc_r;
  logic [15:0] rsvd6_r, rsvd7_r;

  // --------------------------------------------------------------------------
  // Hardware-written sticky bits
  // --------------------------------------------------------------------------
  logic complete_sticky_r;
  logic stack_overflow_sticky_r;
  logic [15:0] error_info_sticky_r;

  // --------------------------------------------------------------------------
  // AXI write path
  // --------------------------------------------------------------------------
  logic              aw_pending_r;
  logic [3:0]        aw_idx_r;      // register index latched from AW address
  mst_id_t           aw_id_r;       // ID to echo on B channel

  // AW handshake: accept when no write is already pending
  assign axi_resp_o.aw_ready = ~aw_pending_r;

  // W handshake: accept once AW has been latched
  assign axi_resp_o.w_ready  = aw_pending_r;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      aw_pending_r <= 1'b0;
      aw_idx_r     <= '0;
      aw_id_r      <= '0;
    end else begin
      if (axi_req_i.aw_valid && axi_resp_o.aw_ready) begin
        aw_pending_r <= 1'b1;
        // addr[4:1] selects one of 16 registers (byte-stride 2, drop bit[0])
        aw_idx_r     <= axi_req_i.aw.addr[4:1];
        aw_id_r      <= axi_req_i.aw.id;
      end else if (aw_pending_r && axi_req_i.w_valid) begin
        aw_pending_r <= 1'b0;
      end
    end
  end

  logic        do_write;
  logic [15:0] wr_data;
  assign do_write = aw_pending_r && axi_req_i.w_valid;
  // Byte-lane strobe merge
  assign wr_data[7:0]  = axi_req_i.w.strb[0] ? axi_req_i.w.data[7:0]  : 8'h00;
  assign wr_data[15:8] = axi_req_i.w.strb[1] ? axi_req_i.w.data[15:8] : 8'h00;

  // --------------------------------------------------------------------------
  // AXI read path
  // --------------------------------------------------------------------------
  logic        ar_pending_r;
  logic [3:0]  ar_idx_r;
  mst_id_t     ar_id_r;

  assign axi_resp_o.ar_ready = ~ar_pending_r;

  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ar_pending_r <= 1'b0;
      ar_idx_r     <= '0;
      ar_id_r      <= '0;
    end else begin
      if (axi_req_i.ar_valid && axi_resp_o.ar_ready) begin
        ar_pending_r <= 1'b1;
        ar_idx_r     <= axi_req_i.ar.addr[4:1];
        ar_id_r      <= axi_req_i.ar.id;
      end else if (ar_pending_r && axi_req_i.r_ready) begin
        ar_pending_r <= 1'b0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Register reads (combinatorial from stored state)
  // --------------------------------------------------------------------------
  logic [15:0] rd_data;
  always_comb begin
    rd_data = '0;
    unique case (ar_idx_r)
      4'(REG_CTRL):   rd_data = ctrl_r;
      4'(REG_PC):     rd_data = start_pc_r;
      4'(REG_STATUS): rd_data = {12'b0,
                                  stack_overflow_sticky_r,  // [3]
                                  hw_dispatching_i,         // [2]
                                  hw_busy_i,                // [1]
                                  complete_sticky_r};       // [0]
      4'(REG_BSLOAD): rd_data = hw_bsload_cnt_i;
      4'(REG_STACK):  rd_data = hw_stack_depth_i;
      4'(REG_ERROR):  rd_data = error_info_sticky_r;
      4'(REG_RSVD6):  rd_data = rsvd6_r;
      4'(REG_RSVD7):  rd_data = rsvd7_r;
      4'(REG_CSRX0):  rd_data = csrX0_i;
      4'(REG_CSRX1):  rd_data = csrX1_i;
      4'(REG_CSRX2):  rd_data = csrX2_i;
      4'(REG_CSRX3):  rd_data = csrX3_i;
      4'(REG_CSRX4):  rd_data = csrX4_i;
      4'(REG_CSRX5):  rd_data = csrX5_i;
      4'(REG_CSRX6):  rd_data = csrX6_i;
      4'(REG_CSRX7):  rd_data = csrX7_i;
      default:        rd_data = '0;
    endcase
  end

  // --------------------------------------------------------------------------
  // R channel output
  // --------------------------------------------------------------------------
  assign axi_resp_o.r_valid  = ar_pending_r;
  assign axi_resp_o.r.data   = axi_data_t'(rd_data);
  assign axi_resp_o.r.resp   = RESP_OKAY;
  assign axi_resp_o.r.last   = 1'b1;
  assign axi_resp_o.r.id     = ar_id_r;
  assign axi_resp_o.r.user   = '0;

  // --------------------------------------------------------------------------
  // B channel output
  // --------------------------------------------------------------------------
  assign axi_resp_o.b_valid  = do_write;
  assign axi_resp_o.b.resp   = RESP_OKAY;
  assign axi_resp_o.b.id     = aw_id_r;
  assign axi_resp_o.b.user   = '0;

  // --------------------------------------------------------------------------
  // R/W register updates + hardware sticky bits
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      ctrl_r                  <= '0;
      start_pc_r              <= '0;
      rsvd6_r                 <= '0;
      rsvd7_r                 <= '0;
      complete_sticky_r       <= 1'b0;
      stack_overflow_sticky_r <= 1'b0;
      error_info_sticky_r     <= '0;
    end else begin

      // --- CTRL: start bit self-clears one cycle after being written --------
      ctrl_r[0] <= 1'b0;  // default: clear start each cycle

      // --- AXI host writes --------------------------------------------------
      if (do_write) begin
        unique case (aw_idx_r)
          4'(REG_CTRL): begin
            ctrl_r    <= wr_data;          // start bit set here, clears next cycle
          end
          4'(REG_PC):   start_pc_r <= wr_data;
          4'(REG_RSVD6): rsvd6_r  <= wr_data;
          4'(REG_RSVD7): rsvd7_r  <= wr_data;
          default: ;  // RO registers: ignore writes
        endcase
      end

      // --- Hardware status updates ------------------------------------------
      // complete: set by hw pulse, cleared when a new start is issued
      if (hw_complete_i)
        complete_sticky_r <= 1'b1;
      else if (ctrl_r[0])  // start pulse clears complete
        complete_sticky_r <= 1'b0;

      // stack overflow: set by hw pulse, cleared on reset or new start
      if (hw_stack_overflow_i) begin
        stack_overflow_sticky_r <= 1'b1;
        error_info_sticky_r     <= hw_error_info_i;
      end else if (ctrl_r[0]) begin
        stack_overflow_sticky_r <= 1'b0;
        error_info_sticky_r     <= '0;
      end

    end
  end

  // --------------------------------------------------------------------------
  // Hardware output assignments
  // --------------------------------------------------------------------------
  assign start_o       = ctrl_r[0];   // 1-cycle pulse (self-clearing bit)
  assign cgra_reset_o  = ctrl_r[1];
  assign bsload_en_o   = ctrl_r[2];
  assign start_pc_o    = start_pc_r;

endmodule : cgra_io_csr
