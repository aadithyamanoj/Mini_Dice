// Miss Status Holding Register Table
//
// Tracks 16 outstanding memory requests issued by the 4x4 CGRA via the
// memory crossbar (mem_addr_o / mem_data_o).  Each entry stores the
// coalesced-request metadata expected by dice_backend.sv and transitions
// through three states:
//
//   FREE -> PENDING  : allocation (valid/ready from dice_backend)
//   PENDING -> FREE  : store accepted by memory (no writeback needed)
//   PENDING -> DONE  : load response received from memory
//   DONE    -> FREE  : response drained to dice_backend mem_rsp_* ports
//
// Parameters match DE_pkg (used by dice_backend.sv):
//   CACHE_LINE_SIZE                   = 32 bytes  → data field 256 bits
//   NUMBER_OF_MAX_COALESCED_COMMANDS  = 8          → bitmap / address_map
//   TID_BITMAP_WIDTH                  = 8
//   BASE_ADDRESS_OFFSET               = 5

`include "dice_define.vh"

module mshr_table
  import dice_pkg::*;
  import DE_pkg::*;
#(
  parameter  int NUM_MSHR      = 16,
  localparam int MSHR_ID_WIDTH = $clog2(NUM_MSHR)   // 4 bits
)(
  input  logic clk_i,
  input  logic rst_i,

  // -------------------------------------------------------------------------
  // Allocation port — from dice_backend / memory coalescing buffer
  // Carries the coalesced-request metadata plus the crossbar outputs.
  // -------------------------------------------------------------------------
  input  logic                                                              alloc_valid_i,
  output logic                                                              alloc_ready_o,    // high while a free slot exists

  input  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                 alloc_base_tid_i,
  input  logic [TID_BITMAP_WIDTH-1:0]                                       alloc_tid_bitmap_i,
  input  logic [DICE_REG_ADDR_WIDTH-1:0]                                   alloc_ld_dest_reg_i,
  input  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0]
               [BASE_ADDRESS_OFFSET-1:0]                                   alloc_address_map_i,
  input  logic [7:0]                                                        alloc_addr_i,     // mem_addr_o from crossbar
  input  logic [7:0]                                                        alloc_data_i,     // mem_data_o from crossbar
  input  logic                                                              alloc_write_en_i, // 0=load  1=store

  // -------------------------------------------------------------------------
  // Memory request port — outbound to off-chip / SRAM memory
  // -------------------------------------------------------------------------
  output logic                     mem_req_valid_o,
  input  logic                     mem_req_ready_i,
  output logic [MSHR_ID_WIDTH-1:0] mem_req_mshr_id_o,  // tag so response can be matched
  output logic [7:0]               mem_req_addr_o,
  output logic                     mem_req_we_o,
  output logic [7:0]               mem_req_data_o,

  // -------------------------------------------------------------------------
  // Memory response port — inbound from memory
  // Memory returns the full cache-line payload (256 bits) together with the
  // MSHR ID tag that was sent with the original request.
  // -------------------------------------------------------------------------
  input  logic                           mem_rsp_valid_i,
  input  logic [MSHR_ID_WIDTH-1:0]       mem_rsp_mshr_id_i,
  input  logic [(CACHE_LINE_SIZE*8)-1:0] mem_rsp_data_i,

  // -------------------------------------------------------------------------
  // Backend writeback port — drives dice_backend.sv mem_rsp_* inputs
  // No ready signal exists on dice_backend, so rsp_ready_i can be tied to 1.
  // -------------------------------------------------------------------------
  output logic                                                              rsp_valid_o,
  input  logic                                                              rsp_ready_i,

  output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                 rsp_base_tid_o,
  output logic [TID_BITMAP_WIDTH-1:0]                                       rsp_tid_bitmap_o,
  output logic [DICE_REG_ADDR_WIDTH-1:0]                                   rsp_ld_dest_reg_o,
  output logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0]
               [BASE_ADDRESS_OFFSET-1:0]                                   rsp_address_map_o,
  output logic [(CACHE_LINE_SIZE*8)-1:0]                                   rsp_data_o,

  // -------------------------------------------------------------------------
  // Status — one-hot valid vector (any state != FREE)
  // -------------------------------------------------------------------------
  output logic [NUM_MSHR-1:0] mshr_valid_o
);

  // -------------------------------------------------------------------------
  // State encoding
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {
    MSHR_FREE    = 2'b00,  // slot is empty and available
    MSHR_PENDING = 2'b01,  // request sent (or queued) to memory
    MSHR_DONE    = 2'b10   // load response received; pending drain to backend
  } mshr_state_e;

  // -------------------------------------------------------------------------
  // Per-entry storage
  // -------------------------------------------------------------------------
  mshr_state_e                                                              mshr_state      [NUM_MSHR];
  logic                                                                     mshr_issued     [NUM_MSHR]; // 1 once mem_req has been accepted
  logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                        mshr_base_tid   [NUM_MSHR];
  logic [TID_BITMAP_WIDTH-1:0]                                              mshr_tid_bitmap [NUM_MSHR];
  logic [DICE_REG_ADDR_WIDTH-1:0]                                          mshr_ld_dest_reg[NUM_MSHR];
  logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][BASE_ADDRESS_OFFSET-1:0]   mshr_address_map[NUM_MSHR];
  logic [7:0]                                                               mshr_addr       [NUM_MSHR];
  logic [7:0]                                                               mshr_wr_data    [NUM_MSHR];
  logic                                                                     mshr_write_en   [NUM_MSHR];
  logic [(CACHE_LINE_SIZE*8)-1:0]                                          mshr_data       [NUM_MSHR];

  // -------------------------------------------------------------------------
  // Free-slot priority encoder — lowest index wins
  // -------------------------------------------------------------------------
  logic [MSHR_ID_WIDTH-1:0] alloc_id;
  logic                     any_free;

  always_comb begin
    alloc_id = '0;
    any_free = 1'b0;
    for (int i = NUM_MSHR-1; i >= 0; i--) begin
      if (mshr_state[i] == MSHR_FREE) begin
        alloc_id = MSHR_ID_WIDTH'(i);
        any_free = 1'b1;
      end
    end
  end

  assign alloc_ready_o = any_free;

  // -------------------------------------------------------------------------
  // Memory-request arbitration — lowest-index PENDING-but-not-yet-issued entry
  // -------------------------------------------------------------------------
  logic [MSHR_ID_WIDTH-1:0] req_id;
  logic                     any_pending_req;

  always_comb begin
    req_id          = '0;
    any_pending_req = 1'b0;
    for (int i = NUM_MSHR-1; i >= 0; i--) begin
      if (mshr_state[i] == MSHR_PENDING && !mshr_issued[i]) begin
        req_id          = MSHR_ID_WIDTH'(i);
        any_pending_req = 1'b1;
      end
    end
  end

  assign mem_req_valid_o   = any_pending_req;
  assign mem_req_mshr_id_o = req_id;
  assign mem_req_addr_o    = mshr_addr    [req_id];
  assign mem_req_we_o      = mshr_write_en[req_id];
  assign mem_req_data_o    = mshr_wr_data [req_id];

  // -------------------------------------------------------------------------
  // Drain arbitration — lowest-index DONE entry to backend writeback
  // -------------------------------------------------------------------------
  logic [MSHR_ID_WIDTH-1:0] drain_id;
  logic                     any_done;

  always_comb begin
    drain_id = '0;
    any_done = 1'b0;
    for (int i = NUM_MSHR-1; i >= 0; i--) begin
      if (mshr_state[i] == MSHR_DONE) begin
        drain_id = MSHR_ID_WIDTH'(i);
        any_done = 1'b1;
      end
    end
  end

  assign rsp_valid_o       = any_done;
  assign rsp_base_tid_o    = mshr_base_tid   [drain_id];
  assign rsp_tid_bitmap_o  = mshr_tid_bitmap [drain_id];
  assign rsp_ld_dest_reg_o = mshr_ld_dest_reg[drain_id];
  assign rsp_address_map_o = mshr_address_map[drain_id];
  assign rsp_data_o        = mshr_data        [drain_id];

  // -------------------------------------------------------------------------
  // Status vector
  // -------------------------------------------------------------------------
  always_comb begin
    for (int i = 0; i < NUM_MSHR; i++)
      mshr_valid_o[i] = (mshr_state[i] != MSHR_FREE);
  end

  // -------------------------------------------------------------------------
  // Sequential state transitions
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      for (int i = 0; i < NUM_MSHR; i++) begin
        mshr_state [i] <= MSHR_FREE;
        mshr_issued[i] <= 1'b0;
      end
    end else begin

      // 1. Allocation: write metadata into the chosen free slot
      if (alloc_valid_i && alloc_ready_o) begin
        mshr_state      [alloc_id] <= MSHR_PENDING;
        mshr_issued     [alloc_id] <= 1'b0;
        mshr_base_tid   [alloc_id] <= alloc_base_tid_i;
        mshr_tid_bitmap [alloc_id] <= alloc_tid_bitmap_i;
        mshr_ld_dest_reg[alloc_id] <= alloc_ld_dest_reg_i;
        mshr_address_map[alloc_id] <= alloc_address_map_i;
        mshr_addr       [alloc_id] <= alloc_addr_i;
        mshr_wr_data    [alloc_id] <= alloc_data_i;
        mshr_write_en   [alloc_id] <= alloc_write_en_i;
        mshr_data       [alloc_id] <= '0;
      end

      // 2. Memory request handshake
      if (mem_req_valid_o && mem_req_ready_i) begin
        if (mshr_write_en[req_id]) begin
          // Store: no response expected — free the slot immediately
          mshr_state [req_id] <= MSHR_FREE;
          mshr_issued[req_id] <= 1'b0;
        end else begin
          // Load: mark issued; wait for mem_rsp
          mshr_issued[req_id] <= 1'b1;
        end
      end

      // 3. Memory response fill (loads only; guard on PENDING state)
      if (mem_rsp_valid_i &&
          (mshr_state[mem_rsp_mshr_id_i] == MSHR_PENDING)) begin
        mshr_data [mem_rsp_mshr_id_i] <= mem_rsp_data_i;
        mshr_state[mem_rsp_mshr_id_i] <= MSHR_DONE;
      end

      // 4. Drain completed load entry to dice_backend
      if (rsp_valid_o && rsp_ready_i) begin
        mshr_state [drain_id] <= MSHR_FREE;
        mshr_issued[drain_id] <= 1'b0;
      end

    end
  end

endmodule
