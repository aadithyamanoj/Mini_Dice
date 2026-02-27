// `include "bsg_defines.sv"
`include "DE_pkg.sv"
`include "dice_pkg.sv"




module reg_wr_buffer 

import DE_pkg::*;
import dice_pkg::*;
#(
      parameter int WIDTH      = $bits(reg_wr_cmd)
    , parameter int ADDR_WIDTH = $clog2(512)
    , parameter int DEPTH      = LDST_BUF_DEPTH   // must be 8 for the casez below
) (
      input  logic            clk_i
    , input  logic            reset_i

    // incoming write command
    , input  reg_wr_cmd       wr_i

    // forwarding read command
    // , input  [DICE_TID_WIDTH-1:0]       fw_req_i

    // pop oldest entry (writeback consumed)
    , input  logic            pop_i
    , input  logic            valid_i

    // status
    , output logic            full_o
    , output logic            empty_o

    // writeback (oldest entry)
    , output reg_wr_cmd                  cmd_o
    , output logic                       wb_valid_o

    // forwarding info
    // , output logic [DEPTH-1:0]      fw_hit_o
    // , output logic [WIDTH-1:0]      fw_data_o
    // , output logic                  fw_data_valid_o
);


    logic ready_lo;

    logic [$bits(reg_wr_cmd)-1:0] data_li, data_lo;
    assign data_li = wr_i;


    bsg_fifo_1r1w_small#
        (.width_p  (WIDTH)
        ,.els_p  (DEPTH)
        )
        wr_buf
        (.clk_i (clk_i)
        ,.reset_i  (reset_i)

        ,.v_i      (valid_i)
        ,.ready_o  (ready_lo)
        ,.data_i   (data_li)

        ,.v_o      (wb_valid_o)
        ,.data_o   (data_lo)
        ,.yumi_i   (pop_i)
        );

    assign full_o = ~ready_lo;
    assign cmd_o = data_lo;
    // localparam int ptr_width_lp = $clog2(DEPTH);

    // // ----------------------------------------------------------------
    // // Pointer tracker
    // // ----------------------------------------------------------------
    // logic [ptr_width_lp-1:0] wptr_r, rptr_r;
    // logic                    full, empty;

    // logic enq_li, deq_li;

    // // Enqueue when we have a write and not full
    // assign enq_li =  valid_i & ~full;
    // // Dequeue when pop requested and not empty
    // assign deq_li = pop_i   & ~empty;

    // fifo_ctrl_credit #(
    //     .els_p(DEPTH)
    // ) fifo_track (
    //     .clk_i     (clk_i),
    //     .reset_i   (reset_i),
    //     .enq_i     (enq_li),
    //     .deq_i     (deq_li),
    //     .wptr_r_o  (wptr_r),
    //     .rptr_r_o  (rptr_r),
    //     .full_o    (full),
    //     .empty_o   (empty)
    // );

    // // wire enq_r = fifo_track.enq_r;

    // assign full_o  = full;
    // assign empty_o = empty;

    // // ----------------------------------------------------------------
    // // 1R/1W memoryfully visible for forwarding
    // // ----------------------------------------------------------------


    // reg_wr_cmd buffer [DEPTH];

    // integer i;
    // always_ff @(posedge clk_i) begin
    //     if (reset_i) begin
    //         for (i = 0; i < DEPTH; i++) begin
    //             buffer[i] <= '0;
    //         end
    //     end else begin
    //         // Enqueue: write new entry at current write pointer
    //         if (enq_li && !full) begin
    //             buffer[wptr_r] <= wr_i;
    //         end
    //     end
    // end

    // // ----------------------------------------------------------------
    // // Oldest entry for writeback
    // // ----------------------------------------------------------------
    // always_comb begin
    //     cmd_o = buffer[rptr_r];
    // end


    // assign fw_data_o = '0;
    // assign fw_hit_o = '0;
    // assign fw_data_valid_o = '0;

    // TODO: Implement read forwarding
    // // ----------------------------------------------------------------
    // // Forwarding:
    // //  - fw_hit_o[i] marks all matching entries by physical index
    // //  - Youngest priority: newest is at wptr_r-1, then wptr_r-2, ...
    // //    We build an "age_hits" vector in age order and use casez.
    // // ----------------------------------------------------------------
    // logic [DEPTH-1:0] hit_vec;

    // function automatic logic in_window (
    // input logic [ptr_width_lp-1:0] idx,
    // input logic [ptr_width_lp-1:0] rptr,
    // input logic [ptr_width_lp-1:0] wptr,
    // input logic          full,
    // input logic          empty
    // );
    // if (empty)      return 1'b0;
    // else if (full)  return 1'b1;
    // else if (wptr > rptr)
    //     // straight region: [rptr .. wptr-1]
    //     return (idx >= rptr) && (idx < wptr);
    // else
    //     // wrapped region: [rptr .. DEPTH-1] U [0 .. wptr-1]
    //     return (idx >= rptr) || (idx < wptr);
    // endfunction


    // always_comb begin
    //     fw_hit_o        = '0;
    //     fw_data_o       = '0;
    //     fw_data_valid_o = 1'b0;

    //     hit_vec         = '0;

    //     if (fw_req_i.re && !empty_o) begin
    //     for (int j = 0; j < DEPTH; j++) begin
    //         logic [ptr_width_lp-1:0] ji = j[ptr_width_lp-1:0];

    //         if (in_window(ji, rptr_r, wptr_r, full_o, empty_o) &&
    //             buffer[j].tid  == fw_req_i.tid &&
    //             buffer[j].addr == fw_req_i.rs[ADDR_WIDTH-1:0]) begin
    //                 hit_vec[j]  = 1'b1;
    //             end
    //         end
    //     end

    //     fw_hit_o = hit_vec;

    //     // idx0 = wptr_r - 1;
    //     // idx1 = wptr_r - 2;
    //     // idx2 = wptr_r - 3;
    //     // idx3 = wptr_r - 4;
    //     // idx4 = wptr_r - 5;
    //     // idx5 = wptr_r - 6;
    //     // idx6 = wptr_r - 7;
    //     // idx7 = wptr_r - 8;

    //     if (fw_req_i.re && !empty_o) begin
    //         // if (in_window(idx0, rptr_r, wptr_r, full_o, empty_o) && hit_vec[idx0]) begin
    //         //     fw_data_o       = buffer[idx0].data;
    //         //     fw_data_valid_o = 1'b1;
    //         // end
    //         for(int i = 1; i<=DEPTH; i++) begin
    //             if (in_window(wptr_r-i, rptr_r, wptr_r, full_o, empty_o) && hit_vec[wptr_r-i]) begin
    //                 fw_data_o       = buffer[wptr_r-i].data;
    //                 fw_data_valid_o = 1'b1;
    //             end
    //         end
    //     end


    // end

endmodule
