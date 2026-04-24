module dispatcher
  import dice_pkg::*, dice_frontend_pkg::*, DE_pkg::*;
(
    input logic clk_i,
    input logic rst,

    // metadata input package
    input logic [NUM_MEM_PORTS-1:0][REG_INDEX_WIDTH-1:0] ld_dest_regs,
    input logic [REG_NUM-1:0] input_register_bitmap,

    // Runtime execution context inputs
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,           // 1024-bit active mask // DICE_NUM_MAX_THREADS_PER_CORE?
    input logic fetch_done,  // Previous stage ready signal

    // Write-back interface for scoreboards
    input logic wb_valid,  // Valid signal for write-back command
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] wb_tid_bitmap,         // bitmap of TIDs to release registers
    input logic [REG_NUM-1:0] wb_regs_bitmap,  // bitmap of registers to release
    input logic clear_scoreboard,  // clear scoreboard on a true CTA boundary

    // Ready-to-dispatch FIFO pop interface
    input  logic dispatch_fifo_pop,   // Pop signals for ready-to-dispatch FIFO
    output logic dispatch_fifo_empty, // 1 if ALL FIFOs are empty

    // Output signals - dispatched threads packed to one bus
    output logic [NUM_LANES*DICE_TID_WIDTH-1:0] dispatch_tid_o,
    output logic [NUM_LANES-1:0] dispatch_valid_o,

    //
    output logic [DICE_TOTAL_REGS-1:0] full_reg_bitmap_o,

    // Status outputs
    output logic dispatcher_busy,  // Dispatcher is active
    output logic dispatcher_done   //
);
  // Local parameters — NUM_LANES, NUM_SCOREBOARDS, CHUNK_SIZE, CHUNK_ADDR_WIDTH from DE_pkg
  localparam int THREADS_PER_SCOREBOARD = CHUNK_SIZE;  // alias: entries per scoreboard
  localparam int SCOREBOARD_TID_WIDTH = $clog2(CHUNK_SIZE);  // TID bit-width within one SB

  // load destination registers (ld_dest_reg) bitmap assembly
  localparam int NUM_LD_DEST_REGS = NUM_MEM_PORTS;

  // Convert packed ld_dest_regs array into a flat REG_NUM-wide bitmap
  logic [REG_NUM-1:0] ld_dest_regs_bitmap;

  always_comb begin
    ld_dest_regs_bitmap = '0;
    for (int k = 0; k < NUM_LD_DEST_REGS; k++) begin
      if (ld_dest_regs[k] != REG_INDEX_WIDTH'(31)) begin
        ld_dest_regs_bitmap[ld_dest_regs[k]] = 1'b1;
      end
    end
  end

  // Next thread logic signals
  logic thread_fifo_pop;
  logic [DICE_TID_WIDTH-1:0] thread_next_tid_0;
  logic thread_valid_0;
  logic thread_fifo_data_valid;
  logic thread_fifo_empty, thread_fifo_full;
  logic                        thread_chunk_done;
  logic                        restart;
  logic [      CHUNK_SIZE-1:0] current_chunk;  // 256-bit chunk from active mask
  logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr;  // Current chunk index (0-3)

  // Scoreboard signals // BITMAP BASED SCOREBOARD INTERFACE USING METADATA INPUT BITMAP SUBJECT TO CHANGE
  logic [   DICE_NUM_REGS-1:0] gpr_bitmap;  // GPR portion of input registers
  logic [  DICE_NUM_CONST-1:0] const_bitmap;  // Constant portion of input registers
  logic [   DICE_NUM_PRED-1:0] pred_bitmap;  // Predicate portion of input registers

  assign full_reg_bitmap_o = {
    pred_bitmap, const_bitmap, gpr_bitmap
  };  // Output the full register bitmap to the RF controller

  logic collision[NUM_SCOREBOARDS];  // Collision results from regular scoreboards
  logic const_collision;  // Collision result from constant scoreboard
  logic [SCOREBOARD_TID_WIDTH-1:0] check_tid[NUM_LANES];  // TIDs to check for collision
  logic [NUM_LANES-1:0] sb_rd_valid;  // Read valid signals for scoreboards
  logic sb_rsv_valid;  // Reserve valid signal for scoreboards
  logic const_rd_valid;  // Read valid for constant scoreboard
  logic const_rsv_valid;  // Reserve valid for constant scoreboard
  logic start_new_cta;  // Starts dispatch for the next eblock
  // syn_keep
  logic [THREADS_PER_SCOREBOARD-1:0] wb_tid_sb [NUM_SCOREBOARDS];               // Write-back bitmaps for each scoreboard
  logic [THREADS_PER_SCOREBOARD-1:0] rsv_tid_sb[NUM_SCOREBOARDS];

  // Ready-to-dispatch FIFO signals
  logic [DICE_TID_WIDTH:0] ready_fifo_push_data[NUM_LANES];
  logic [DICE_TID_WIDTH:0] ready_fifo_pop_data[NUM_LANES];
  logic [NUM_LANES-1:0] ready_fifo_push_en;
  logic [NUM_LANES-1:0] ready_fifo_pop_data_valid;
  logic [NUM_LANES-1:0] ready_fifo_empty;
  logic [NUM_LANES-1:0] ready_fifo_full;

  logic [CHUNK_ADDR_WIDTH-1:0] lane_sb_sel[NUM_LANES];  // Which scoreboard (0-3) for each lane
  logic [NUM_LANES-1:0] lane_collision;  // Per-lane collision results
  logic [NUM_LANES-1:0] sb_rd_valid_per_sb [NUM_SCOREBOARDS];       // [scoreboard][lane] - tracks which lanes check which SB

  // Dispatch output signals (declared before use)
  logic [DICE_TID_WIDTH-1:0] dispatch_tid_0;
  logic dispatch_valid_0;
  logic dispatch_pipeline_idle;
  logic [DICE_TID_WIDTH-1:0] pending_check_tid;
  logic pending_check_valid;
  logic thread_pop_pending;

  // ============================================================
  // Component Instantiations
  // ============================================================

  dispatcher_fsm dispatcher_fsm_inst (
      .current_chunk(current_chunk),
      .gpr_bitmap(gpr_bitmap),
      .const_bitmap(const_bitmap),
      .chunk_base_addr(chunk_base_addr),
      .pred_bitmap(pred_bitmap),
      .start_new_cta(start_new_cta),
      .dispatcher_busy(dispatcher_busy),
      .dispatcher_done(dispatcher_done),
      .restart(restart),

      .active_mask(active_mask),
      .input_register_bitmap(input_register_bitmap),
      .dispatch_valid_0(dispatch_valid_0),
      .fetch_done(fetch_done),
      .thread_chunk_done(thread_chunk_done),
      .dispatch_fifo_empty(dispatch_fifo_empty),
      .dispatch_pipeline_idle(dispatch_pipeline_idle),
      .clk(clk_i),
      .rst(rst)
  );

  // Next Thread Logic Top - Updated interface with chunk_done
  next_thread_logic_top next_thread_top (
      .clk(clk_i),
      .rst(rst),
      .active_mask_chunk(current_chunk),
      .chunk_base_addr(chunk_base_addr),
      .restart(restart),
      .fifo_pop(thread_fifo_pop),
      .next_tid_0(thread_next_tid_0),
      .valid_0(thread_valid_0),
      .fifo_data_valid(thread_fifo_data_valid),
      .fifo_empty(thread_fifo_empty),
      .fifo_full(thread_fifo_full),
      .chunk_done(thread_chunk_done)
  );

  // Hold the TID being checked until it is collision-free. The thread FIFO
  // produces a one-cycle valid pulse after pop, so a colliding TID must be
  // retained locally while waiting for its dependencies to clear.
  assign check_tid[0]   = pending_check_tid[SCOREBOARD_TID_WIDTH-1:0];

  // Extract scoreboard selector from upper TID bits
  // With NUM_SCOREBOARDS=1, SCOREBOARD_TID_WIDTH==DICE_TID_WIDTH so no upper bits exist; always scoreboard 0
  assign lane_sb_sel[0] = '0;

  // Load destinations are known for the whole eblock at accept time. Reserve
  // them for every active thread immediately so later eblocks cannot pass
  // collision checks while earlier load threads are still queued.
  assign sb_rsv_valid   = fetch_done && (|ld_dest_regs_bitmap);

  // Valid signals for scoreboards - only check when thread FIFO has valid data
  always_comb begin
    // Initialize: no lanes checking any scoreboards
    for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
      sb_rd_valid_per_sb[sb] = '0;
    end

    // Route READ requests: lane 0 checks its target scoreboard
    if (pending_check_valid) sb_rd_valid_per_sb[lane_sb_sel[0]][0] = 1'b1;
  end

  // Aggregate: each scoreboard's rd_valid is OR of all lanes checking it
  always_comb begin
    for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
      sb_rd_valid[sb] = |sb_rd_valid_per_sb[sb];
    end
  end

  always_comb begin
    for (int lane = 0; lane < NUM_LANES; lane++) begin
      // Each lane gets collision result from its target scoreboard
      lane_collision[lane] = collision[lane_sb_sel[lane]];
    end
  end

  // Constant scoreboard valid signals (OR of all lanes)
  assign const_rd_valid  = |sb_rd_valid;  // Check constants if any lane needs checking
  assign const_rsv_valid = 1'b0;

  // Only pass write-back signals when wb_valid is asserted
  always_comb begin
    if (wb_valid) begin
      for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
        wb_tid_sb[sb] = wb_tid_bitmap[sb*THREADS_PER_SCOREBOARD+:THREADS_PER_SCOREBOARD];
      end
    end else begin
      for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
        wb_tid_sb[sb] = '0;
      end
    end
  end

  always_comb begin
    if (sb_rsv_valid) begin
      for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
        rsv_tid_sb[sb] = active_mask[sb*THREADS_PER_SCOREBOARD+:THREADS_PER_SCOREBOARD];
      end
    end else begin
      for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
        rsv_tid_sb[sb] = '0;
      end
    end
  end

  // For each SB, pick the rd_tid from whichever lane is actually targeting it
  logic [SCOREBOARD_TID_WIDTH-1:0] sb_rd_tid[NUM_SCOREBOARDS];
  always_comb begin
    for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
      sb_rd_tid[sb] = '0;
      for (int lane = 0; lane < NUM_LANES; lane++) begin
        if (sb_rd_valid_per_sb[sb][lane]) sb_rd_tid[sb] = check_tid[lane];
      end
    end
  end

  // Scoreboards for collision detection
  genvar i;
  generate
    for (i = 0; i < NUM_SCOREBOARDS; i++) begin : gen_scoreboards
      scoreboard #(
          .THREADS_PER_SCOREBOARD(THREADS_PER_SCOREBOARD),
          .SCOREBOARD_TID_WIDTH  (SCOREBOARD_TID_WIDTH)
      ) sb (
          .clk             (clk_i),
          .rst             (rst),
          .input_regs_map  (input_register_bitmap),  // Direct from input: 32GPR + 2PR (34 bits)
          .rd_tid          (sb_rd_tid[i]),
          .rd_valid        (sb_rd_valid[i]),         // Valid signal for read operation
          .rsv_tid_bitmap  (rsv_tid_sb[i]),
          .rsv_valid       (sb_rsv_valid),           // Valid signal for reserve operation
          .wb_tid_bitmap   (wb_tid_sb[i]),           // Each scoreboard gets its 256-bit slice
          .rsv_regs_bitmap (ld_dest_regs_bitmap),
          .wb_regs_bitmap  (wb_regs_bitmap),
          .wb_valid        (wb_valid),
          .clear_scoreboard(clear_scoreboard),
          .collision       (collision[i])
      );
    end
  endgenerate

  // Constant scoreboard for shared constant collision detection
  constant_scoreboard #(
      .NUM_CONSTANT_REGS(DICE_NUM_CONST)
  ) const_sb (
      .clk(clk_i),
      .rst(rst),
      .input_const_map(const_bitmap),  // 32-bit constant register map
      .rd_valid(const_rd_valid),  // Valid when any lane needs checking
      .rsv_const_map(const_bitmap),  // Reserve the same constants
      .rsv_valid(const_rsv_valid),  // Valid when any lane is reserving
      .wb_const_bitmap(wb_regs_bitmap[(DICE_NUM_REGS+DICE_NUM_CONST-1):DICE_NUM_REGS]),
      .wb_valid(wb_valid && |wb_regs_bitmap[(DICE_NUM_REGS+DICE_NUM_CONST-1):DICE_NUM_REGS]),
      .clear_scoreboard(clear_scoreboard),
      .collision(const_collision)
  );

  // Thread FIFO pop control - pop when no collision and can push to ready FIFOs
  logic all_lane_can_dispatch;
  assign all_lane_can_dispatch = !lane_collision[0] && !const_collision;

  logic ready_fifo_not_full;
  assign ready_fifo_not_full = !ready_fifo_full[0];

  assign thread_fifo_pop = !thread_fifo_empty
                         && !pending_check_valid
                         && !thread_pop_pending
                         && ready_fifo_not_full;

  always_ff @(posedge clk_i) begin
    if (rst || restart) begin
      pending_check_tid   <= '0;
      pending_check_valid <= 1'b0;
      thread_pop_pending  <= 1'b0;
    end else begin
      if (thread_fifo_pop) begin
        thread_pop_pending <= 1'b1;
      end

      if (!pending_check_valid && thread_fifo_data_valid && thread_valid_0) begin
        pending_check_tid   <= thread_next_tid_0;
        pending_check_valid <= 1'b1;
        thread_pop_pending  <= 1'b0;
      end else if (pending_check_valid && all_lane_can_dispatch && ready_fifo_not_full) begin
        pending_check_valid <= 1'b0;
      end
    end
  end

  always_comb begin
    // NEW: Calculating per-lane push enable
    for (int j = 0; j < NUM_LANES; j++) begin
      ready_fifo_push_en[j] = pending_check_valid &&
                                !lane_collision[j] && !const_collision &&
                                !ready_fifo_full[j];
    end
    // Push data assignments
    ready_fifo_push_data[0] = {1'b1, pending_check_tid};
  end

  // Ready-to-dispatch FIFOs using sync_fifo module
  generate
    for (i = 0; i < NUM_LANES; i++) begin : gen_ready_fifos
      sync_fifo_read_unreg #(
          .DATA_WIDTH(DICE_TID_WIDTH + 1),  // {valid, tid[DICE_TID_WIDTH-1:0]}
          .DEPTH     (4)                    // 4 entries deep
      ) ready_fifo (
          .clk_i(clk_i),
          .rst(rst),
          .push(ready_fifo_push_en[i]),
          .push_data(ready_fifo_push_data[i]),
          .pop(dispatch_fifo_pop),
          .pop_data(ready_fifo_pop_data[i]),
          .pop_data_valid(ready_fifo_pop_data_valid[i]),
          .empty(ready_fifo_empty[i]),
          .full(ready_fifo_full[i]),
          .count()  // Unused
      );
    end
  endgenerate

  // Output assignments
  assign dispatch_tid_0 = ready_fifo_pop_data[0][DICE_TID_WIDTH-1:0];
  assign dispatch_valid_0 = ready_fifo_pop_data_valid[0] && ready_fifo_pop_data[0][DICE_TID_WIDTH];

  assign dispatch_tid_o = dispatch_tid_0;
  assign dispatch_valid_o = dispatch_valid_0;

  assign dispatch_fifo_empty = ready_fifo_empty[0];
  assign dispatch_pipeline_idle = !thread_fifo_pop
                                 && thread_fifo_empty
                                 && !thread_fifo_data_valid
                                 && !pending_check_valid
                                 && !thread_pop_pending
                                 && !(|ready_fifo_push_en)
                                 && dispatch_fifo_empty;

endmodule
