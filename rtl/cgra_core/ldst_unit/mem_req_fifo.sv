// mem_req_fifo.sv
//
// Depth-16 synchronous FIFO that serializes per-thread memory requests from
// the CGRA (via dice_backend shift-register outputs) onto an AXI-Lite master
// port, then drives the dice_backend mem_rsp_* writeback inputs.
//
// Flow:
//   LOAD  : enqueue → issue AR → wait RVALID → pulse rsp_valid_o → pop
//   STORE : enqueue → issue AW+W → wait BVALID → pop (no RF writeback)
//
// One transaction in flight at a time (AXI-Lite has no ID fields).

`include "dice_define.vh"

module mem_req_fifo
  import dice_pkg::*;
  import DE_pkg::*;
#(
  parameter  int DEPTH   = 16,
  localparam int PTR_W   = $clog2(DEPTH),
  localparam int AXI_AW  = 16,
  localparam int AXI_DW  = 16
)(
  input  logic clk_i,
  input  logic rst_i,

  // -------------------------------------------------------------------------
  // Enqueue port — driven by cgra_tid_lo / cgra_v_lo shift registers in
  // dice_backend, plus mem_addr_o / mem_data_o from the memory crossbar.
  // -------------------------------------------------------------------------
  input  logic                           enq_valid_i,
  output logic                           enq_ready_o,    // FIFO not full
  input  logic [DICE_TID_WIDTH-1:0]      enq_tid_i,
  input  logic [7:0]                     enq_addr_i,     // mem_addr_o
  input  logic [7:0]                     enq_data_i,     // mem_data_o (stores)
  input  logic                           enq_write_en_i, // 0=load  1=store
  input  logic [DICE_REG_ADDR_WIDTH-1:0] enq_ld_dest_reg_i,

  // -------------------------------------------------------------------------
  // AXI-Lite master — connect to cgra_mem_system_16bit crossbar
  // -------------------------------------------------------------------------
  output logic [AXI_AW-1:0] axi_awaddr_o,
  output logic               axi_awvalid_o,
  input  logic               axi_awready_i,

  output logic [AXI_DW-1:0] axi_wdata_o,
  output logic [1:0]         axi_wstrb_o,
  output logic               axi_wvalid_o,
  input  logic               axi_wready_i,

  input  logic [1:0]         axi_bresp_i,
  input  logic               axi_bvalid_i,
  output logic               axi_bready_o,

  output logic [AXI_AW-1:0] axi_araddr_o,
  output logic               axi_arvalid_o,
  input  logic               axi_arready_i,

  input  logic [AXI_DW-1:0] axi_rdata_i,
  input  logic [1:0]         axi_rresp_i,
  input  logic               axi_rvalid_i,
  output logic               axi_rready_o,

  // -------------------------------------------------------------------------
  // Backend writeback — wire directly to dice_backend.sv mem_rsp_* inputs
  // -------------------------------------------------------------------------
  output logic                                                               rsp_valid_o,
  output logic [$clog2(DICE_NUM_MAX_THREADS_PER_CORE)-1:0]                  rsp_base_tid_o,
  output logic [TID_BITMAP_WIDTH-1:0]                                        rsp_tid_bitmap_o,
  output logic [DICE_REG_ADDR_WIDTH-1:0]                                    rsp_ld_dest_reg_o,
  output logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0]
               [BASE_ADDRESS_OFFSET-1:0]                                    rsp_address_map_o,
  output logic [(CACHE_LINE_SIZE*8)-1:0]                                    rsp_data_o
);

  // -------------------------------------------------------------------------
  // FIFO storage arrays
  // -------------------------------------------------------------------------
  logic [DICE_TID_WIDTH-1:0]      fifo_tid      [DEPTH];
  logic [7:0]                     fifo_addr     [DEPTH];
  logic [7:0]                     fifo_wr_data  [DEPTH];
  logic                           fifo_write_en [DEPTH];
  logic [DICE_REG_ADDR_WIDTH-1:0] fifo_dest_reg [DEPTH];

  logic [PTR_W-1:0] wptr, rptr;

  logic full, empty;
  assign full  = (wptr + PTR_W'(1) == rptr);
  assign empty = (wptr == rptr);
  assign enq_ready_o = !full;

  // Head-of-FIFO convenience wires
  logic [DICE_TID_WIDTH-1:0]      h_tid;
  logic [7:0]                     h_addr;
  logic [7:0]                     h_wr_data;
  logic                           h_we;
  logic [DICE_REG_ADDR_WIDTH-1:0] h_dest;

  assign h_tid     = fifo_tid      [rptr];
  assign h_addr    = fifo_addr     [rptr];
  assign h_wr_data = fifo_wr_data  [rptr];
  assign h_we      = fifo_write_en [rptr];
  assign h_dest    = fifo_dest_reg [rptr];

  // -------------------------------------------------------------------------
  // AXI-Lite transaction FSM
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_ISSUE_W,   // asserting AW + W for a store
    ST_WAIT_B,    // waiting for BVALID (store complete)
    ST_ISSUE_R,   // asserting AR for a load
    ST_WAIT_R     // waiting for RVALID (load data arrives)
  } state_e;

  state_e state;
  logic   aw_done, w_done;   // track per-channel handshake in ST_ISSUE_W

  // -------------------------------------------------------------------------
  // AXI-Lite output drive (combinational)
  // -------------------------------------------------------------------------
  always_comb begin
    axi_awaddr_o  = '0;
    axi_awvalid_o = 1'b0;
    axi_wdata_o   = '0;
    axi_wstrb_o   = 2'b01;   // byte lane 0
    axi_wvalid_o  = 1'b0;
    axi_bready_o  = 1'b0;
    axi_araddr_o  = '0;
    axi_arvalid_o = 1'b0;
    axi_rready_o  = 1'b0;

    unique case (state)
      ST_ISSUE_W: begin
        axi_awaddr_o  = AXI_AW'(h_addr);
        axi_awvalid_o = !aw_done;
        axi_wdata_o   = {8'b0, h_wr_data};
        axi_wstrb_o   = 2'b01;
        axi_wvalid_o  = !w_done;
      end
      ST_WAIT_B: axi_bready_o  = 1'b1;
      ST_ISSUE_R: begin
        axi_araddr_o  = AXI_AW'(h_addr);
        axi_arvalid_o = 1'b1;
      end
      ST_WAIT_R:  axi_rready_o  = 1'b1;
      default: ;
    endcase
  end

  // -------------------------------------------------------------------------
  // Response reconstruction (combinational, fires on RVALID in ST_WAIT_R)
  //
  // Single-thread response fields for dice_backend assemble_ldst_wr:
  //   slot          = tid[DICE_BASE_TID_ADDRESS_OFFSET-1:0]  (which bitmap bit)
  //   base_tid      = tid with lower DICE_BASE_TID_ADDRESS_OFFSET bits zeroed
  //   tid_bitmap    = 1 << slot
  //   address_map[slot] = addr[BASE_ADDRESS_OFFSET-1:0]   (byte offset in line)
  //   core_rsp_data[slot*8 +: 8] = rdata[7:0]
  // -------------------------------------------------------------------------
  localparam int SLOT_W = DICE_BASE_TID_ADDRESS_OFFSET;  // 3

  logic [SLOT_W-1:0] h_slot;
  assign h_slot = h_tid[SLOT_W-1:0];

  assign rsp_valid_o = (state == ST_WAIT_R) && axi_rvalid_i;

  always_comb begin
    rsp_base_tid_o    = {h_tid[DICE_TID_WIDTH-1:SLOT_W], {SLOT_W{1'b0}}};
    rsp_tid_bitmap_o  = TID_BITMAP_WIDTH'(1'b1) << h_slot;
    rsp_ld_dest_reg_o = h_dest;

    rsp_address_map_o = '0;
    rsp_address_map_o[h_slot] = h_addr[BASE_ADDRESS_OFFSET-1:0];

    rsp_data_o = '0;
    rsp_data_o[h_slot * DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] = axi_rdata_i[7:0];
  end

  // -------------------------------------------------------------------------
  // Sequential: FIFO push/pop + FSM transitions
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (rst_i) begin
      wptr    <= '0;
      rptr    <= '0;
      state   <= ST_IDLE;
      aw_done <= 1'b0;
      w_done  <= 1'b0;
    end else begin

      // --- Enqueue (push) ---------------------------------------------------
      if (enq_valid_i && enq_ready_o) begin
        fifo_tid      [wptr] <= enq_tid_i;
        fifo_addr     [wptr] <= enq_addr_i;
        fifo_wr_data  [wptr] <= enq_data_i;
        fifo_write_en [wptr] <= enq_write_en_i;
        fifo_dest_reg [wptr] <= enq_ld_dest_reg_i;
        wptr <= wptr + PTR_W'(1);
      end

      // --- FSM --------------------------------------------------------------
      unique case (state)

        ST_IDLE: begin
          aw_done <= 1'b0;
          w_done  <= 1'b0;
          if (!empty)
            state <= h_we ? ST_ISSUE_W : ST_ISSUE_R;
        end

        ST_ISSUE_W: begin
          // Track each channel's handshake independently (AXI-Lite allows
          // AW and W to be accepted in any order).
          if (!aw_done && axi_awready_i) aw_done <= 1'b1;
          if (!w_done  && axi_wready_i)  w_done  <= 1'b1;

          // Both accepted this cycle or already done → move to wait
          if ((aw_done || axi_awready_i) && (w_done || axi_wready_i))
            state <= ST_WAIT_B;
        end

        ST_WAIT_B: begin
          if (axi_bvalid_i) begin
            rptr  <= rptr + PTR_W'(1);
            state <= ST_IDLE;
          end
        end

        ST_ISSUE_R: begin
          if (axi_arready_i) state <= ST_WAIT_R;
        end

        ST_WAIT_R: begin
          // rsp_valid_o pulses combinatorially this same cycle.
          // Pop the entry and return to idle.
          if (axi_rvalid_i) begin
            rptr  <= rptr + PTR_W'(1);
            state <= ST_IDLE;
          end
        end

      endcase
    end
  end

endmodule
