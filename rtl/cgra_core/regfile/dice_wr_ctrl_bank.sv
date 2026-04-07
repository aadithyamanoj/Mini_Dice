`include "DE_pkg.sv"



// This is per bank, we_o already know which bank this will write to, so we_o only
//care about the tid. Address conversion has already happened, but we_o are keeping the !!
module dice_wr_ctrl_bank
<<<<<<< HEAD
  import DE_pkg::*;
  import dice_pkg::*;
#(
    parameter WIDTH = 32
    , parameter DEPTH = 512
    , parameter ADDR_WIDTH = $clog2(DEPTH)
    , parameter BUF_DEPTH = 8
) (
      input logic clk_i
    , input logic reset_i

    // wr req from LDST and CGRA
    , input  logic      cgra_valid_i
    , output logic      cgra_ready_o
    , input  reg_wr_cmd cgra_wr_i

    , input reg_wr_cmd wr_ldst_i
    , input logic      ldst_valid_i

    // stall from either buffer
    , output logic stall_o
    , output logic ldst_pop_o


    // signals out to register file
    , output logic [ADDR_WIDTH-1:0] ws_o
    , output logic [     WIDTH-1:0] data_o
    , output logic                  we_o
);
  reg_wr_cmd cmd_lo;
  logic ldst_full, ldst_empty;
  reg_wr_cmd ldst_wb;
  logic      ldst_wb_valid;
  logic      pop_ldst;
  logic      cgra_bank_write;

  localparam int WBUF = $bits(reg_wr_cmd);
  reg_wr_buffer #(
        .WIDTH     (WBUF)
      , .ADDR_WIDTH(ADDR_WIDTH)
      , .DEPTH     (BUF_DEPTH)
  ) u_ldst_buf (
        .clk_i     (clk_i)
      , .reset_i   (reset_i)
      , .wr_i      (wr_ldst_i)
      , .pop_i     (pop_ldst)
      , .valid_i   (ldst_valid_i)
      , .full_o    (ldst_full)
      , .empty_o   (ldst_empty)
      , .cmd_o     (ldst_wb)
      , .wb_valid_o(ldst_wb_valid)

  );

  assign stall_o = ldst_full;
  assign cgra_ready_o = 1'b1;
  assign ldst_pop_o = pop_ldst;

  always_comb begin
    cgra_bank_write = cgra_valid_i && cgra_wr_i.mask;
    cmd_lo   = cgra_bank_write ? cgra_wr_i : ldst_wb;
    pop_ldst = !cgra_bank_write && ldst_wb_valid;
    data_o   = cmd_lo.data;
    we_o     = cgra_bank_write || (!cgra_bank_write && ldst_wb_valid && ldst_wb.mask);
    ws_o     = cmd_lo.tid;
=======
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

    // stall from either buffer
    , output logic       stall_o


    // signals out to register file
    , output logic[ADDR_WIDTH-1:0]   ws_o
    , output logic[WIDTH-1:0]        data_o
    , output logic                   we_o
);



  // arbitrated output
  reg_wr_cmd cmd_lo;
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
        , .pop_i          (pop_ldst)
        , .valid_i        (ldst_valid_i)
        , .full_o         (ldst_full)
        , .empty_o        (ldst_empty)
        , .cmd_o          (ldst_wb)
        , .wb_valid_o     (ldst_wb_valid)

    );

  assign stall_o = ldst_full;

  always_comb begin
    cmd_lo   = cgra_valid_i ? cgra_wr_i : ldst_wb;
    pop_ldst = !cgra_valid_i && ldst_wb_valid;

    data_o = cmd_lo.data;
    we_o   = (cgra_valid_i | ldst_wb_valid) & cmd_lo.mask;
    ws_o   = cmd_lo.tid;
>>>>>>> origin/merging
  end


endmodule
