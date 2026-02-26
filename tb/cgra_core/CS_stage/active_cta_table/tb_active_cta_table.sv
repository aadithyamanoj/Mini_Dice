
// `timescale 1ns / 1ps
`include "dice_define.vh"

module tb_active_cta_table;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  localparam int ClkPeriod = 10;
  localparam int TimeoutCycles = 40;

  logic clk;
  logic rst;

  logic                            add_ready_o;
  logic                            add_valid_i;
  dice_cta_desc_t                  add_cta_info_i;
  cta_size_e                       add_hw_cta_size_i;
  logic [DICE_TID_WIDTH:0]         add_cta_thread_count_i;

  logic                            pop_valid_i;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] pop_hw_cta_id_i;
  logic                            pop_ready_o;

  logic                            out_valid_o;
  logic                            out_ready_i;
  dice_cta_id_t                    out_cta_id_o;
  logic [DICE_TID_WIDTH-1:0]       out_cta_size_o;
  logic [DICE_KERNEL_ID_WIDTH-1:0] out_kernel_id_o;
  logic [DICE_TID_WIDTH:0]         out_cta_thread_count_o;

  active_cta_t [DICE_NUM_MAX_CTA_PER_CORE-1:0] active_cta_entries_o;

  logic                            full_o;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] next_empty_cta_index_o;

  int cycle_count;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      cycle_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) $fatal(1, "TIMEOUT");
    end
  end

  active_cta_table u_dut (
      .clk_i                 (clk),
      .rst_i                 (rst),
      .add_ready_o           (add_ready_o),
      .add_valid_i           (add_valid_i),
      .add_cta_info_i        (add_cta_info_i),
      .add_hw_cta_size_i     (add_hw_cta_size_i),
      .add_cta_thread_count_i(add_cta_thread_count_i),
      .pop_valid_i           (pop_valid_i),
      .pop_hw_cta_id_i       (pop_hw_cta_id_i),
      .pop_ready_o           (pop_ready_o),
      .out_valid_o           (out_valid_o),
      .out_ready_i           (out_ready_i),
      .out_cta_id_o          (out_cta_id_o),
      .out_cta_size_o        (out_cta_size_o),
      .out_kernel_id_o       (out_kernel_id_o),
      .out_cta_thread_count_o(out_cta_thread_count_o),
      .active_cta_entries_o  (active_cta_entries_o),
      .full_o                (full_o),
      .next_empty_cta_index_o(next_empty_cta_index_o)
  );

  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end


  // Tasks

  task automatic idle_inputs();
    add_valid_i            = 1'b0;
    add_cta_info_i         = '0;
    add_hw_cta_size_i      = CTA_SIZE_1;
    add_cta_thread_count_i = '0;

    pop_valid_i            = 1'b0;
    pop_hw_cta_id_i        = '0;

    out_ready_i            = 1'b1;
  endtask



  task automatic reset_dut();
    rst = 1'b1;
    idle_inputs();
    repeat (5) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
  endtask


  function automatic dice_cta_desc_t build_min_desc();
    dice_cta_desc_t d;
    d = '0;

    d.cta_id.x = 5;
    d.cta_id.y = 13;
    d.cta_id.z = 12;

    d.kernel_desc.cta_size.x  = 1;
    d.kernel_desc.cta_size.y  = 1;
    d.kernel_desc.cta_size.z  = 1;

    d.kernel_desc.grid_size.x = 1;
    d.kernel_desc.grid_size.y = 1;
    d.kernel_desc.grid_size.z = 1;

    d.kernel_desc.kernel_id = 15;

    return d;
  endfunction


  task automatic add_cta_handshake(
    input dice_cta_desc_t desc,
    input cta_size_e      hw_cta_size,
    input int unsigned    thread_count
  );
    add_cta_info_i         = desc;
    add_hw_cta_size_i      = hw_cta_size;
    add_cta_thread_count_i = thread_count;

    add_valid_i = 1'b1;

    do begin
      @(posedge clk);
    end while (!add_ready_o);
    repeat (10) @(posedge clk);
    add_valid_i = 1'b0;
  endtask

  task automatic pop_cta_handshake(
    input logic [DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_id
  );
    pop_hw_cta_id_i = hw_cta_id;
    pop_valid_i     = 1'b1;

    do begin
      @(posedge clk);
    end while (!pop_ready_o);

    pop_valid_i = 1'b0;
  endtask

  // Stimulus
  initial begin
    dice_cta_desc_t desc;
    dice_cta_id_t   exp_id;

    $display("Start active cta table testbench");

    idle_inputs();
    reset_dut();
    repeat (5) @(posedge clk);

    // Build a minimal CTA descriptor
    desc   = build_min_desc();
    exp_id = desc.cta_id;

    // Add one CTA (holds valid until ready)
    add_cta_handshake(desc, CTA_SIZE_2, 1);
    $display("added first");

    add_cta_handshake(desc, CTA_SIZE_1, 1);
    $display("added second");

    add_cta_handshake(desc, CTA_SIZE_1, 1);
    add_cta_handshake(desc, CTA_SIZE_1, 1);

    repeat (10) @(posedge clk); // consume output beat

    $display("PASS");
    $finish;

  end




`ifdef FSDB
  initial begin
    $fsdbDumpfile("tb_active_cta_table.fsdb");
    $fsdbDumpvars(0, "+struct");
  end
`endif


endmodule
