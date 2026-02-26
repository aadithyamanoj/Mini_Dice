module block_commit_table 
import dice_pkg::*;
#(
    parameter R_W = 14
) (
    input  logic                                    clk,
    input  logic                                    rst,
    
    // Entry insert interface
    input  logic                                    insert_valid,
    input  logic [DICE_HW_CTA_ID_WIDTH-1:0]         insert_hw_cta_id,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]          insert_e_block_id,
    input  logic [R_W-1:0]                            insert_pending_reads,
    input  logic [R_W-1:0]                            insert_pending_writes,
    
    // Pending read/write update interface
    input  logic                                    update_valid,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]          update_e_block_id,
    input  logic                                    update_is_write,      // 0: read, 1: write
    input  logic [2**DICE_HW_CTA_ID_WIDTH-1:0]                             update_reduce_count,  // max 8
    
    // E-block commit interface
    output logic                                    pop_valid,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0]          pop_e_block_id,
    input  logic                                    pop_ready,

    //status outputs
    output logic [2**DICE_HW_CTA_ID_WIDTH-1:0]         hw_cta_pending
);

    // Table entry structure
    typedef struct packed {
        logic                                       valid;
        logic [DICE_HW_CTA_ID_WIDTH-1:0]           hw_cta_id;
        logic [DICE_EBLOCK_ID_WIDTH-1:0]            e_block_id;
        logic [R_W-1:0]                               pending_reads;
        logic [R_W-1:0]                               pending_writes;
    } table_entry_t;

    // Table storage
    table_entry_t commit_table [2**DICE_EBLOCK_ID_WIDTH];

    // Round-robin priority pointer
    logic [DICE_EBLOCK_ID_WIDTH-1:0] rr_ptr;

    // Internal signals
    logic [2**DICE_EBLOCK_ID_WIDTH-1:0] ready_to_commit;
    logic [DICE_EBLOCK_ID_WIDTH-1:0] commit_idx;
    logic commit_found;

    // Entry insert logic
    always_ff @(posedge clk) begin
        if (rst) begin
            // Initialize all entries as invalid
            for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
                commit_table[i].valid <= 1'b0;
                commit_table[i].hw_cta_id <= '0;
                commit_table[i].e_block_id <= '0;
                commit_table[i].pending_reads <= '0;
                commit_table[i].pending_writes <= '0;
            end
        end else begin
            // Handle insert
            if (insert_valid) begin
                `ifndef SYNTHESIS
                if (commit_table[insert_e_block_id].valid) begin
                    $error("Error: Attempting to insert into occupied entry %0d at time %0t",
                           insert_e_block_id, $time);
                end
                `endif

                commit_table[insert_e_block_id].valid <= 1'b1;
                commit_table[insert_e_block_id].hw_cta_id <= insert_hw_cta_id;
                commit_table[insert_e_block_id].e_block_id <= insert_e_block_id;
                commit_table[insert_e_block_id].pending_reads <= insert_pending_reads;
                commit_table[insert_e_block_id].pending_writes <= insert_pending_writes;
            end

            // Handle pending count updates
            if (update_valid && commit_table[update_e_block_id].valid) begin
                if (update_is_write) begin
                    // Update pending writes
                    `ifndef SYNTHESIS
                    if (commit_table[update_e_block_id].pending_writes < update_reduce_count) begin
                        $error("Error: Pending writes underflow for entry %0d. Current: %0d, Reduce: %0d at time %0t",
                               update_e_block_id, commit_table[update_e_block_id].pending_writes,
                               update_reduce_count, $time);
                    end
                    `endif
                    commit_table[update_e_block_id].pending_writes <=
                        commit_table[update_e_block_id].pending_writes - update_reduce_count;
                end else begin
                    // Update pending reads
                    `ifndef SYNTHESIS
                    if (commit_table[update_e_block_id].pending_reads < update_reduce_count) begin
                        $error("Error: Pending reads underflow for entry %0d. Current: %0d, Reduce: %0d at time %0t",
                               update_e_block_id, commit_table[update_e_block_id].pending_reads,
                               update_reduce_count, $time);
                    end
                    `endif
                    commit_table[update_e_block_id].pending_reads <=
                        commit_table[update_e_block_id].pending_reads - update_reduce_count;
                end
            end

            // Handle commit/pop
            if (pop_valid && pop_ready) begin
                commit_table[commit_idx].valid <= 1'b0;
            end
        end
    end

    // Check which entries are ready to commit
    always_comb begin
        for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
            ready_to_commit[i] = commit_table[i].valid && 
                                (commit_table[i].pending_reads == {{R_W}{1'd0}}) && 
                                (commit_table[i].pending_writes == {{R_W}{1'd0}});
        end
    end

    // Round-robin priority logic for commit selection
    always_ff @(posedge clk) begin
        if (rst) begin
            rr_ptr <= '0;
        end else if (pop_valid && pop_ready) begin
            // Update round-robin pointer after successful commit
            if (rr_ptr == 2**DICE_EBLOCK_ID_WIDTH - 1)
                rr_ptr <= '0;
            else
                rr_ptr <= rr_ptr + 1'b1;
        end
    end

    // Find next entry to commit using round-robin priority
    always_comb begin
        commit_found = 1'b0;
        commit_idx = '0;

        // Search from current rr_ptr to end
        for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
            logic [DICE_EBLOCK_ID_WIDTH-1:0] idx;
            idx = (rr_ptr + i) % 2**DICE_EBLOCK_ID_WIDTH;
            if (ready_to_commit[idx] && !commit_found) begin
                commit_found = 1'b1;
                commit_idx = idx;
            end
        end
    end

    // Output assignments
    assign pop_valid = commit_found;
    assign pop_e_block_id = commit_idx;

    //output for each hw_cta
    always_comb begin
        hw_cta_pending = '0;
        for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
            if (commit_table[i].valid) begin
                hw_cta_pending[commit_table[i].hw_cta_id] = 1'b1;
            end
        end
    end

    // Assertions for verification
    `ifndef SYNTHESIS
    // Check that e_block_id matches the table index
    always_ff @(posedge clk) begin
        if (!rst && insert_valid) begin
            assert(insert_e_block_id < 2**DICE_EBLOCK_ID_WIDTH) 
                else $error("Invalid e_block_id %0d exceeds DICE_EBLOCK_ID_WIDTH %0d", 
                           insert_e_block_id, 2**DICE_EBLOCK_ID_WIDTH);
        end
        
        if (!rst && update_valid) begin
            assert(update_e_block_id < 2**DICE_EBLOCK_ID_WIDTH) 
                else $error("Invalid update e_block_id %0d exceeds DICE_EBLOCK_ID_WIDTH %0d", 
                           update_e_block_id, 2**DICE_EBLOCK_ID_WIDTH);
            assert(update_reduce_count <= 4'd8)
                else $error("Invalid reduce count %0d exceeds maximum of 8",
                           update_reduce_count);
        end
    end
    `endif

endmodule
