`include "DE_pkg.sv"



// This is per bank, we_o already know which bank this will write to, so we_o only
//care about the tid. Address conversion has already happened, but we_o are keeping the !!
module dice_wr_ctrl_bank
import DE_pkg::*;
import dice_pkg::*;
#
(
      parameter WIDTH =  32
    , parameter DEPTH = 512
    , parameter ADDR_WIDTH = $clog2(DEPTH)
    , parameter BUF_DEPTH = 8
)
(
      input logic         clk_i
    , input logic         reset_i

    // wr req from LDST and CGRA
    , input  logic                      cgra_valid_i
    , output logic                      cgra_ready_o
    , input  reg_wr_cmd                 cgra_wr_i

    , input reg_wr_cmd   wr_ldst_i
    , input logic        ldst_valid_i

    // forwarding for read
    // , input [DICE_TID_WIDTH-1:0] fw_req_i

    // stall from either buffer
    , output logic       stall_o
    // forwarding flags for each entry in buffer
    // , output logic[7:0]         fw_hit_cgra_o
    // , output logic[7:0]         fw_hit_ldst_o
    // , output logic[WIDTH-1:0]   fw_data_o

    // signals out to register file
    , output logic[ADDR_WIDTH-1:0]   ws_o
    , output logic[WIDTH-1:0]        data_o
    , output logic                   we_o
);




  reg_wr_cmd cmd_lo;


// ---------------- CGRA buffer ----------------
  logic                  cgra_full,  cgra_empty;
  reg_wr_cmd             cgra_wb;
  logic                  cgra_wb_valid;
  // logic [BUF_DEPTH-1:0]  cgra_fw_hit;
  // logic [WIDTH-1:0]      cgra_fw_data_o;
  // logic                  cgra_fw_valid;
  logic                  pop_cgra;


  // single value write arbitration, does nothing right now :)

  reg_wr_single #(
        .WIDTH     (WIDTH)
      , .ADDR_WIDTH(ADDR_WIDTH)
  ) u_cgra_buf (
          .clk_i             (clk_i)
        , .reset_i           (reset_i)
        , .cgra_valid_i      (cgra_valid_i)
        , .cgra_ready_o      ()
        , .cgra_wr_i         (cgra_wr_i)
        , .valid_o           (cgra_wb_valid)
        , .cgra_wr_o         (cgra_wb)
        // , .fw_req_i          (fw_req_i)
        // , .fw_hit_o          () // forwarding unconnected for now
        // , .fw_data_o       () // forwarding unconnected for now 
        // , .fw_data_valid_o ()
  );

  // ---------------- LDST buffer ----------------
  logic                 ldst_full,  ldst_empty;
  reg_wr_cmd             ldst_wb;
  logic                  ldst_wb_valid;
  // logic [BUF_DEPTH-1:0]  ldst_fw_hit;
  // logic [WIDTH-1:0]      ldst_fw_data_o;
  // logic                  ldst_fw_valid;
  logic                  pop_ldst;

  reg_wr_buffer #(
          .WIDTH     (WIDTH)
        , .ADDR_WIDTH(ADDR_WIDTH)
        , .DEPTH     (BUF_DEPTH)
    ) u_ldst_buf (
          .clk_i          (clk_i)
        , .reset_i        (reset_i)
        , .wr_i           (wr_ldst_i)
        // , .fw_req_i       (fw_req_i)
        , .pop_i          (pop_ldst)
        , .valid_i        (ldst_valid_i)
        , .full_o         (ldst_full)
        , .empty_o        (ldst_empty)
        , .cmd_o          (ldst_wb)
        , .wb_valid_o     (ldst_wb_valid)
        // , .fw_hit_o       () // forwarding unconnected for now
        // , .fw_data_o      () // forwarding unconnected for now
        // , .fw_data_valid_o() // forwarding unconnected for now
    );

  assign stall_o = ldst_full;

  // assign fw_hit_ldst_o = ldst_fw_hit;
  // assign fw_hit_cgra_o = cgra_fw_hit;

  //fw data

  // always_comb begin
  //   if (cgra_fw_valid) begin
  //     fw_data_o = cgra_fw_data_o;
  //   end else if (ldst_fw_valid) begin
  //     fw_data_o = ldst_fw_data_o;
  //   end else begin
  //     fw_data_o = '0;
  //   end
  // end

  // wb arbitration

  always_comb begin
    cmd_lo = cgra_wb_valid ? cgra_wb : ldst_wb;
    pop_ldst = !cgra_wb_valid;

    data_o = cmd_lo.data;
    we_o = cmd_lo.mask;
    ws_o = cmd_lo.tid;
  end


endmodule
