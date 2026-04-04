module fdr_top_syn_wrap
  import dice_pkg::*;
  import dice_frontend_pkg::*;
#(
  parameter int TAG_WIDTH                      = DICE_ADDR_WIDTH,
  parameter int BITSTREAM_SIZE                 = DICE_BITSTREAM_SIZE,
  parameter int MEM_FLAGS_WIDTH_P              = DICE_MEM_FLAGS_WIDTH,
  parameter int MEM_ADDR_WIDTH_P               = DICE_MEM_ADDR_WIDTH,
  parameter int METACACHE_MEM_DATA_SIZE_P      = DICE_MEM_DATA_WIDTH / 8,
  parameter int METACACHE_MEM_DATA_WIDTH_P     = METACACHE_MEM_DATA_SIZE_P * 8,
  parameter int METACACHE_MEM_REQ_ADDR_WIDTH_P = MEM_ADDR_WIDTH_P - $clog2(METACACHE_MEM_DATA_SIZE_P),
  parameter int BITSTREAM_MEM_DATA_SIZE_P      = DICE_MEM_DATA_WIDTH / 8,
  parameter int BITSTREAM_MEM_DATA_WIDTH_P     = BITSTREAM_MEM_DATA_SIZE_P * 8,
  parameter int BITSTREAM_MEM_REQ_ADDR_WIDTH_P = MEM_ADDR_WIDTH_P - $clog2(BITSTREAM_MEM_DATA_SIZE_P),
  parameter int CM_DATA_WIDTH_P                = DICE_MEM_DATA_WIDTH,
  parameter int CM_CHUNK_COUNT_P               = (DICE_BITSTREAM_SIZE + CM_DATA_WIDTH_P - 1) / CM_DATA_WIDTH_P
) (
  input logic clk_i,
  input logic rst_i,

  // Scheduler -> FDR
  input  logic             schedule_valid_i,
  input  schedule_eblock_t schedule_data_i,
  output logic             schedule_ready_o,

  // FDR -> backend
  output logic fdr_valid_o,
  output fdr_t fdr_data_o,
  input  logic fdr_ready_i,

  // Scheduler status/SIMT context -> FDR
  input simt_stack_status_entry_t simt_status_i,
  input dice_cta_status_t         cta_status_data_i,

  // Meta cache bus (wrapper environment <-> FDR)
  input  logic                                      metacache_req_ready_i,
  input  logic                                      metacache_rsp_valid_i,
  input  logic [METACACHE_MEM_DATA_WIDTH_P-1:0]     metacache_rsp_data_i,
  input  logic [TAG_WIDTH-1:0]                      metacache_rsp_tag_i,
  output logic                                      metacache_rsp_ready_o,
  output logic                                      metacache_req_valid_o,
  output logic                                      metacache_req_rw_o,
  output logic [METACACHE_MEM_REQ_ADDR_WIDTH_P-1:0] metacache_req_addr_o,
  output logic [METACACHE_MEM_DATA_WIDTH_P-1:0]     metacache_req_data_o,
  output logic [METACACHE_MEM_DATA_SIZE_P-1:0]      metacache_req_byteen_o,
  output logic [MEM_FLAGS_WIDTH_P-1:0]              metacache_req_flags_o,
  output logic [TAG_WIDTH-1:0]                      metacache_req_tag_o,

  // Bitstream cache bus (wrapper environment <-> FDR)
  input  logic                                      bitstream_req_ready_i,
  input  logic                                      bitstream_rsp_valid_i,
  input  logic [BITSTREAM_MEM_DATA_WIDTH_P-1:0]     bitstream_rsp_data_i,
  input  logic [TAG_WIDTH-1:0]                      bitstream_rsp_tag_i,
  output logic                                      bitstream_rsp_ready_o,
  output logic                                      bitstream_req_valid_o,
  output logic                                      bitstream_req_rw_o,
  output logic [BITSTREAM_MEM_REQ_ADDR_WIDTH_P-1:0] bitstream_req_addr_o,
  output logic [BITSTREAM_MEM_DATA_WIDTH_P-1:0]     bitstream_req_data_o,
  output logic [BITSTREAM_MEM_DATA_SIZE_P-1:0]      bitstream_req_byteen_o,
  output logic [MEM_FLAGS_WIDTH_P-1:0]              bitstream_req_flags_o,
  output logic [TAG_WIDTH-1:0]                      bitstream_req_tag_o,

  // Branch handler/status-table outputs
  output branch_predict_interface_t bh_branch_predict_info_o,
  output logic                      bh_branch_predict_info_we_o,

  // SIMT update interface outputs
  output logic                            simt_update_valid_o,
  input  logic                            simt_update_ready_i,
  output simt_stack_update_t              simt_update_stack_data_o,

  // CGRA configuration memory outputs
  output logic [CM_DATA_WIDTH_P-1:0]  cm0_data_o,
  output logic [CM_CHUNK_COUNT_P-1:0] cm0_chunk_en_o,
  output logic [CM_DATA_WIDTH_P-1:0]  cm1_data_o,
  output logic [CM_CHUNK_COUNT_P-1:0] cm1_chunk_en_o,

  // Eblock flush notification
  output logic                       eblock_flush_valid_o,
  output logic [EBLOCK_ID_WIDTH-1:0] eblock_flush_id_o
);

  dice_mem_bus_if #(
    .DATA_SIZE(METACACHE_MEM_DATA_SIZE_P),
    .FLAGS_WIDTH(MEM_FLAGS_WIDTH_P),
    .TAG_WIDTH(TAG_WIDTH),
    .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH_P),
    .ADDR_WIDTH(METACACHE_MEM_REQ_ADDR_WIDTH_P)
  ) metacache_mem_if ();

  dice_mem_bus_if #(
    .DATA_SIZE(BITSTREAM_MEM_DATA_SIZE_P),
    .FLAGS_WIDTH(MEM_FLAGS_WIDTH_P),
    .TAG_WIDTH(TAG_WIDTH),
    .MEM_ADDR_WIDTH(MEM_ADDR_WIDTH_P),
    .ADDR_WIDTH(BITSTREAM_MEM_REQ_ADDR_WIDTH_P)
  ) bitstream_cache_mem_if ();

  cta_sched_if         schedule_if_inst ();
  fdr_if               fdr_if_inst ();

  cgra_cm_if           cm0_if_inst ();
  cgra_cm_if           cm1_if_inst ();

  assign schedule_if_inst.valid = schedule_valid_i;
  assign schedule_if_inst.data  = schedule_data_i;
  assign schedule_ready_o       = schedule_if_inst.ready;

  assign fdr_if_inst.ready = fdr_ready_i;
  assign fdr_valid_o       = fdr_if_inst.valid;
  assign fdr_data_o        = fdr_if_inst.data;



  assign metacache_mem_if.req_ready        = metacache_req_ready_i;
  assign metacache_mem_if.rsp_valid        = metacache_rsp_valid_i;
  assign metacache_mem_if.rsp_data.data    = metacache_rsp_data_i;
  assign metacache_mem_if.rsp_data.tag.uuid = metacache_rsp_tag_i;

  assign bitstream_cache_mem_if.req_ready        = bitstream_req_ready_i;
  assign bitstream_cache_mem_if.rsp_valid        = bitstream_rsp_valid_i;
  assign bitstream_cache_mem_if.rsp_data.data    = bitstream_rsp_data_i;
  assign bitstream_cache_mem_if.rsp_data.tag.uuid = bitstream_rsp_tag_i;

  assign metacache_rsp_ready_o = metacache_mem_if.rsp_ready;
  assign metacache_req_valid_o = metacache_mem_if.req_valid;
  assign metacache_req_rw_o    = metacache_mem_if.req_data.rw;
  assign metacache_req_addr_o  = metacache_mem_if.req_data.addr;
  assign metacache_req_data_o  = metacache_mem_if.req_data.data;
  assign metacache_req_byteen_o = metacache_mem_if.req_data.byteen;
  assign metacache_req_flags_o = metacache_mem_if.req_data.flags;
  assign metacache_req_tag_o   = metacache_mem_if.req_data.tag.uuid;

  assign bitstream_rsp_ready_o = bitstream_cache_mem_if.rsp_ready;
  assign bitstream_req_valid_o = bitstream_cache_mem_if.req_valid;
  assign bitstream_req_rw_o    = bitstream_cache_mem_if.req_data.rw;
  assign bitstream_req_addr_o  = bitstream_cache_mem_if.req_data.addr;
  assign bitstream_req_data_o  = bitstream_cache_mem_if.req_data.data;
  assign bitstream_req_byteen_o = bitstream_cache_mem_if.req_data.byteen;
  assign bitstream_req_flags_o = bitstream_cache_mem_if.req_data.flags;
  assign bitstream_req_tag_o   = bitstream_cache_mem_if.req_data.tag.uuid;

  assign cm0_data_o     = cm0_if_inst.data;
  assign cm0_chunk_en_o = cm0_if_inst.chunk_en;
  assign cm1_data_o     = cm1_if_inst.data;
  assign cm1_chunk_en_o = cm1_if_inst.chunk_en;

  fdr_top #(
    .TAG_WIDTH(TAG_WIDTH),
    .BITSTREAM_SIZE(BITSTREAM_SIZE)
  ) u_fdr_top (
    .clk_i(clk_i),
    .rst_i(rst_i),
    .metacache_mem_if(metacache_mem_if),
    .bitstream_cache_mem_if(bitstream_cache_mem_if),
    .schedule_if(schedule_if_inst),
    .fdr_if(fdr_if_inst),
    .simt_status_i(simt_status_i),
    .bh_branch_predict_info_o(bh_branch_predict_info_o),
    .bh_branch_predict_info_we_o(bh_branch_predict_info_we_o),
    .cta_status_data_i(cta_status_data_i),
    .simt_update_valid_o(simt_update_valid_o),
    .simt_update_ready_i(simt_update_ready_i),
    .simt_update_stack_data_o(simt_update_stack_data_o),
    .cm0_if(cm0_if_inst),
    .cm1_if(cm1_if_inst),
    .eblock_flush_valid_o(eblock_flush_valid_o),
    .eblock_flush_id_o(eblock_flush_id_o)
  );

endmodule
