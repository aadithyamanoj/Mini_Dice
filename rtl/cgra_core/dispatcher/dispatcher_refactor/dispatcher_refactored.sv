`include "dice_define.vh"

module dispatcher
    import dice_pkg::*, 
           dice_frontend_pkg::*,
           DE_pkg::*;
(
    input logic clk_i,
    input logic rst,

    // metadata input package
    input logic [$clog2(`DICE_CGRA_MEM_PORTS-1):0][REG_INDEX_WIDTH-1:0] ld_dest_regs,
    input logic [REG_NUM-1:0] input_register_bitmap,
    input logic [1:0] unrolling_factor,

    // Runtime execution context inputs
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask,           // 1024-bit active mask // DICE_NUM_MAX_THREADS_PER_CORE?
    input [1:0] cta_size,                 // 0=256, 1=512, 3=1024
    input logic fetch_done,                     // Previous stage ready signal
    
    // Write-back interface for scoreboards
    input logic wb_valid,                       // Valid signal for write-back command
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] wb_tid_bitmap,         // 1024-bit bitmap of TIDs to release registers // DICE_NUM_MAX_THREADS_PER_CORE?
    
    // Ready-to-dispatch FIFO pop interface
    input logic dispatch_fifo_pop,       // Pop signals for ready-to-dispatch FIFO
    output logic dispatch_fifo_empty,        // 1 if ALL FIFOs are empty
    
    // Output signals - dispatched threads packed to one bus
    output logic [4*DICE_TID_WIDTH-1:0] dispatch_tid_o, // Combined TID output for all lanes
    output logic [NUM_LANES-1:0] dispatch_valid_o,                      // Combined valid signal for all lanes

    // 
    output logic [`DICE_GPR_NUM-1:0] gpr_bitmap_o,
    
    // Status outputs
    output logic dispatcher_busy,              // Dispatcher is active
    output logic dispatcher_done               //  
);
    // Local parameters — NUM_LANES, NUM_SCOREBOARDS, CHUNK_SIZE, CHUNK_ADDR_WIDTH from DE_pkg
    localparam int THREADS_PER_SCOREBOARD = CHUNK_SIZE;            // alias: entries per scoreboard
    localparam int SCOREBOARD_TID_WIDTH   = $clog2(CHUNK_SIZE);    // TID bit-width within one SB

    // load destination registers (ld_dest_reg) bitmap assembly
    localparam int NUM_LD_DEST_REGS = $clog2(`DICE_CGRA_MEM_PORTS-1) + 1; // number of ld_dest entries

    // Convert parcked ld_dest_regs array into a flat REG_NUM-wide bitmap
    logic [REG_NUM-1:0] ld_dest_regs_bitmap;

    always_comb begin
        ld_dest_regs_bitmap = '0;
        for (int k = 0; k < NUM_LD_DEST_REGS; k++) begin
            ld_dest_regs_bitmap[ld_dest_regs[k]] = 1'b1;
        end
    end

    // Next thread logic signals
    logic thread_fifo_pop;
    logic [DICE_TID_WIDTH-1:0] thread_next_tid_0, thread_next_tid_1, thread_next_tid_2, thread_next_tid_3;
    logic thread_valid_0, thread_valid_1, thread_valid_2, thread_valid_3;
    logic thread_fifo_data_valid;
    logic thread_fifo_empty, thread_fifo_full;
    logic thread_chunk_done;
    logic restart;
    logic [CHUNK_SIZE-1:0] current_chunk;           // 256-bit chunk from active mask
    logic [CHUNK_ADDR_WIDTH-1:0] chunk_base_addr;           // Current chunk index (0-3)
    logic [1:0] latched_unrolling_factor;  // Latched unrolling factor
    
    // Scoreboard signals // BITMAP BASED SCOREBAORD INTERFACE USING METADATA INPUT BITMAP SUBJECT TO CHANGE
    logic [`DICE_GPR_NUM-1:0] gpr_bitmap;                   // GPR portion of input registers
    logic [`DICE_CR_NUM-1:0] const_bitmap;                 // Constant portion of input registers
    logic [`DICE_PR_NUM-1:0] pred_bitmap;                   // Predicate portion of input registers

    assign gpr_bitmap_o = gpr_bitmap; // Output the GPR bitmap to the RF controller

    logic collision [NUM_SCOREBOARDS];                       // Collision results from regular scoreboards
    logic const_collision;                     // Collision result from constant scoreboard
    logic [SCOREBOARD_TID_WIDTH-1:0] check_tid [NUM_LANES];                 // TIDs to check for collision
    logic [SCOREBOARD_TID_WIDTH-1:0] reserve_tid [NUM_LANES];               // TIDs to reserve
    logic [NUM_LANES-1:0] sb_rd_valid;                   // Read valid signals for scoreboards
    logic [NUM_LANES-1:0] sb_rsv_valid;                  // Reserve valid signals for scoreboards
    logic const_rd_valid;                      // Read valid for constant scoreboard
    logic const_rsv_valid;                     // Reserve valid for constant scoreboard
    logic start_new_cta;                       // Clears scoreboards on new CTA dispatch
    // syn_keep
    logic [THREADS_PER_SCOREBOARD-1:0] wb_tid_sb [NUM_SCOREBOARDS];               // Write-back bitmaps for each scoreboard
    
    // Ready-to-dispatch FIFO signals
    logic [DICE_TID_WIDTH:0] ready_fifo_push_data [NUM_LANES];
    logic [DICE_TID_WIDTH:0] ready_fifo_pop_data [NUM_LANES];
    logic [NUM_LANES-1:0] ready_fifo_pop_data_valid;
    logic [NUM_LANES-1:0] ready_fifo_empty;
    logic [NUM_LANES-1:0] ready_fifo_full;
    logic last_chunk_done; // Indicates if the last chunk is done processing

    logic [CHUNK_ADDR_WIDTH-1:0] lane_sb_sel [NUM_LANES];              // Which scoreboard (0-3) for each lane
    logic [NUM_LANES-1:0] lane_collision;               // Per-lane collision results
    logic [NUM_LANES-1:0] sb_rd_valid_per_sb [NUM_SCOREBOARDS];       // [scoreboard][lane] - tracks which lanes check which SB
    logic [NUM_LANES-1:0] sb_rsv_valid_per_sb [NUM_SCOREBOARDS];      // [scoreboard][lane] - for reserve operationsNUM_LANES-1

    // Dispatch output signals (declared before use)
    logic [DICE_TID_WIDTH-1:0] dispatch_tid_0, dispatch_tid_1, dispatch_tid_2, dispatch_tid_3;
    logic dispatch_valid_0, dispatch_valid_1, dispatch_valid_2, dispatch_valid_3;

    // ============================================================
    // Component Instantiations
    // ============================================================

    dispatcher_fsm dispatcher_fsm_inst (
        .current_chunk(current_chunk),
        .gpr_bitmap(gpr_bitmap),
        .const_bitmap(const_bitmap),
        .chunk_base_addr(chunk_base_addr),
        .latched_unrolling_factor(latched_unrolling_factor),
        .pred_bitmap(pred_bitmap),
        .start_new_cta(start_new_cta),
        .dispatcher_busy(dispatcher_busy),
        .dispatcher_done(dispatcher_done),
        .restart(restart),

        .active_mask(active_mask),
        .input_register_bitmap(input_register_bitmap),
        .unrolling_factor(unrolling_factor),
        .cta_size(cta_size),
        .dispatch_valid_0(dispatch_valid_0),
        .dispatch_valid_1(dispatch_valid_1),
        .dispatch_valid_2(dispatch_valid_2),
        .dispatch_valid_3(dispatch_valid_3),
        .fetch_done(fetch_done),
        .thread_chunk_done(thread_chunk_done),
        .dispatch_fifo_empty(dispatch_fifo_empty),
        .clk(clk_i),
        .rst(rst)
    );
    
    // Next Thread Logic Top - Updated interface with chunk_done
    next_thread_logic_top next_thread_top (
        .clk(clk_i),
        .rst(rst),
        .unrolling_factor(latched_unrolling_factor),
        .active_mask_chunk(current_chunk),
        .chunk_base_addr(chunk_base_addr),
        .restart(restart),
        .fifo_pop(thread_fifo_pop),
        .next_tid_0(thread_next_tid_0),
        .next_tid_1(thread_next_tid_1),
        .next_tid_2(thread_next_tid_2),
        .next_tid_3(thread_next_tid_3),
        .valid_0(thread_valid_0),
        .valid_1(thread_valid_1),
        .valid_2(thread_valid_2),
        .valid_3(thread_valid_3),
        .fifo_data_valid(thread_fifo_data_valid),
        .fifo_empty(thread_fifo_empty),
        .fifo_full(thread_fifo_full),
        .chunk_done(thread_chunk_done)
    );
    
    // Extract TIDs for scoreboard checking (only when data is valid)
    assign check_tid[0] = thread_next_tid_0[SCOREBOARD_TID_WIDTH-1:0];  // Use lower 8 bits of TID
    assign check_tid[1] = thread_next_tid_1[SCOREBOARD_TID_WIDTH-1:0];
    assign check_tid[2] = thread_next_tid_2[SCOREBOARD_TID_WIDTH-1:0];
    assign check_tid[3] = thread_next_tid_3[SCOREBOARD_TID_WIDTH-1:0];
    
    assign reserve_tid[0] = ready_fifo_pop_data[0][SCOREBOARD_TID_WIDTH-1:0];
    assign reserve_tid[1] = ready_fifo_pop_data[1][SCOREBOARD_TID_WIDTH-1:0];
    assign reserve_tid[2] = ready_fifo_pop_data[2][SCOREBOARD_TID_WIDTH-1:0];
    assign reserve_tid[3] = ready_fifo_pop_data[3][SCOREBOARD_TID_WIDTH-1:0];

    // Extract scoreboard selectro from upper TID bits
    assign lane_sb_sel[0] = thread_next_tid_0[DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH];  // Which scoreboard lane 0 should check
    assign lane_sb_sel[1] = thread_next_tid_1[DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH];
    assign lane_sb_sel[2] = thread_next_tid_2[DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH];
    assign lane_sb_sel[3] = thread_next_tid_3[DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH];
    
    // Each lane's rsv_valid = fifo pop and lane has valid data
    assign sb_rsv_valid[0] = dispatch_fifo_pop && dispatch_valid_0;
    assign sb_rsv_valid[1] = dispatch_fifo_pop && dispatch_valid_1;
    assign sb_rsv_valid[2] = dispatch_fifo_pop && dispatch_valid_2;
    assign sb_rsv_valid[3] = dispatch_fifo_pop && dispatch_valid_3;

    // Valid signals for scoreboards - only check when thread FIFO has valid data
    always_comb begin
        // Initialize: no lanes checking any scoreboards
        for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
            sb_rd_valid_per_sb[sb] = '0;
            sb_rsv_valid_per_sb[sb] = '0;
        end
        
        // Route READ requests: each valid lane checks its target scoreboard
        if (thread_fifo_data_valid && thread_valid_0)
            sb_rd_valid_per_sb[lane_sb_sel[0]][0] = 1'b1;
        if (thread_fifo_data_valid && thread_valid_1)
            sb_rd_valid_per_sb[lane_sb_sel[1]][1] = 1'b1;
        if (thread_fifo_data_valid && thread_valid_2)
            sb_rd_valid_per_sb[lane_sb_sel[2]][2] = 1'b1;
        if (thread_fifo_data_valid && thread_valid_3)
            sb_rd_valid_per_sb[lane_sb_sel[3]][3] = 1'b1;
        
        // Route RESERVE requests: based on TID from ready FIFO
        if (sb_rsv_valid[0]) // If lane 0 is reserving
            sb_rsv_valid_per_sb[ready_fifo_pop_data[0][DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH]][0] = 1'b1;
        if (sb_rsv_valid[1])
            sb_rsv_valid_per_sb[ready_fifo_pop_data[1][DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH]][1] = 1'b1;
        if (sb_rsv_valid[2])
            sb_rsv_valid_per_sb[ready_fifo_pop_data[2][DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH]][2] = 1'b1;
        if (sb_rsv_valid[3])
            sb_rsv_valid_per_sb[ready_fifo_pop_data[3][DICE_TID_WIDTH-1:SCOREBOARD_TID_WIDTH]][3] = 1'b1;
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
    assign const_rd_valid = |sb_rd_valid;    // Check constants if any lane needs checking
    assign const_rsv_valid = |sb_rsv_valid;  // Reserve constants if any lane is reserving
    
    // Only pass write-back signals when wb_valid is asserted
    always_comb begin
        if (wb_valid) begin
            for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
                wb_tid_sb[sb] = wb_tid_bitmap[sb*THREADS_PER_SCOREBOARD +: THREADS_PER_SCOREBOARD];
            end 
        end else begin
            // No write-back when not valid
            for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
                wb_tid_sb[sb] = '0;
            end
        end
    end
    
    // For each SB, pick the rd_tid from whichever lane is actually targeting it
    logic [SCOREBOARD_TID_WIDTH-1:0] sb_rd_tid [NUM_SCOREBOARDS];
    logic [SCOREBOARD_TID_WIDTH-1:0] sb_rsv_tid [NUM_SCOREBOARDS];
    always_comb begin
        for (int sb = 0; sb < NUM_SCOREBOARDS; sb++) begin
            sb_rd_tid[sb]  = '0;
            sb_rsv_tid[sb] = '0;
            for (int lane = 0; lane < NUM_LANES; lane++) begin
                if (sb_rd_valid_per_sb[sb][lane])  sb_rd_tid[sb]  = check_tid[lane];
                if (sb_rsv_valid_per_sb[sb][lane]) sb_rsv_tid[sb] = reserve_tid[lane];
            end
        end
    end

    // Scoreboards for collision detection (4 scoreboards, one for each TID range)
    genvar i;
    generate
        for (i = 0; i < NUM_SCOREBOARDS; i++) begin : gen_scoreboards
            scoreboard #(
                .THREADS_PER_SCOREBOARD(THREADS_PER_SCOREBOARD),
                .SCOREBOARD_TID_WIDTH(SCOREBOARD_TID_WIDTH)  
            ) sb (
                .clk(clk_i),
                .rst(rst),
                .input_regs_map(input_register_bitmap), // Direct from input: 32GPR + 2PR (34 bits)
                .rd_tid(sb_rd_tid[i]),
                .rd_valid(sb_rd_valid[i]),              // Valid signal for read operation
                .rsv_tid(sb_rsv_tid[i]),
                .rsv_valid(|sb_rsv_valid_per_sb[i]),            // Valid signal for reserve operation
                .wb_tid_bitmap(wb_tid_sb[i]),           // Each scoreboard gets its 256-bit slice
                .ld_dest_regs_bitmap(ld_dest_regs_bitmap),         // Convert to 7 bits for scoreboard (GPR+Pred only)
                .wb_valid(wb_valid), 
                .clear_scoreboard(start_new_cta),           // Clear scoreboard on new CTA dispatch
                .collision(collision[i])
            );
        end
    endgenerate
    
    // Constant scoreboard for shared constant collision detection
    constant_scoreboard #(.NUM_CONSTANT_REGS(`DICE_CR_NUM)) const_sb (
        .clk(clk_i),
        .rst(rst),
        .input_const_map(const_bitmap),         // 32-bit constant register map
        .rd_valid(const_rd_valid),              // Valid when any lane needs checking
        .rsv_const_map(const_bitmap),           // Reserve the same constants
        .rsv_valid(const_rsv_valid),            // Valid when any lane is reserving
        .wb_const_bitmap(ld_dest_regs_bitmap[(`DICE_GPR_NUM + `DICE_CR_NUM - 1):`DICE_GPR_NUM]),  // Single constant register to release
        .wb_valid(wb_valid && |ld_dest_regs_bitmap[(`DICE_GPR_NUM + `DICE_CR_NUM - 1):`DICE_GPR_NUM]),  // Valid only for constant regs
        .collision(const_collision)
    );
    
    // Thread FIFO pop control - pop when no collision and can push to ready FIFOs
    logic all_lane_can_dispatch;
    always_comb begin
        all_lane_can_dispatch = 1'b1;
        case (latched_unrolling_factor)
            2'b00: all_lane_can_dispatch = !lane_collision[0] && !const_collision; // 1-way
            2'b01: all_lane_can_dispatch = !lane_collision[0] && !lane_collision[1] && !const_collision; // 2-way
            2'b10: all_lane_can_dispatch = !lane_collision[0] && !lane_collision[1] && !lane_collision[2] && !lane_collision[3] && !const_collision; // 4-way
            default: all_lane_can_dispatch = 1'b1; // Invalid unrolling factor
        endcase
    end


    logic ready_fifo_not_full;
    assign ready_fifo_not_full = !ready_fifo_full[0] && !ready_fifo_full[1] && !ready_fifo_full[2] && !ready_fifo_full[3];
    
    assign thread_fifo_pop = !thread_fifo_empty && all_lane_can_dispatch && ready_fifo_not_full;
    
    // Collision-free dispatch logic
    logic [NUM_LANES-1:0] ready_fifo_push_en; // per-lane push enable

    //flag of if current valid tids are checking collision
    logic is_checking_collision, is_checking_collision_next; //flag of current tids is checking collision and have not been pushed to ready fifo yet
    always_ff@(posedge clk_i) begin
        if (rst) begin
            is_checking_collision <= 1'b0;
        end else begin
            is_checking_collision <= is_checking_collision_next;
        end
    end

    always_comb begin
        // Default:
        is_checking_collision_next = is_checking_collision;
        // Determine if there are any valid TIDs checking collision
        if (is_checking_collision == 1'b0) begin
            if (thread_fifo_pop) 
                is_checking_collision_next = 1'b1;
            else 
                is_checking_collision_next = 1'b0;
        end else begin //clear or maintain the flag
            if (all_lane_can_dispatch && ready_fifo_not_full) begin
                if(thread_fifo_pop) 
                    is_checking_collision_next = 1'b1; //next valid tid coming, maintain the flag
                else 
                    is_checking_collision_next = 1'b0; //clear, no more valid tids
            end
        end
    end

    always_comb begin
        // NEW: Calculating per-lane push enable
        //when can push, 
        //firstly, if there is a group of tids is checking collision, if no valid tids then do not push
        //then check if previous tids are blocked by collision, if no previous tids or not blocked, then can push
        //finally check if ready fifo is full, if not full, then can push
        for (int i = 0; i < NUM_LANES; i++) begin
            ready_fifo_push_en[i] = is_checking_collision &&  
                                !lane_collision[i] && !const_collision && 
                                !ready_fifo_full[i];
        end
        // Push data assignments (unchanged)
        ready_fifo_push_data[0] = {thread_valid_0, thread_next_tid_0};
        ready_fifo_push_data[1] = {thread_valid_1, thread_next_tid_1};
        ready_fifo_push_data[2] = {thread_valid_2, thread_next_tid_2};
        ready_fifo_push_data[3] = {thread_valid_3, thread_next_tid_3};
    end
    
    // Ready-to-dispatch FIFOs using sync_fifo module
    generate
        for (i = 0; i < NUM_LANES; i++) begin : gen_ready_fifos
            sync_fifo #(
                .DATA_WIDTH(DICE_TID_WIDTH + 1),        // 11 bits: {valid, tid[9:0](DICE_TID_WIDTH)}
                .DEPTH(4)                               // 4 entries deep
            ) ready_fifo (
                .clk(clk_i),
                .rst(rst),
                .push(ready_fifo_push_en[i]),
                .push_data(ready_fifo_push_data[i]),
                .pop(dispatch_fifo_pop),
                .pop_data(ready_fifo_pop_data[i]),
                .pop_data_valid(ready_fifo_pop_data_valid[i]),
                .empty(ready_fifo_empty[i]),
                .full(ready_fifo_full[i]),
                .count() // Unused
            );
        end
    endgenerate
    
    // Output assignments - using registered FIFO outputs
    assign dispatch_tid_0 = ready_fifo_pop_data[0][DICE_TID_WIDTH-1:0];
    assign dispatch_valid_0 = ready_fifo_pop_data_valid[0] && ready_fifo_pop_data[0][DICE_TID_WIDTH];
    assign dispatch_tid_1 = ready_fifo_pop_data[1][DICE_TID_WIDTH-1:0];
    assign dispatch_valid_1 = ready_fifo_pop_data_valid[1] && ready_fifo_pop_data[1][DICE_TID_WIDTH];
    assign dispatch_tid_2 = ready_fifo_pop_data[2][DICE_TID_WIDTH-1:0];
    assign dispatch_valid_2 = ready_fifo_pop_data_valid[2] && ready_fifo_pop_data[2][DICE_TID_WIDTH];
    assign dispatch_tid_3 = ready_fifo_pop_data[3][DICE_TID_WIDTH-1:0];
    assign dispatch_valid_3 = ready_fifo_pop_data_valid[3] && ready_fifo_pop_data[3][DICE_TID_WIDTH];
    
    // Set output to one bus and one valid signal
    assign dispatch_tid_o = {dispatch_tid_3, dispatch_tid_2, dispatch_tid_1, dispatch_tid_0};
    assign dispatch_valid_o = {dispatch_valid_3, dispatch_valid_2, dispatch_valid_1, dispatch_valid_0};

    // Unrolling-aware logic
    logic dispatch_fifo_empty_comb;
    always_comb begin
        case (latched_unrolling_factor)
            2'b00: begin // 1-way unrolling
                // Only FIFO 0 matters
                dispatch_fifo_empty_comb = ready_fifo_empty[0];
            end
            
            2'b01: begin // 2-way unrolling
                // FIFOs 0 and 1 matter
                dispatch_fifo_empty_comb = ready_fifo_empty[0] && ready_fifo_empty[1];
            end
            
            2'b10: begin // 4-way unrolling
                // All 4 FIFOs matter
                dispatch_fifo_empty_comb = ready_fifo_empty[0] && ready_fifo_empty[1] && 
                                        ready_fifo_empty[2] && ready_fifo_empty[3];
            end
            
            default: begin
                // Shouldn't happen, but default to all empty
                dispatch_fifo_empty_comb = 1'b1;
            end
        endcase
    end

    assign dispatch_fifo_empty = dispatch_fifo_empty_comb;
endmodule