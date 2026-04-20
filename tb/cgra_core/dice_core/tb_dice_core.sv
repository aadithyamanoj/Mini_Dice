`timescale 1ns / 1ps

import "DPI-C" context function void dice_core_tb_init(
  input string cta_desc_mem_file,
  input string meta_mem_file,
  input string bitstream_mem_file,
  input string runtime_json_file
);
import "DPI-C" context function int unsigned dice_core_tb_has_init_error();
import "DPI-C" context function string dice_core_tb_get_init_error();
import "DPI-C" context function int unsigned dice_core_tb_get_cta_desc_word(
  input int unsigned word_idx
);
import "DPI-C" context function int unsigned dice_core_tb_get_csr(input int unsigned csr_idx);
import "DPI-C" context function int unsigned dice_core_tb_meta_read16(input int unsigned byte_addr);
import "DPI-C" context function int unsigned dice_core_tb_bitstream_read16(
  input int unsigned byte_addr
);
import "DPI-C" context function int unsigned dice_core_tb_axi_read16(input int unsigned addr);
import "DPI-C" context function void dice_core_tb_record_axi_write(
  input int unsigned addr,
  input int unsigned data,
  input int unsigned strb
);
import "DPI-C" context function int unsigned dice_core_tb_check_done();

`include "dice_define.vh"

module tb_dice_core;
  import dice_pkg::*;
  import dice_frontend_pkg::*;
  import DE_pkg::*;
  import axi4_xbar_pkg::*;


  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, tb_dice_core, "+struct", "+mda");
  end


  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 50000;
  localparam int AxiRespDelayCycles = 10;
  localparam int AxiRespDelayCtrWidth = $clog2(AxiRespDelayCycles + 1);
  localparam int MetaBeatBytes = AxiDataWidth / 8;
  localparam int CTA_DESC_BITS = $bits(dice_cta_desc_t);
  localparam int CTA_DESC_WORDS = (CTA_DESC_BITS + 31) / 32;
  localparam string DefaultTestVector = "full_mul_array_test_vector";
  localparam string DefaultTestVectorDir = "tb/test_vectors";

  logic clk_i;
  logic rst_i;
  int cycle_count;

  string test_vector_name;
  string test_vector_stem;
  string test_vector_dir;
  string cta_desc_mem_file;
  string meta_mem_file;
  string bitstream_mem_file;
  string runtime_json_file;

  cta_if cta_if_inst ();

  slv_req_t                                        mfetch_req_o;
  slv_resp_t                                       mfetch_resp_i;
  slv_req_t                                        bsfetch_req_o;
  slv_resp_t                                       bsfetch_resp_i;

  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX0_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX1_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX2_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX3_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX4_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX5_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX6_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] csrX7_i;

  logic                                            cgra_prog_dout_o;
  logic                                            cgra_prog_we_o;

  logic           [       DICE_REG_DATA_WIDTH-1:0] axi_awaddr_o;
  logic                                            axi_awvalid_o;
  logic                                            axi_awready_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] axi_wdata_o;
  logic           [                           1:0] axi_wstrb_o;
  logic                                            axi_wvalid_o;
  logic                                            axi_wready_i;
  logic           [                           1:0] axi_bresp_i;
  logic                                            axi_bvalid_i;
  logic                                            axi_bready_o;
  logic           [       DICE_REG_DATA_WIDTH-1:0] axi_araddr_o;
  logic                                            axi_arvalid_o;
  logic                                            axi_arready_i;
  logic           [       DICE_REG_DATA_WIDTH-1:0] axi_rdata_i;
  logic           [                           1:0] axi_rresp_i;
  logic                                            axi_rvalid_i;
  logic                                            axi_rready_o;

  logic                                            mfetch_active_q;
  logic           [           DICE_ADDR_WIDTH-1:0] mfetch_addr_q;
  logic           [                           7:0] mfetch_len_q;
  logic           [                           7:0] mfetch_beat_idx_q;
  logic           [ $bits(mfetch_req_o.ar.id)-1:0] mfetch_id_q;

  logic                                            bsfetch_active_q;
  logic           [           DICE_ADDR_WIDTH-1:0] bsfetch_addr_q;
  logic           [                           7:0] bsfetch_len_q;
  logic           [                           7:0] bsfetch_beat_idx_q;
  logic           [$bits(bsfetch_req_o.ar.id)-1:0] bsfetch_id_q;

  logic                                            aw_seen_q;
  logic           [       DICE_REG_DATA_WIDTH-1:0] awaddr_q;
  logic                                            w_seen_q;
  logic           [       DICE_REG_DATA_WIDTH-1:0] wdata_q;
  logic           [                           1:0] wstrb_q;
  logic                                            write_resp_pending_q;
  logic           [     AxiRespDelayCtrWidth-1:0] write_resp_delay_q;
  logic                                            read_resp_pending_q;
  logic           [     AxiRespDelayCtrWidth-1:0] read_resp_delay_q;
  logic           [       DICE_REG_DATA_WIDTH-1:0] read_data_q;

  dice_cta_desc_t                                  launch_desc;

  dice_core u_dut (
      .clk_i(clk_i),
      .rst_i(rst_i),
      .cta_if_inst(cta_if_inst),
      .mfetch_req_o(mfetch_req_o),
      .mfetch_resp_i(mfetch_resp_i),
      .bsfetch_req_o(bsfetch_req_o),
      .bsfetch_resp_i(bsfetch_resp_i),
      .csrX0_i(csrX0_i),
      .csrX1_i(csrX1_i),
      .csrX2_i(csrX2_i),
      .csrX3_i(csrX3_i),
      .csrX4_i(csrX4_i),
      .csrX5_i(csrX5_i),
      .csrX6_i(csrX6_i),
      .csrX7_i(csrX7_i),
      .cgra_prog_dout_o(cgra_prog_dout_o),
      .cgra_prog_we_o(cgra_prog_we_o),
      .axi_awaddr_o(axi_awaddr_o),
      .axi_awvalid_o(axi_awvalid_o),
      .axi_awready_i(axi_awready_i),
      .axi_wdata_o(axi_wdata_o),
      .axi_wstrb_o(axi_wstrb_o),
      .axi_wvalid_o(axi_wvalid_o),
      .axi_wready_i(axi_wready_i),
      .axi_bresp_i(axi_bresp_i),
      .axi_bvalid_i(axi_bvalid_i),
      .axi_bready_o(axi_bready_o),
      .axi_araddr_o(axi_araddr_o),
      .axi_arvalid_o(axi_arvalid_o),
      .axi_arready_i(axi_arready_i),
      .axi_rdata_i(axi_rdata_i),
      .axi_rresp_i(axi_rresp_i),
      .axi_rvalid_i(axi_rvalid_i),
      .axi_rready_o(axi_rready_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #(ClkPeriod / 2) clk_i = ~clk_i;
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
        $fatal(1, "TIMEOUT after %0d cycles", TimeoutCycles);
      end
    end
  end

  function automatic bit has_path_component(input string path);
    if (path.len() == 0) begin
      return 1'b0;
    end

    if (path.getc(0) == "/") begin
      return 1'b1;
    end

    for (int idx = 0; idx < path.len(); idx++) begin
      if (path.getc(idx) == "/") begin
        return 1'b1;
      end
    end

    return 1'b0;
  endfunction

  task automatic init_paths();
    begin
      if (!$value$plusargs("TEST_VECTOR=%s", test_vector_name)) begin
        test_vector_name = DefaultTestVector;
      end
      if (has_path_component(test_vector_name)) begin
        test_vector_stem = test_vector_name;
      end else begin
        if (!$value$plusargs("TEST_VECTOR_DIR=%s", test_vector_dir)) begin
          test_vector_dir = DefaultTestVectorDir;
        end
        test_vector_stem = {test_vector_dir, "/", test_vector_name};
      end
      cta_desc_mem_file  = {test_vector_stem, "_cta_desc.mem"};
      meta_mem_file      = {test_vector_stem, "_meta.mem"};
      bitstream_mem_file = {test_vector_stem, "_bitstream.mem"};
      runtime_json_file  = {test_vector_stem, "_runtime.json"};
    end
  endtask

  task automatic init_collateral();
    logic [CTA_DESC_WORDS*32-1:0] packed_desc;
    begin
      packed_desc = '0;
      dice_core_tb_init(cta_desc_mem_file, meta_mem_file, bitstream_mem_file, runtime_json_file);
      if (dice_core_tb_has_init_error()) begin
        $fatal(1, "[TB] DPI init failed: %s", dice_core_tb_get_init_error());
      end

      for (int word_idx = 0; word_idx < CTA_DESC_WORDS; word_idx++) begin
        packed_desc[word_idx*32+:32] = dice_core_tb_get_cta_desc_word(word_idx);
      end
      launch_desc = dice_cta_desc_t'(packed_desc[CTA_DESC_BITS-1:0]);

      csrX0_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(0));
      csrX1_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(1));
      csrX2_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(2));
      csrX3_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(3));
      csrX4_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(4));
      csrX5_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(5));
      csrX6_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(6));
      csrX7_i = DICE_REG_DATA_WIDTH'(dice_core_tb_get_csr(7));

      $display("[TB] Using test vector stem: %s", test_vector_stem);
      $display("[TB] CTA start_pc=%0d grid=(%0d,%0d,%0d) thread_count=%0d cta_id=(%0d,%0d,%0d)",
               launch_desc.kernel_desc.start_pc, launch_desc.kernel_desc.grid_size.x,
               launch_desc.kernel_desc.grid_size.y, launch_desc.kernel_desc.grid_size.z,
               launch_desc.kernel_desc.thread_count, launch_desc.cta_id.x, launch_desc.cta_id.y,
               launch_desc.cta_id.z);
    end
  endtask

  task automatic reset_dut();
    begin
      rst_i = 1'b1;

      cta_if_inst.dispatch_valid = 1'b0;
      cta_if_inst.dispatch_data = '0;
      cta_if_inst.complete_ready = 1'b1;

      csrX0_i = '0;
      csrX1_i = '0;
      csrX2_i = '0;
      csrX3_i = '0;
      csrX4_i = '0;
      csrX5_i = '0;
      csrX6_i = '0;
      csrX7_i = '0;

      repeat (10) @(posedge clk_i);
      rst_i = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic dispatch_cta(input dice_cta_desc_t desc);
    begin
      cta_if_inst.dispatch_valid = 1'b1;
      cta_if_inst.dispatch_data  = desc;
      do begin
        @(posedge clk_i);
      end while (!cta_if_inst.dispatch_ready);
      cta_if_inst.dispatch_valid = 1'b0;
    end
  endtask

  always_comb begin
    mfetch_resp_i = '0;
    mfetch_resp_i.ar_ready = !mfetch_active_q;
    if (mfetch_active_q) begin
      mfetch_resp_i.r_valid = 1'b1;
      mfetch_resp_i.r.id = mfetch_id_q;
      mfetch_resp_i.r.data = AxiDataWidth'(
          dice_core_tb_meta_read16(int'(mfetch_addr_q) + int'(mfetch_beat_idx_q) * MetaBeatBytes));
      mfetch_resp_i.r.last = (mfetch_beat_idx_q == mfetch_len_q);
    end
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      mfetch_active_q <= 1'b0;
      mfetch_addr_q <= '0;
      mfetch_len_q <= '0;
      mfetch_beat_idx_q <= '0;
      mfetch_id_q <= '0;
    end else begin
      if (mfetch_req_o.ar_valid && mfetch_resp_i.ar_ready) begin
        mfetch_active_q <= 1'b1;
        mfetch_addr_q <= DICE_ADDR_WIDTH'(mfetch_req_o.ar.addr);
        mfetch_len_q <= mfetch_req_o.ar.len;
        mfetch_beat_idx_q <= '0;
        mfetch_id_q <= mfetch_req_o.ar.id;
      end else if (mfetch_resp_i.r_valid && mfetch_req_o.r_ready) begin
        if (mfetch_resp_i.r.last) begin
          mfetch_active_q <= 1'b0;
        end else begin
          mfetch_beat_idx_q <= mfetch_beat_idx_q + 1'b1;
        end
      end
    end
  end

  always_comb begin
    bsfetch_resp_i = '0;
    bsfetch_resp_i.ar_ready = !bsfetch_active_q;
    if (bsfetch_active_q) begin
      bsfetch_resp_i.r_valid = 1'b1;
      bsfetch_resp_i.r.id = bsfetch_id_q;
      bsfetch_resp_i.r.data =
          AxiDataWidth'(dice_core_tb_bitstream_read16(
                        int'(bsfetch_addr_q) + int'(bsfetch_beat_idx_q) * MetaBeatBytes));
      bsfetch_resp_i.r.last = (bsfetch_beat_idx_q == bsfetch_len_q);
    end
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      bsfetch_active_q <= 1'b0;
      bsfetch_addr_q <= '0;
      bsfetch_len_q <= '0;
      bsfetch_beat_idx_q <= '0;
      bsfetch_id_q <= '0;
    end else begin
      if (bsfetch_req_o.ar_valid && bsfetch_resp_i.ar_ready) begin
        bsfetch_active_q <= 1'b1;
        bsfetch_addr_q <= DICE_ADDR_WIDTH'(bsfetch_req_o.ar.addr);
        bsfetch_len_q <= bsfetch_req_o.ar.len;
        bsfetch_beat_idx_q <= '0;
        bsfetch_id_q <= bsfetch_req_o.ar.id;
      end else if (bsfetch_resp_i.r_valid && bsfetch_req_o.r_ready) begin
        if (bsfetch_resp_i.r.last) begin
          bsfetch_active_q <= 1'b0;
        end else begin
          bsfetch_beat_idx_q <= bsfetch_beat_idx_q + 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      aw_seen_q <= 1'b0;
      awaddr_q <= '0;
      w_seen_q <= 1'b0;
      wdata_q <= '0;
      wstrb_q <= '0;
      write_resp_pending_q <= 1'b0;
      write_resp_delay_q <= '0;
      read_resp_pending_q <= 1'b0;
      read_resp_delay_q <= '0;
      read_data_q <= '0;
      axi_awready_i <= 1'b0;
      axi_wready_i <= 1'b0;
      axi_bvalid_i <= 1'b0;
      axi_bresp_i <= 2'b00;
      axi_arready_i <= 1'b0;
      axi_rvalid_i <= 1'b0;
      axi_rdata_i <= '0;
      axi_rresp_i <= 2'b00;
    end else begin
      axi_awready_i <= !(write_resp_pending_q || axi_bvalid_i || aw_seen_q);
      axi_wready_i  <= !(write_resp_pending_q || axi_bvalid_i || w_seen_q);
      axi_arready_i <= !(read_resp_pending_q || axi_rvalid_i);

      if (axi_awvalid_o && axi_awready_i) begin
        aw_seen_q <= 1'b1;
        awaddr_q  <= axi_awaddr_o;
      end

      if (axi_wvalid_o && axi_wready_i) begin
        w_seen_q <= 1'b1;
        wdata_q  <= axi_wdata_o;
        wstrb_q  <= axi_wstrb_o;
      end

      if (!write_resp_pending_q
          && !axi_bvalid_i
          && (aw_seen_q || (axi_awvalid_o && axi_awready_i))
          && (w_seen_q || (axi_wvalid_o && axi_wready_i))) begin
        aw_seen_q <= 1'b0;
        w_seen_q <= 1'b0;
        write_resp_pending_q <= 1'b1;
        write_resp_delay_q <= AxiRespDelayCtrWidth'(AxiRespDelayCycles);
      end else if (write_resp_pending_q) begin
        if (write_resp_delay_q == AxiRespDelayCtrWidth'(1)) begin
          dice_core_tb_record_axi_write(int'(awaddr_q), int'(wdata_q), int'(wstrb_q));
          axi_bvalid_i <= 1'b1;
          write_resp_pending_q <= 1'b0;
          write_resp_delay_q <= '0;
        end else begin
          write_resp_delay_q <= write_resp_delay_q - 1'b1;
        end
      end else if (axi_bvalid_i && axi_bready_o) begin
        axi_bvalid_i <= 1'b0;
      end

      if (!read_resp_pending_q && !axi_rvalid_i && axi_arvalid_o && axi_arready_i) begin
        read_resp_pending_q <= 1'b1;
        read_resp_delay_q <= AxiRespDelayCtrWidth'(AxiRespDelayCycles);
        read_data_q <= DICE_REG_DATA_WIDTH'(dice_core_tb_axi_read16(int'(axi_araddr_o)));
      end else if (read_resp_pending_q) begin
        if (read_resp_delay_q == AxiRespDelayCtrWidth'(1)) begin
          axi_rvalid_i <= 1'b1;
          axi_rdata_i  <= read_data_q;
          read_resp_pending_q <= 1'b0;
          read_resp_delay_q <= '0;
        end else begin
          read_resp_delay_q <= read_resp_delay_q - 1'b1;
        end
      end else if (axi_rvalid_i && axi_rready_o) begin
        axi_rvalid_i <= 1'b0;
      end
    end
  end

  initial begin
    int unsigned check_ok;

    $display("tb_dice_core");

    init_paths();
    reset_dut();
    init_collateral();

    repeat (10) @(posedge clk_i);
    dispatch_cta(launch_desc);

    wait (cta_if_inst.complete_valid === 1'b1);
    $display("[TB] CTA complete observed at cycle %0d", cycle_count);
    repeat (5) @(posedge clk_i);

    check_ok = dice_core_tb_check_done();
    if (check_ok != 0) begin
      $display("PASS: dice_core completed and DPI checks passed");
      $finish;
    end

    $display("FAIL: dice_core runtime checks reported an error (see AXI WRITE VERIFICATION DIFF above)");
    $fatal(1, "FAIL: AXI write mismatch - see diff above");
  end


endmodule
