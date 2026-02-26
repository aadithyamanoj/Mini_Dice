module dispatcher_control
    import dice_pkg::*, 
           dice_frontend_pkg::*;
(
    output logic latch_inputs,
    output logic update_count,
    output logic deassert_restart,
    output logic incr_counter,
    output logic rst_counter, 
    output logic assert_restart, 
    output logic last_chunk_fin,
    output logic start_new_cta,
    output logic dispatcher_busy,
    output logic dispatcher_done,

    input logic fetch_done,
    input logic thread_chunk_done,
    input logic last_chunk_done,
    input logic dispatch_fifo_empty,
    input logic [1:0] chunk_counter, max_chunks,
    input logic clk, rst
);

    enum logic [1:0] {
        IDLE,
        DISPATCHING,
        DONE
    } ps, ns;

    always_comb begin
        case(ps)
            IDLE: begin
                if (fetch_done)
                    ns = DISPATCHING;
                else
                    ns = ps;
            end

            DISPATCHING: begin
                if (last_chunk_done && dispatch_fifo_empty)
                    ns = DONE;
                else
                    ns = ps;
            end

            DONE: begin
                if (fetch_done)
                    ns = DISPATCHING;
                else
                    ns = ps;
            end
        endcase
    end

    // IDLE
    assign latch_inputs     =   (ps == IDLE) && (ns == DISPATCHING);
    // DISPATCHING
    assign update_count     =   (ps == DISPATCHING);
    assign deassert_restart =   (ps == DISPATCHING);
    assign incr_counter     =   (ps == DISPATCHING) && thread_chunk_done && (chunk_counter < max_chunks);
    assign assert_restart   =   (ps == DISPATCHING) && thread_chunk_done && (chunk_counter < max_chunks);
    assign rst_counter      =   (ps == DISPATCHING) && thread_chunk_done && (chunk_counter >= max_chunks);
    assign last_chunk_fin  =   (ps == DISPATCHING) && thread_chunk_done && (chunk_counter >= max_chunks);
    // DONE
    assign start_new_cta    =   (ps == DONE) && (ns == DISPATCHING);

    // Status outputs 
    assign dispatcher_busy = (ps == DISPATCHING);
    assign dispatcher_done = (ps == DONE);

    // Synchronous reset
    always_ff @(posedge clk) begin
        if (rst)
            ps <= IDLE;
        else
            ps <= ns;
    end

endmodule
    