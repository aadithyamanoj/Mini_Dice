`timescale 1ns / 1ps

module tb_dice_frontend_top;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod      = 10;
  localparam int TimeoutCycles  = 400;
  localparam int TagWidth       = DICE_ADDR_WIDTH;
  localparam int DataSizeBytes  = DICE_MEM_DATA_WIDTH / 8;
  localparam int BusAddrWidth   = DICE_MEM_ADDR_WIDTH - $clog2(DataSizeBytes);
  localparam int NumChunks      = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                                  / DICE_MEM_DATA_WIDTH;
  localparam int AddrShift      = $clog2(DataSizeBytes);

  localparam logic [DICE_ADDR_WIDTH-1:0] StartPc             = 16'h0100;
  localparam logic [DICE_ADDR_WIDTH-1:0] SecondPc            = StartPc + DICE_METADATA_WIDTH;
  localparam logic [DICE_ADDR_WIDTH-1:0] FirstBitstreamAddr  = 16'h0400;
  localparam logic [DICE_ADDR_WIDTH-1:0] SecondBitstreamAddr = 16'h0500;

  logic clk;
  logic rst;
  int cycle_count;

  cta_if cta_if_inst ();

  VX_mem_bus_if #(
      .DATA_SIZE(DataSizeBytes),
      .TAG_WIDTH(TagWidth)
  ) metacache_mem_if ();

  VX_mem_bus_if #(
      .DATA_SIZE(DataSizeBytes),
      .TAG_WIDTH(TagWidth)
  ) bitstream_cache_mem_if ();

  fdr_if     fdr_if_inst ();
  cgra_cm_if cm0_if ();
  cgra_cm_if cm1_if ();

  logic                       eblock_commit_valid_i;
  logic [EBLOCK_ID_WIDTH-1:0] eblock_commit_id_i;
  block_retire_status_t       brt_info_i;
  logic                       brt_info_write_enable_i;

  logic [31:0]                schedule_fire_count;
  logic [31:0]                fdr_fire_count;
  logic [31:0]                simt_update_fire_count;
  logic [31:0]                complete_count;
  logic [DICE_ADDR_WIDTH-1:0] first_schedule_pc;
  logic [DICE_ADDR_WIDTH-1:0] second_schedule_pc;
  logic [DICE_ADDR_WIDTH-1:0] first_simt_update_pc;
  logic [DICE_ADDR_WIDTH-1:0] second_simt_update_pc;
  logic [EBLOCK_ID_WIDTH-1:0] first_fdr_eblock_id;
  logic [EBLOCK_ID_WIDTH-1:0] second_fdr_eblock_id;
  logic [BITSTREAM_LENGTH_WIDTH-1:0] first_fdr_bitstream_length;
  logic [BITSTREAM_LENGTH_WIDTH-1:0] second_fdr_bitstream_length;
  dice_cta_id_t last_complete_cta_id;

  logic          meta_rsp_pending_q;
  logic [TagWidth-1:0] meta_rsp_tag_q;
  pgraph_meta_t  meta_rsp_payload_q;

  logic          bitstream_rsp_pending_q;
  logic [TagWidth-1:0] bitstream_rsp_tag_q;
  logic [DICE_MEM_DATA_WIDTH-1:0] bitstream_rsp_payload_q;

  function automatic pgraph_meta_t metadata_for_pc(
      input logic [DICE_ADDR_WIDTH-1:0] pc
  );
    pgraph_meta_t meta;

    meta = '0;
    meta.bitstream_length = BITSTREAM_LENGTH_WIDTH'(NumChunks);
    meta.lat              = 8'd3;

    unique case (pc)
      StartPc: begin
        meta.bitstream_addr       = FirstBitstreamAddr;
        meta.in_regs_bitmap[0]    = 1'b1;
        meta.out_regs_bitmap[1]   = 1'b1;
      end
      SecondPc: begin
        meta.bitstream_addr       = SecondBitstreamAddr;
        meta.in_regs_bitmap[2]    = 1'b1;
        meta.out_regs_bitmap[3]   = 1'b1;
        meta.branch_meta.is_return = 1'b1;
      end
      default: begin
        meta.bitstream_addr = FirstBitstreamAddr;
      end
    endcase

    return meta;
  endfunction

  function automatic logic [DICE_MEM_DATA_WIDTH-1:0] bitstream_word_for_addr(
      input logic [BusAddrWidth-1:0] word_addr
  );
    logic [DICE_MEM_DATA_WIDTH-1:0] data_word;

    data_word         = '0;
    data_word[31:0]   = {16'hCAFE, word_addr};
    data_word[63:32]  = {16'hD00D, word_addr};
    data_word[95:64]  = {16'hBEEF, word_addr};
    data_word[127:96] = {16'hFACE, word_addr};

    return data_word;
  endfunction

  dice_frontend_top u_dut (
      .clk_i                 (clk),
      .rst_i                 (rst),
      .cta_if_inst           (cta_if_inst),
      .metacache_mem_if      (metacache_mem_if),
      .bitstream_cache_mem_if(bitstream_cache_mem_if),
      .fdr_if_inst           (fdr_if_inst),
      .cm0_if                (cm0_if),
      .cm1_if                (cm1_if),
      .eblock_commit_valid_i (eblock_commit_valid_i),
      .eblock_commit_id_i    (eblock_commit_id_i),
      .brt_info_i            (brt_info_i),
      .brt_info_write_enable_i(brt_info_write_enable_i)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      metacache_mem_if.req_ready <= 1'b1;
      metacache_mem_if.rsp_valid <= 1'b0;
      metacache_mem_if.rsp_data  <= '0;
      meta_rsp_pending_q         <= 1'b0;
      meta_rsp_tag_q             <= '0;
      meta_rsp_payload_q         <= '0;
    end else begin
      metacache_mem_if.req_ready <= 1'b1;
      metacache_mem_if.rsp_valid <= 1'b0;
      metacache_mem_if.rsp_data  <= '0;

      if (meta_rsp_pending_q) begin
        metacache_mem_if.rsp_valid           <= 1'b1;
        metacache_mem_if.rsp_data.tag.uuid   <= meta_rsp_tag_q;
        metacache_mem_if.rsp_data.data[$bits(pgraph_meta_t)-1:0] <= meta_rsp_payload_q;
        meta_rsp_pending_q                   <= 1'b0;
      end

      if (metacache_mem_if.req_valid && metacache_mem_if.req_ready) begin
        logic [DICE_ADDR_WIDTH-1:0] requested_pc;

        requested_pc     = DICE_ADDR_WIDTH'(metacache_mem_if.req_data.addr << AddrShift);
        meta_rsp_pending_q <= 1'b1;
        meta_rsp_tag_q     <= metacache_mem_if.req_data.tag.uuid;
        meta_rsp_payload_q <= metadata_for_pc(requested_pc);
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      bitstream_cache_mem_if.req_ready <= 1'b1;
      bitstream_cache_mem_if.rsp_valid <= 1'b0;
      bitstream_cache_mem_if.rsp_data  <= '0;
      bitstream_rsp_pending_q          <= 1'b0;
      bitstream_rsp_tag_q              <= '0;
      bitstream_rsp_payload_q          <= '0;
    end else begin
      bitstream_cache_mem_if.req_ready <= 1'b1;
      bitstream_cache_mem_if.rsp_valid <= 1'b0;
      bitstream_cache_mem_if.rsp_data  <= '0;

      if (bitstream_rsp_pending_q) begin
        bitstream_cache_mem_if.rsp_valid         <= 1'b1;
        bitstream_cache_mem_if.rsp_data.tag.uuid <= bitstream_rsp_tag_q;
        bitstream_cache_mem_if.rsp_data.data     <= bitstream_rsp_payload_q;
        bitstream_rsp_pending_q                  <= 1'b0;
      end

      if (bitstream_cache_mem_if.req_valid && bitstream_cache_mem_if.req_ready) begin
        bitstream_rsp_pending_q <= 1'b1;
        bitstream_rsp_tag_q     <= bitstream_cache_mem_if.req_data.tag.uuid;
        bitstream_rsp_payload_q <= bitstream_word_for_addr(bitstream_cache_mem_if.req_data.addr);
      end
    end
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      schedule_fire_count        <= 0;
      fdr_fire_count             <= 0;
      simt_update_fire_count     <= 0;
      complete_count             <= 0;
      first_schedule_pc          <= '0;
      second_schedule_pc         <= '0;
      first_simt_update_pc       <= '0;
      second_simt_update_pc      <= '0;
      first_fdr_eblock_id        <= '0;
      second_fdr_eblock_id       <= '0;
      first_fdr_bitstream_length <= '0;
      second_fdr_bitstream_length <= '0;
      last_complete_cta_id       <= '0;
    end else begin
      if (u_dut.schedule_if_inst.valid && u_dut.schedule_if_inst.ready) begin
        if (schedule_fire_count == 0) begin
          first_schedule_pc <= u_dut.schedule_if_inst.data.schedule_next_pc;
        end else if (schedule_fire_count == 1) begin
          second_schedule_pc <= u_dut.schedule_if_inst.data.schedule_next_pc;
        end
        schedule_fire_count <= schedule_fire_count + 1;
        $display("[%0t] schedule fire pc=0x%0h eblock=%0d prefetch=%0b",
                 $time,
                 u_dut.schedule_if_inst.data.schedule_next_pc,
                 u_dut.schedule_if_inst.data.schedule_eblock_id,
                 u_dut.schedule_if_inst.data.schedule_prefetch_block);
      end

      if (u_dut.simt_update_valid && u_dut.simt_update_ready) begin
        if (simt_update_fire_count == 0) begin
          first_simt_update_pc <= u_dut.simt_update_stack_data.update_next_pc;
        end else if (simt_update_fire_count == 1) begin
          second_simt_update_pc <= u_dut.simt_update_stack_data.update_next_pc;
        end
        simt_update_fire_count <= simt_update_fire_count + 1;
        $display("[%0t] simt update next_pc=0x%0h",
                 $time, u_dut.simt_update_stack_data.update_next_pc);
      end

      if (fdr_if_inst.valid && fdr_if_inst.ready) begin
        if (fdr_fire_count == 0) begin
          first_fdr_eblock_id         <= fdr_if_inst.data.schedule_eblock_id;
          first_fdr_bitstream_length  <= fdr_if_inst.data.metadata.bitstream_length;
        end else if (fdr_fire_count == 1) begin
          second_fdr_eblock_id        <= fdr_if_inst.data.schedule_eblock_id;
          second_fdr_bitstream_length <= fdr_if_inst.data.metadata.bitstream_length;
        end
        fdr_fire_count <= fdr_fire_count + 1;
        $display("[%0t] fdr fire eblock=%0d length=%0d buffer=%0b",
                 $time,
                 fdr_if_inst.data.schedule_eblock_id,
                 fdr_if_inst.data.metadata.bitstream_length,
                 fdr_if_inst.data.loaded_buffer);
      end

      if (|cm0_if.chunk_en) begin
        $display("[%0t] cm0 load chunk_en=%b", $time, cm0_if.chunk_en);
      end

      if (|cm1_if.chunk_en) begin
        $display("[%0t] cm1 load chunk_en=%b", $time, cm1_if.chunk_en);
      end

      if (cta_if_inst.complete_valid && cta_if_inst.complete_ready) begin
        last_complete_cta_id <= cta_if_inst.complete_cta_id;
        complete_count       <= complete_count + 1;
        $display("[%0t] cta complete id=(%0d,%0d,%0d)",
                 $time,
                 cta_if_inst.complete_cta_id.x,
                 cta_if_inst.complete_cta_id.y,
                 cta_if_inst.complete_cta_id.z);
      end
    end
  end

  task automatic init_inputs();
    cta_if_inst.dispatch_valid = 1'b0;
    cta_if_inst.dispatch_data  = '0;
    cta_if_inst.complete_ready = 1'b1;

    fdr_if_inst.ready          = 1'b1;

    eblock_commit_valid_i      = 1'b0;
    eblock_commit_id_i         = '0;
    brt_info_i                 = '0;
    brt_info_write_enable_i    = 1'b0;
  endtask

  task automatic reset_dut();
    rst = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask

  task automatic dispatch_cta(input dice_cta_desc_t desc);
    wait (cta_if_inst.dispatch_ready == 1'b1);
    cta_if_inst.dispatch_data  = desc;
    cta_if_inst.dispatch_valid = 1'b1;
    @(posedge clk);
    cta_if_inst.dispatch_valid = 1'b0;
  endtask

  task automatic commit_eblock(input logic [EBLOCK_ID_WIDTH-1:0] eblock_id);
    eblock_commit_id_i    = eblock_id;
    eblock_commit_valid_i = 1'b1;
    @(posedge clk);
    eblock_commit_valid_i = 1'b0;
    eblock_commit_id_i    = '0;
  endtask

  initial begin
    dice_cta_desc_t desc;

    $display("tb_dice_frontend_top");

    init_inputs();
    reset_dut();

    desc = '0;
    desc.kernel_desc.grid_size.x = 1;
    desc.kernel_desc.grid_size.y = 1;
    desc.kernel_desc.grid_size.z = 1;
    desc.kernel_desc.cta_size.x  = 1;
    desc.kernel_desc.cta_size.y  = 1;
    desc.kernel_desc.cta_size.z  = 1;
    desc.kernel_desc.start_pc    = StartPc;
    desc.cta_id.x                = '0;
    desc.cta_id.y                = '0;
    desc.cta_id.z                = '0;

    dispatch_cta(desc);

    wait (schedule_fire_count >= 1);
    wait (fdr_fire_count >= 1);
    commit_eblock(first_fdr_eblock_id);

    wait (schedule_fire_count >= 2);
    wait (simt_update_fire_count >= 2);
    wait (fdr_fire_count >= 2);
    commit_eblock(second_fdr_eblock_id);

    wait (complete_count >= 1);

    assert (first_schedule_pc == StartPc)
      else $fatal(1, "first schedule PC mismatch");
    assert (second_schedule_pc == SecondPc)
      else $fatal(1, "second schedule PC mismatch");
    assert (first_simt_update_pc == SecondPc)
      else $fatal(1, "first SIMT update PC mismatch");
    assert (second_simt_update_pc == (SecondPc + DICE_METADATA_WIDTH))
      else $fatal(1, "second SIMT update PC mismatch");
    assert (first_fdr_bitstream_length == BITSTREAM_LENGTH_WIDTH'(NumChunks))
      else $fatal(1, "first FDR length mismatch");
    assert (second_fdr_bitstream_length == BITSTREAM_LENGTH_WIDTH'(NumChunks))
      else $fatal(1, "second FDR length mismatch");
    assert (last_complete_cta_id == desc.cta_id)
      else $fatal(1, "completed CTA ID mismatch");

    $display("PASS: frontend top integration path is alive");
`ifdef MODELSIM
    $stop;
`else
    $finish;
`endif
  end

`ifdef VCD
  initial begin
    $dumpfile("tb_dice_frontend_top.vcd");
    $dumpvars(0, tb_dice_frontend_top);
  end
`endif

endmodule
