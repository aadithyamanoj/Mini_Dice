`ifdef GATE_SIM
// Gate-level wrapper: maps the flat PAR netlist ports of dice_core back to the
// SV interface/struct types used by the testbench.  Compiled only when
// GATE_SIM is defined so RTL sim is unaffected.
module dice_core_gate_wrap
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;
(
    input  logic clk_i,
    input  logic rst_i,

    cta_if.slave cta_if_inst,

    output slv_req_t  mfetch_req_o,
    input  slv_resp_t mfetch_resp_i,
    output slv_req_t  bsfetch_req_o,
    input  slv_resp_t bsfetch_resp_i,

    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX0_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX1_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX2_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX3_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX4_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX5_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX6_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] csrX7_i,

    output logic cgra_prog_dout_o,
    output logic cgra_prog_we_o,

    output logic [DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o,
    output logic                           axi_awvalid_o,
    input  logic                           axi_awready_i,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_wdata_o,
    output logic [                    1:0] axi_wstrb_o,
    output logic                           axi_wvalid_o,
    input  logic                           axi_wready_i,
    input  logic [                    1:0] axi_bresp_i,
    input  logic                           axi_bvalid_i,
    output logic                           axi_bready_o,
    output logic [DICE_REG_DATA_WIDTH-1:0] axi_araddr_o,
    output logic                           axi_arvalid_o,
    input  logic                           axi_arready_i,
    input  logic [DICE_REG_DATA_WIDTH-1:0] axi_rdata_i,
    input  logic [                    1:0] axi_rresp_i,
    input  logic                           axi_rvalid_i,
    output logic                           axi_rready_o
);

  // Internal structs to collect DUT flat outputs before driving the ports.
  slv_req_t mfetch_req_int;
  slv_req_t bsfetch_req_int;
  assign mfetch_req_o  = mfetch_req_int;
  assign bsfetch_req_o = bsfetch_req_int;

  dice_core u_dice_core_par (
    .clk_i (clk_i),
    .rst_i (rst_i),

    // ---- CTA interface (flattened by PAR) ----
    .cta_if_inst_dispatch_valid                          (cta_if_inst.dispatch_valid),
    .\cta_if_inst_dispatch_data[cta_id][z]               (cta_if_inst.dispatch_data.cta_id.z),
    .\cta_if_inst_dispatch_data[cta_id][y]               (cta_if_inst.dispatch_data.cta_id.y),
    .\cta_if_inst_dispatch_data[cta_id][x]               (cta_if_inst.dispatch_data.cta_id.x),
    .\cta_if_inst_dispatch_data[kernel_desc][start_pc]   (cta_if_inst.dispatch_data.kernel_desc.start_pc),
    .\cta_if_inst_dispatch_data[kernel_desc][thread_count] (cta_if_inst.dispatch_data.kernel_desc.thread_count),
    .\cta_if_inst_dispatch_data[kernel_desc][grid_size][z] (cta_if_inst.dispatch_data.kernel_desc.grid_size.z),
    .\cta_if_inst_dispatch_data[kernel_desc][grid_size][y] (cta_if_inst.dispatch_data.kernel_desc.grid_size.y),
    .\cta_if_inst_dispatch_data[kernel_desc][grid_size][x] (cta_if_inst.dispatch_data.kernel_desc.grid_size.x),
    .cta_if_inst_dispatch_ready                          (cta_if_inst.dispatch_ready),
    .cta_if_inst_complete_valid                          (cta_if_inst.complete_valid),
    .cta_if_inst_complete_ready                          (cta_if_inst.complete_ready),

    // ---- mfetch_req_o (output struct → flat outputs) ----
    .\mfetch_req_o[aw_valid]  (mfetch_req_int.aw_valid),
    .\mfetch_req_o[aw][id]    (mfetch_req_int.aw.id),
    .\mfetch_req_o[aw][addr]  (mfetch_req_int.aw.addr),
    .\mfetch_req_o[aw][len]   (mfetch_req_int.aw.len),
    .\mfetch_req_o[aw][size]  (mfetch_req_int.aw.size),
    .\mfetch_req_o[aw][burst] (mfetch_req_int.aw.burst),
    .\mfetch_req_o[aw][lock]  (mfetch_req_int.aw.lock),
    .\mfetch_req_o[aw][cache] (mfetch_req_int.aw.cache),
    .\mfetch_req_o[aw][prot]  (mfetch_req_int.aw.prot),
    .\mfetch_req_o[aw][qos]   (mfetch_req_int.aw.qos),
    .\mfetch_req_o[aw][region] (mfetch_req_int.aw.region),
    .\mfetch_req_o[aw][atop]  (mfetch_req_int.aw.atop),
    .\mfetch_req_o[aw][user]  (mfetch_req_int.aw.user),
    .\mfetch_req_o[w_valid]   (mfetch_req_int.w_valid),
    .\mfetch_req_o[w][data]   (mfetch_req_int.w.data),
    .\mfetch_req_o[w][strb]   (mfetch_req_int.w.strb),
    .\mfetch_req_o[w][last]   (mfetch_req_int.w.last),
    .\mfetch_req_o[w][user]   (mfetch_req_int.w.user),
    .\mfetch_req_o[b_ready]   (mfetch_req_int.b_ready),
    .\mfetch_req_o[ar_valid]  (mfetch_req_int.ar_valid),
    .\mfetch_req_o[ar][id]    (mfetch_req_int.ar.id),
    .\mfetch_req_o[ar][addr]  (mfetch_req_int.ar.addr),
    .\mfetch_req_o[ar][len]   (mfetch_req_int.ar.len),
    .\mfetch_req_o[ar][size]  (mfetch_req_int.ar.size),
    .\mfetch_req_o[ar][burst] (mfetch_req_int.ar.burst),
    .\mfetch_req_o[ar][lock]  (mfetch_req_int.ar.lock),
    .\mfetch_req_o[ar][cache] (mfetch_req_int.ar.cache),
    .\mfetch_req_o[ar][prot]  (mfetch_req_int.ar.prot),
    .\mfetch_req_o[ar][qos]   (mfetch_req_int.ar.qos),
    .\mfetch_req_o[ar][region] (mfetch_req_int.ar.region),
    .\mfetch_req_o[ar][user]  (mfetch_req_int.ar.user),
    .\mfetch_req_o[r_ready]   (mfetch_req_int.r_ready),

    // ---- mfetch_resp_i (input struct → flat inputs) ----
    .\mfetch_resp_i[aw_ready] (mfetch_resp_i.aw_ready),
    .\mfetch_resp_i[ar_ready] (mfetch_resp_i.ar_ready),
    .\mfetch_resp_i[w_ready]  (mfetch_resp_i.w_ready),
    .\mfetch_resp_i[b_valid]  (mfetch_resp_i.b_valid),
    .\mfetch_resp_i[b][id]    (mfetch_resp_i.b.id),
    .\mfetch_resp_i[b][resp]  (mfetch_resp_i.b.resp),
    .\mfetch_resp_i[b][user]  (mfetch_resp_i.b.user),
    .\mfetch_resp_i[r_valid]  (mfetch_resp_i.r_valid),
    .\mfetch_resp_i[r][id]    (mfetch_resp_i.r.id),
    .\mfetch_resp_i[r][data]  (mfetch_resp_i.r.data),
    .\mfetch_resp_i[r][resp]  (mfetch_resp_i.r.resp),
    .\mfetch_resp_i[r][last]  (mfetch_resp_i.r.last),
    .\mfetch_resp_i[r][user]  (mfetch_resp_i.r.user),

    // ---- bsfetch_req_o (output struct → flat outputs) ----
    .\bsfetch_req_o[aw_valid]  (bsfetch_req_int.aw_valid),
    .\bsfetch_req_o[aw][id]    (bsfetch_req_int.aw.id),
    .\bsfetch_req_o[aw][addr]  (bsfetch_req_int.aw.addr),
    .\bsfetch_req_o[aw][len]   (bsfetch_req_int.aw.len),
    .\bsfetch_req_o[aw][size]  (bsfetch_req_int.aw.size),
    .\bsfetch_req_o[aw][burst] (bsfetch_req_int.aw.burst),
    .\bsfetch_req_o[aw][lock]  (bsfetch_req_int.aw.lock),
    .\bsfetch_req_o[aw][cache] (bsfetch_req_int.aw.cache),
    .\bsfetch_req_o[aw][prot]  (bsfetch_req_int.aw.prot),
    .\bsfetch_req_o[aw][qos]   (bsfetch_req_int.aw.qos),
    .\bsfetch_req_o[aw][region] (bsfetch_req_int.aw.region),
    .\bsfetch_req_o[aw][atop]  (bsfetch_req_int.aw.atop),
    .\bsfetch_req_o[aw][user]  (bsfetch_req_int.aw.user),
    .\bsfetch_req_o[w_valid]   (bsfetch_req_int.w_valid),
    .\bsfetch_req_o[w][data]   (bsfetch_req_int.w.data),
    .\bsfetch_req_o[w][strb]   (bsfetch_req_int.w.strb),
    .\bsfetch_req_o[w][last]   (bsfetch_req_int.w.last),
    .\bsfetch_req_o[w][user]   (bsfetch_req_int.w.user),
    .\bsfetch_req_o[b_ready]   (bsfetch_req_int.b_ready),
    .\bsfetch_req_o[ar_valid]  (bsfetch_req_int.ar_valid),
    .\bsfetch_req_o[ar][id]    (bsfetch_req_int.ar.id),
    .\bsfetch_req_o[ar][addr]  (bsfetch_req_int.ar.addr),
    .\bsfetch_req_o[ar][len]   (bsfetch_req_int.ar.len),
    .\bsfetch_req_o[ar][size]  (bsfetch_req_int.ar.size),
    .\bsfetch_req_o[ar][burst] (bsfetch_req_int.ar.burst),
    .\bsfetch_req_o[ar][lock]  (bsfetch_req_int.ar.lock),
    .\bsfetch_req_o[ar][cache] (bsfetch_req_int.ar.cache),
    .\bsfetch_req_o[ar][prot]  (bsfetch_req_int.ar.prot),
    .\bsfetch_req_o[ar][qos]   (bsfetch_req_int.ar.qos),
    .\bsfetch_req_o[ar][region] (bsfetch_req_int.ar.region),
    .\bsfetch_req_o[ar][user]  (bsfetch_req_int.ar.user),
    .\bsfetch_req_o[r_ready]   (bsfetch_req_int.r_ready),

    // ---- bsfetch_resp_i (input struct → flat inputs) ----
    .\bsfetch_resp_i[aw_ready] (bsfetch_resp_i.aw_ready),
    .\bsfetch_resp_i[ar_ready] (bsfetch_resp_i.ar_ready),
    .\bsfetch_resp_i[w_ready]  (bsfetch_resp_i.w_ready),
    .\bsfetch_resp_i[b_valid]  (bsfetch_resp_i.b_valid),
    .\bsfetch_resp_i[b][id]    (bsfetch_resp_i.b.id),
    .\bsfetch_resp_i[b][resp]  (bsfetch_resp_i.b.resp),
    .\bsfetch_resp_i[b][user]  (bsfetch_resp_i.b.user),
    .\bsfetch_resp_i[r_valid]  (bsfetch_resp_i.r_valid),
    .\bsfetch_resp_i[r][id]    (bsfetch_resp_i.r.id),
    .\bsfetch_resp_i[r][data]  (bsfetch_resp_i.r.data),
    .\bsfetch_resp_i[r][resp]  (bsfetch_resp_i.r.resp),
    .\bsfetch_resp_i[r][last]  (bsfetch_resp_i.r.last),
    .\bsfetch_resp_i[r][user]  (bsfetch_resp_i.r.user),

    // ---- Scalar ports (identical in RTL and PAR) ----
    .csrX0_i        (csrX0_i),
    .csrX1_i        (csrX1_i),
    .csrX2_i        (csrX2_i),
    .csrX3_i        (csrX3_i),
    .csrX4_i        (csrX4_i),
    .csrX5_i        (csrX5_i),
    .csrX6_i        (csrX6_i),
    .csrX7_i        (csrX7_i),
    .cgra_prog_dout_o(cgra_prog_dout_o),
    .cgra_prog_we_o  (cgra_prog_we_o),
    .axi_awaddr_o   (axi_awaddr_o),
    .axi_awvalid_o  (axi_awvalid_o),
    .axi_awready_i  (axi_awready_i),
    .axi_wdata_o    (axi_wdata_o),
    .axi_wstrb_o    (axi_wstrb_o),
    .axi_wvalid_o   (axi_wvalid_o),
    .axi_wready_i   (axi_wready_i),
    .axi_bresp_i    (axi_bresp_i),
    .axi_bvalid_i   (axi_bvalid_i),
    .axi_bready_o   (axi_bready_o),
    .axi_araddr_o   (axi_araddr_o),
    .axi_arvalid_o  (axi_arvalid_o),
    .axi_arready_i  (axi_arready_i),
    .axi_rdata_i    (axi_rdata_i),
    .axi_rresp_i    (axi_rresp_i),
    .axi_rvalid_i   (axi_rvalid_i),
    .axi_rready_o   (axi_rready_o)
  );

endmodule
`endif // GATE_SIM
