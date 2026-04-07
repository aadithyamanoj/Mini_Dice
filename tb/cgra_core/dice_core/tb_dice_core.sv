// `timescale 1ns/1ps
`include "dice_define.vh"

module tb_dice_core;
  import dice_pkg::*;
  import dice_frontend_pkg::*;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam int TimeoutCycles = 1000;
  localparam int ClkPeriod     = 10;

  // Test vector configuration
  localparam string TEST_VECTOR_FILE      = "kernel_simple";
  localparam int    METACACHE_DATA_SIZE   = 256;
  localparam int    BITSTREAM_DATA_SIZE   = DICE_MEM_DATA_WIDTH / 8;

  // =========================================================================
  // Signals
  // =========================================================================
  logic clk;
  logic reset;


  // =========================================================================
  // Interfaces
  // =========================================================================
  cta_if cta_if_inst();

  dice_mem_bus_if #(
      .DATA_SIZE(METACACHE_DATA_SIZE),
      .TAG_WIDTH(DICE_ADDR_WIDTH)
  ) metacache_mem_if [1] ();

  dice_mem_bus_if #(
      .DATA_SIZE(BITSTREAM_DATA_SIZE),
      .TAG_WIDTH(DICE_ADDR_WIDTH)
  ) bitstream_cache_mem_if [1] ();



  // =========================================================================
  // Memory Instantiation
  // =========================================================================
  dice_local_mem #(
    .SIZE      (1 << 26),
    .WORD_SIZE (METACACHE_DATA_SIZE),
    .TAG_WIDTH (DICE_ADDR_WIDTH)
  ) u_meta_mem (
      .clk        (clk),
      .reset      (reset),
      .mem_bus_if (metacache_mem_if)
  );

  dice_local_mem #(
    .SIZE      (1 << 26),
    .WORD_SIZE (BITSTREAM_DATA_SIZE),
    .TAG_WIDTH (DICE_ADDR_WIDTH)
  ) u_bitstream_mem (
      .clk        (clk),
      .reset      (reset),
      .mem_bus_if (bitstream_cache_mem_if)
  );


  // =========================================================================
  // Timeout Counter
  // =========================================================================
  int cycle_count;
  always_ff @(posedge clk or posedge reset) begin
    if (reset) cycle_count <= 0;
    else begin
      cycle_count <= cycle_count + 1;
      if (cycle_count >= TimeoutCycles) begin
         $error("TIMEOUT");
         $finish;
      end
    end
  end

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  dice_core u_dut (
      .clk_i                   (clk),
      .rst_i                   (reset),
      .cta_if_inst             (cta_if_inst),
      .metacache_mem_if        (metacache_mem_if[0]),
      .bitstream_cache_mem_if  (bitstream_cache_mem_if[0])
  );
  // =========================================================================
  // Clock Generation
  // =========================================================================
  initial begin
    clk = 1'b0;
    forever #(ClkPeriod / 2) clk = ~clk;
  end

  // =========================================================================
  // Helper Tasks
  // =========================================================================

  //Initializes inputs to the DUT
  task automatic init_inputs();
    cta_if_inst.dispatch_valid = 1'b0;
    cta_if_inst.dispatch_data  = '0;
    cta_if_inst.complete_ready = 1'b1;
  endtask

  //Resets the DUT
  task automatic reset_dut();
    reset = 1'b1;
    repeat (10) @(posedge clk);
    reset = 1'b0;
  endtask

  //Dispatches CTA into the core with specified description
  task automatic dispatch_cta(input dice_cta_desc_t desc);
    cta_if_inst.dispatch_valid = 1'b1;
    cta_if_inst.dispatch_data  = desc;

    do begin
      @(posedge clk);
    end while (!cta_if_inst.dispatch_ready);

    cta_if_inst.dispatch_valid = 1'b0;
  endtask

  // Load CTA descriptor from generated .mem file (produced by gen_memfile.py)
  localparam int CTA_DESC_BITS = $bits(dice_cta_desc_t);
  localparam int CTA_DESC_PAD  = ((CTA_DESC_BITS + 3) / 4) * 4; // nibble-aligned

  task automatic load_cta_desc(
    input  string          mem_file,
    output dice_cta_desc_t desc
  );
    logic [CTA_DESC_PAD-1:0] cta_mem [0:0];
    $display("Loading CTA descriptor from %s", mem_file);
    $readmemh(mem_file, cta_mem);
    desc = dice_cta_desc_t'(cta_mem[0][CTA_DESC_BITS-1:0]);
    $display("  kernel_id=%0d, grid=(%0d,%0d,%0d), cta_size=(%0d,%0d,%0d), cta_id=(%0d,%0d,%0d)",
             desc.kernel_desc.kernel_id,
             desc.kernel_desc.grid_size.x, desc.kernel_desc.grid_size.y, desc.kernel_desc.grid_size.z,
             desc.kernel_desc.cta_size.x,  desc.kernel_desc.cta_size.y,  desc.kernel_desc.cta_size.z,
             desc.cta_id.x, desc.cta_id.y, desc.cta_id.z);
  endtask


  // Load metadata .mem file into the local memory model via $readmemh backdoor
  task automatic load_metadata(string mem_file);
    $display("Loading metadata from %s", mem_file);
    $readmemh(mem_file, u_meta_mem.ram);
  endtask

  // Load bitstream .mem file into the local memory model via $readmemh backdoor
  task automatic load_bitstream(string mem_file);
    $display("Loading bitstream from %s", mem_file);
    $readmemh(mem_file, u_bitstream_mem.ram);
  endtask

  // Load all .mem files from a test vector and dispatch CTA
  // NOTE: .mem files must be pre-generated by `make gen` before running sim
  task automatic dispatch_cta_with_metadata(
    input string json_basename  // e.g., "kernel_simple"
  );
    dice_cta_desc_t desc;

    // 1) Load generated metadata into memory backdoor
    load_metadata($sformatf("%s_meta.mem", json_basename));

    // 2) Load generated bitstream data into memory backdoor
    load_bitstream($sformatf("%s_bitstream.mem", json_basename));

    // 3) Load CTA descriptor from generated .mem file
    load_cta_desc($sformatf("%s_cta_desc.mem", json_basename), desc);

    // 4) Dispatch the CTA
    $display("[dispatch_cta_with_metadata] Dispatching CTA for %s", json_basename);
    dispatch_cta(desc);
  endtask


  // =========================================================================
  // Stimulus
  // =========================================================================
  initial begin
    $display("dice_core testbench");

    init_inputs();
    reset_dut();

    repeat (10) @(posedge clk);

    // Load metadata, bitstream, CTA descriptor from test vector and dispatch
    dispatch_cta_with_metadata(TEST_VECTOR_FILE);

    repeat (100) @(posedge clk);

    $display("TB Done");
    $finish;
  end

`ifdef FSDB
  initial begin
    $fsdbDumpfile("tb_dice_core.fsdb");
    $fsdbDumpvars(0, tb_dice_core, "+struct", "+mda"); //include structs and multi-dimensional arrays
  end
`endif

endmodule
