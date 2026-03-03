module fifo_ctrl_credit #(
    parameter int els_p        = 8,
    parameter int ptr_width_lp = $clog2(els_p)
) (
    input  logic                   clk_i,
    input  logic                   reset_i,

    // request to enqueue / dequeue this cycle
    input  logic                   enq_i,
    input  logic                   deq_i,

    // circular pointers
    output logic [ptr_width_lp-1:0] wptr_r_o,
    output logic [ptr_width_lp-1:0] rptr_r_o,

    // status
    output logic                   full_o,
    output logic                   empty_o
);

    // ------------------------------------------------------------
    // State: pointers + occupancy counter
    // ------------------------------------------------------------
    logic [ptr_width_lp-1:0] wptr_r, rptr_r;
    logic [$clog2(els_p+1)-1:0] count_r;   // 0..els_p

    // --- wrap-around helper
    function automatic [ptr_width_lp-1:0] next_ptr (
        input [ptr_width_lp-1:0] ptr
    );
        // verilator lint_off WIDTH
        if (ptr == els_p-1)
            next_ptr = '0;
        else
            next_ptr = ptr + 1;
        // verilator lint_on WIDTH
    endfunction

    // ------------------------------------------------------------
    // Derived flags (external interface)
    // ------------------------------------------------------------
    // verilator lint_off WIDTH
    assign full_o  = (count_r == els_p);
    // verilator lint_on WIDTH
    assign empty_o = (count_r == 0);

    // ------------------------------------------------------------
    // Sequential update
    // ------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            wptr_r  <= '0;
            rptr_r  <= '0;
            count_r <= '0;
        end else begin
            unique case ({enq_i, deq_i})
                2'b10: begin
                    // enqueue only
                    wptr_r  <= next_ptr(wptr_r);
                    count_r <= count_r + 1;
                end

                2'b01: begin
                    // dequeue only
                    // $display("dequeing!");
                    rptr_r  <= next_ptr(rptr_r);
                    count_r <= count_r - 1;
                end

                2'b11: begin
                    // enqueue + dequeue same cycle
                    // occupancy unchanged, pointers both advance
                    wptr_r  <= next_ptr(wptr_r);
                    rptr_r  <= next_ptr(rptr_r);
                end

                default: begin
                    // 2'b00: idle
                    // no change
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    assign wptr_r_o = wptr_r;
    assign rptr_r_o = rptr_r;

endmodule
