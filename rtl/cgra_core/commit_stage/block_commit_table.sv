module block_commit_table 
    import dice_pkg::*;
#(
    parameter int R_W = 14
) (
    input  logic                                    clk_i,
    input  logic                                    rst_i,
    
    // Entry insert interface
    input  logic                                    insert_valid_i,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]         insert_e_block_id_i,
    input  logic [R_W-1:0]                          insert_pending_reads_i,
    input  logic [R_W-1:0]                          insert_pending_writes_i,
    
    // Pending read/write update interface
    input  logic                                    update_valid_i,
    input  logic [DICE_EBLOCK_ID_WIDTH-1:0]         update_e_block_id_i,
    input  logic                                    update_is_write_i,    // 0: read, 1: write
    input  logic [2**DICE_HW_CTA_ID_WIDTH-1:0]      update_reduce_count_i,  // max 8
    
    // E-block commit interface
    output logic                                    pop_valid_o,
    output logic [DICE_EBLOCK_ID_WIDTH-1:0]         pop_e_block_id_o, //eblock id width is 3 bits
    input  logic                                    pop_ready_i,

    //status outputs
    output logic                                    hw_cta_pending_o
);

    // Table entry structure
    typedef struct packed {
        logic                            valid;
        logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_id;
        logic [R_W-1:0]                  pending_reads;
        logic [R_W-1:0]                  pending_writes;
    } table_entry_t;

    // Table storage
    table_entry_t commit_table [2**DICE_EBLOCK_ID_WIDTH]; // 8 entries

    // Round-robin priority pointer
    logic [DICE_EBLOCK_ID_WIDTH-1:0] rr_ptr;

    // Internal signals
    logic [2**DICE_EBLOCK_ID_WIDTH-1:0] ready_to_commit;
    logic [DICE_EBLOCK_ID_WIDTH-1:0] commit_idx;
    logic commit_found;

    // Entry insert logic
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            // Initialize all entries as invalid
            for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
                commit_table[i].valid <= 1'b0;
                commit_table[i].e_block_id <= '0;
                commit_table[i].pending_reads <= '0;
                commit_table[i].pending_writes <= '0;
            end
        end else begin
            // Handle insert
            if (insert_valid_i) begin
                commit_table[insert_e_block_id_i].valid <= 1'b1;
                commit_table[insert_e_block_id_i].e_block_id <= insert_e_block_id_i;
                commit_table[insert_e_block_id_i].pending_reads <= insert_pending_reads_i;
                commit_table[insert_e_block_id_i].pending_writes <= insert_pending_writes_i;
            end

            // Handle pending count updates
            if (update_valid_i && commit_table[update_e_block_id_i].valid) begin
                if (update_is_write_i) begin
                    // Update pending writes
                    commit_table[update_e_block_id_i].pending_writes <=
                        commit_table[update_e_block_id_i].pending_writes - update_reduce_count_i;
                end else begin
                    // Update pending reads
                    commit_table[update_e_block_id_i].pending_reads <=
                        commit_table[update_e_block_id_i].pending_reads - update_reduce_count_i;
                end
            end

            // Handle commit/pop
            if (pop_valid_o && pop_ready_i) begin
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
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rr_ptr <= '0;
        end else if (pop_valid_o && pop_ready_i) begin
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
    assign pop_valid_o = commit_found;
    assign pop_e_block_id_o = commit_idx;

    // Any valid entry means the CTA has a pending eblock
    always_comb begin
        hw_cta_pending_o = 1'b0;
        for (int i = 0; i < 2**DICE_EBLOCK_ID_WIDTH; i++) begin
            if (commit_table[i].valid)
                hw_cta_pending_o = 1'b1;
        end
    end


// Assertions for verification
`ifndef SYNTHESIS
    // No double-insert: target slot must be empty on an insert
    assert_no_double_insert: assert property (
        @(posedge clk_i) disable iff (rst_i)
        insert_valid_i |-> !commit_table[insert_e_block_id_i].valid
    ) else $error("Error: Attempting to insert into occupied entry %0d at time %0t",
                  insert_e_block_id_i, $time);

    // Insert e_block_id must be a valid table index
    assert_insert_id_in_range: assert property (
        @(posedge clk_i) disable iff (rst_i)
        insert_valid_i |-> (insert_e_block_id_i < 2**DICE_EBLOCK_ID_WIDTH)
    ) else $error("Invalid e_block_id %0d exceeds DICE_EBLOCK_ID_WIDTH %0d",
                  insert_e_block_id_i, 2**DICE_EBLOCK_ID_WIDTH);

    // Update e_block_id must be a valid table index
    assert_update_id_in_range: assert property (
        @(posedge clk_i) disable iff (rst_i)
        update_valid_i |-> (update_e_block_id_i < 2**DICE_EBLOCK_ID_WIDTH)
    ) else $error("Invalid update e_block_id %0d exceeds DICE_EBLOCK_ID_WIDTH %0d",
                  update_e_block_id_i, 2**DICE_EBLOCK_ID_WIDTH);

    // Update reduce count must not exceed the maximum of 8
    assert_reduce_count_max: assert property (
        @(posedge clk_i) disable iff (rst_i)
        update_valid_i |-> (update_reduce_count_i <= 4'd8)
    ) else $error("Invalid reduce count %0d exceeds maximum of 8", update_reduce_count_i);

    // Pending writes must not underflow on a write update
    assert_no_write_underflow: assert property (
        @(posedge clk_i) disable iff (rst_i)
        (update_valid_i && commit_table[update_e_block_id_i].valid && update_is_write_i) |->
        (commit_table[update_e_block_id_i].pending_writes >= update_reduce_count_i)
    ) else $error("Error: Pending writes underflow for entry %0d. Current: %0d, Reduce: %0d at time %0t",
                  update_e_block_id_i, commit_table[update_e_block_id_i].pending_writes,
                  update_reduce_count_i, $time);

    // Pending reads must not underflow on a read update
    assert_no_read_underflow: assert property (
        @(posedge clk_i) disable iff (rst_i)
        (update_valid_i && commit_table[update_e_block_id_i].valid && !update_is_write_i) |->
        (commit_table[update_e_block_id_i].pending_reads >= update_reduce_count_i)
    ) else $error("Error: Pending reads underflow for entry %0d. Current: %0d, Reduce: %0d at time %0t",
                  update_e_block_id_i, commit_table[update_e_block_id_i].pending_reads,
                  update_reduce_count_i, $time);
`endif // SYNTHESIS

endmodule
