// Single-entry CGRA write buffer with valid/ready handshake.
// - CGRA side:  in_valid/in_ready
// - RF side:    out_valid/out_ready
// - Latest write wins; supports in+out in same cycle (no bubble).

module reg_wr_single 
import DE_pkg::*;
import dice_pkg::*;
#(
      parameter int WIDTH      = 32
    , parameter int ADDR_WIDTH = $clog2(512)
) (
    input  logic        clk_i,
    input  logic        reset_i,

    // Upstream CGRA write interface
    input  logic                      cgra_valid_i,
    output logic                      cgra_ready_o,
    input  reg_wr_cmd                 cgra_wr_i,

    // Downstream interface to RF arbiter (CGRA has priority there)
    output logic                      valid_o,
    output reg_wr_cmd                 cgra_wr_o

    // Forwarding interface
    // input  [DICE_TID_WIDTH-1:0]   fw_req_i,
    // output logic        fw_hit_o,
    // output logic [WIDTH-1:0] fw_data_o,
    // output logic        fw_data_valid_o
);


    // no register, this is basically a passthrough until i have forwarding. 
    assign valid_o   = cgra_valid_i;
    assign cgra_wr_o = cgra_wr_i;

    assign cgra_ready_o = 1'b1;

    // TODO: implement read forwarding

    // // ------------------------------------------------------------
    // // Forwarding: single-entry, trivial
    // // ------------------------------------------------------------
    // always_comb begin
    //     fw_hit_o         = 1'b0;
    //     fw_data_o        = '0;
    //     fw_data_valid_o  = 1'b0;

    //     if (fw_req_i.re && valid_r && entry_r.we &&
    //         (entry_r.tid == fw_req_i.tid) &&
    //         (entry_r.ws  == fw_req_i.rs[ADDR_WIDTH-1:0])) begin
    //         fw_hit_o        = 1'b1;
    //         fw_data_o       = entry_r.data;
    //         fw_data_valid_o = 1'b1;
    //     end
    // end

endmodule
