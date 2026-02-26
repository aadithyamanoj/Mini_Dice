`timescale 1ns/1ps

module tb_dice_cgra;
  localparam TILE_BITS = 156;
  localparam NUM_TILES = 16;
  localparam NUM_CGRA_IO = 32;
  localparam NUM_CGRA_IO_PER_EDGE = NUM_CGRA_IO / 4;
  localparam NUM_TID = 512;
  localparam DATA_WIDTH = 32;
  localparam MAX_CTA_ID = 65535;
  localparam MAX_CGRA_PIPE_STAGE = 128;
  localparam MAX_IO_PIPE_STAGE = 8;
  localparam CFG_WIDTH = TILE_BITS * NUM_TILES;
  localparam ADDR_WIDTH = $clog2(NUM_TID);
  localparam TID_WIDTH = $clog2(NUM_TID);
  localparam IO_PIPE_SEL_WIDTH = $clog2(MAX_IO_PIPE_STAGE);
  localparam CGRA_PIPE_SEL_WIDTH = $clog2(MAX_CGRA_PIPE_STAGE);
  localparam PRED_RF_CFG_BITS_PER_PORT = 2 + IO_PIPE_SEL_WIDTH*2; // (rd_en, wr_en), (out_lat, in_lat)
  localparam GPRF_CFG_BITS_PER_PORT = 2 + IO_PIPE_SEL_WIDTH*2 + 5 + TID_WIDTH*4; // (rd_en, wr_en), in_lat, out_lat, (spec_rd_en, spec_rd_sel), rd_addr_override, wr_addr_override, rd_addr_override_en, wr_addr_override_en

  logic clk;
  logic rst_n;
  logic clr;
  logic [CFG_WIDTH-1:0] cgra_cfg;

  // Edge I/O signals
  logic [DATA_WIDTH-1:0] N_in_t [0:NUM_CGRA_IO_PER_EDGE-1], N_out_t [0:NUM_CGRA_IO_PER_EDGE-1];
  logic [DATA_WIDTH-1:0] E_in_t [0:NUM_CGRA_IO_PER_EDGE-1], E_out_t [0:NUM_CGRA_IO_PER_EDGE-1];
  logic [DATA_WIDTH-1:0] S_in_t [0:NUM_CGRA_IO_PER_EDGE-1], S_out_t [0:NUM_CGRA_IO_PER_EDGE-1];
  logic [DATA_WIDTH-1:0] W_in_t [0:NUM_CGRA_IO_PER_EDGE-1], W_out_t [0:NUM_CGRA_IO_PER_EDGE-1];

  logic N_in_p [0:NUM_CGRA_IO_PER_EDGE-1], N_out_p [0:NUM_CGRA_IO_PER_EDGE-1];
  logic E_in_p [0:NUM_CGRA_IO_PER_EDGE-1], E_out_p [0:NUM_CGRA_IO_PER_EDGE-1];
  logic S_in_p [0:NUM_CGRA_IO_PER_EDGE-1], S_out_p [0:NUM_CGRA_IO_PER_EDGE-1];
  logic W_in_p [0:NUM_CGRA_IO_PER_EDGE-1], W_out_p [0:NUM_CGRA_IO_PER_EDGE-1];


  logic [TID_WIDTH-1:0] dispatch_tid;
  logic disp_tid_valid;
  logic disp_enable;
  logic disp_clr;
  logic disp_done;
  logic cgra_done;

  logic [NUM_CGRA_IO*ADDR_WIDTH-1:0] rd_override_enable;
  logic [NUM_CGRA_IO*ADDR_WIDTH-1:0] rd_override_address;
  logic [NUM_CGRA_IO-1:0] rf_rd_en;
  logic [NUM_CGRA_IO-1:0] prf_rd_en;
  logic [NUM_CGRA_IO*ADDR_WIDTH-1:0] wr_override_enable;
  logic [NUM_CGRA_IO*ADDR_WIDTH-1:0] wr_override_address;
  logic [NUM_CGRA_IO-1:0] rf_wr_en;
  logic [NUM_CGRA_IO-1:0] prf_wr_en;
  logic [NUM_CGRA_IO*IO_PIPE_SEL_WIDTH-1:0] rf_latency_in;
  logic [NUM_CGRA_IO*IO_PIPE_SEL_WIDTH-1:0] rf_latency_out;
  logic [NUM_CGRA_IO*IO_PIPE_SEL_WIDTH-1:0] prf_latency_in;
  logic [NUM_CGRA_IO*IO_PIPE_SEL_WIDTH-1:0] prf_latency_out;
  logic [CGRA_PIPE_SEL_WIDTH-1:0] cgra_compute_latency;


  logic [TID_WIDTH-1:0] tid_x;
  logic [TID_WIDTH-1:0] tid_y;
  logic [TID_WIDTH-1:0] tid_z;
  //block size
  logic [TID_WIDTH-1:0] ntid_x;
  logic [TID_WIDTH-1:0] ntid_y;
  logic [TID_WIDTH-1:0] ntid_z;

  logic [NUM_CGRA_IO-1:0] spec_rd_en;
  logic [NUM_CGRA_IO*4-1:0] spec_rd_select;
  logic [NUM_CGRA_IO*DATA_WIDTH-1:0] const_reg;
  //dispatcher tp hgen
  naive_dispatcher #(.TOTAL_TID(NUM_TID)) u_dispatcher
  (
    .clk(clk),
    .rst_n(rst_n),
    .enable(disp_enable),
    .clr(disp_clr),
    .max_tid(9'd255),
    .ntid_x(ntid_x),
    .ntid_y(ntid_y),
    .ntid_z(ntid_z),
    .tid_x(tid_x),
    .tid_y(tid_y),
    .tid_z(tid_z),
    .done(disp_done),
    .dispatch_tid(dispatch_tid),
    .tid_valid(disp_tid_valid)
  );

  //CGRA subsystem
  dice_cgra_subsystem 
#(
    .NUM_CGRA_IO(NUM_CGRA_IO),
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_TID(NUM_TID),
    .MAX_CTA_ID(MAX_CTA_ID),
    .MAX_IO_PIPE_STAGE(MAX_IO_PIPE_STAGE),
    .MAX_CGRA_PIPE_STAGE(MAX_CGRA_PIPE_STAGE),
    .CGRA_CFG_WIDTH(CFG_WIDTH)
) u_cgra_subsystem (
    .clk(clk),
    .rst_n(rst_n),
    .clr(clr),
    .done(cgra_done),

    // From Dispatcher
    .disp_tid(dispatch_tid),
    .disp_valid(disp_tid_valid),
    .tid_x(tid_x),
    .tid_y(tid_y),
    .tid_z(tid_z),
    .ntid_x(ntid_x),
    .ntid_y(ntid_y),
    .ntid_z(ntid_z),
    .ctaid_x(16'd0),
    .ctaid_y(16'd0),
    .ctaid_z(16'd0),
    .nctaid_x(16'd1),
    .nctaid_y(16'd1),
    .nctaid_z(16'd1),
    // From metadata to control RF read/write enables
    // special register
    .spec_rd_enable(spec_rd_en),
    .spec_rd_select(spec_rd_select),
    .const_reg(const_reg),
    // general purpose register file
    .rf_rd_en(rf_rd_en),
    .rf_wr_en(rf_wr_en),
    // predicate register file
    .prf_rd_en(prf_rd_en),
    .prf_wr_en(prf_wr_en),
    // Config
    // Latency control
    .rf_latency_in_cgra(rf_latency_in),
    .rf_latency_out_cgra(rf_latency_out),
    .prf_latency_in_cgra(prf_latency_in),
    .prf_latency_out_cgra(prf_latency_out),
    // RF address override
    .rd_override_enable(rd_override_enable),
    .rd_override_address(rd_override_address),
    .wr_override_enable(wr_override_enable),
    .wr_override_address(wr_override_address),
    // CGRA config
    .cgra_compute_latency(cgra_compute_latency),
    .cgra_cfg(cgra_cfg)
);

logic [PRED_RF_CFG_BITS_PER_PORT*NUM_CGRA_IO-1:0] predrf_cfg;
logic [GPRF_CFG_BITS_PER_PORT*NUM_CGRA_IO-1:0] gprf_cfg;


//map cfg to each port
always_comb begin
    for(int i=0; i<NUM_CGRA_IO; i++) begin
        {prf_rd_en[i], prf_wr_en[i], prf_latency_in[i*IO_PIPE_SEL_WIDTH +: IO_PIPE_SEL_WIDTH], prf_latency_out[i*IO_PIPE_SEL_WIDTH +: IO_PIPE_SEL_WIDTH]} = predrf_cfg[i*PRED_RF_CFG_BITS_PER_PORT +: PRED_RF_CFG_BITS_PER_PORT];
        {
          rf_rd_en[i], 
          rf_wr_en[i], 
          rf_latency_in[i*IO_PIPE_SEL_WIDTH +: IO_PIPE_SEL_WIDTH], 
          rf_latency_out[i*IO_PIPE_SEL_WIDTH +: IO_PIPE_SEL_WIDTH], 
          spec_rd_en[i], 
          spec_rd_select[i*4 +: 4], 
          rd_override_address[i*ADDR_WIDTH +: ADDR_WIDTH], 
          wr_override_address[i*ADDR_WIDTH +: ADDR_WIDTH], 
          rd_override_enable[i*ADDR_WIDTH +: ADDR_WIDTH], 
          wr_override_enable[i*ADDR_WIDTH +: ADDR_WIDTH]
        } = gprf_cfg[i*GPRF_CFG_BITS_PER_PORT +: GPRF_CFG_BITS_PER_PORT];
    end
end



  //-----------------------------------------------------------
  // Load configuration
  //-----------------------------------------------------------
  initial begin
    //ntid
    ntid_x = 9'd255;
    ntid_y = 9'd0;
    ntid_z = 9'd0;
    const_reg = '0;
  end

  initial begin
    //load predrf_bitstream
    int fd;
    string line;
    int io_port_index = 0;
    int status;
    int tile_idx = 0;
    int last;

    //prf_latency_in = '0;
    //prf_latency_out = '0;
    //prf_rd_en = '0;
    //prf_wr_en = '0;

    fd = $fopen("bitstreams/predrf_bitstream.txt", "r");
    if (!fd) $fatal("Cannot open predrfbitstream.txt");

    while (!$feof(fd) && io_port_index < NUM_CGRA_IO) begin
      status = $fgets(line, fd);

      // -----------------------------------------------------
      // Manually trim trailing whitespace and newline chars
      // -----------------------------------------------------
      last = line.len() - 1;
      while (last >= 0 &&
             (line[last] == "\n" || line[last] == "\r" ||
              line[last] == " "  || line[last] == "\t"))
        last--;
      if (last >= 0)
        line = line.substr(0, last);
      else
        continue;  // skip empty line

      // -----------------------------------------------------
      // Skip invalid lines that are shorter than expected
      // -----------------------------------------------------
      if (line.len() < PRED_RF_CFG_BITS_PER_PORT)
        continue;

      // -----------------------------------------------------
      // Convert ASCII '1'/'0' to bits
      // -----------------------------------------------------
      for (int b = 0; b < PRED_RF_CFG_BITS_PER_PORT; b++) begin
        predrf_cfg[io_port_index * PRED_RF_CFG_BITS_PER_PORT +
                   (PRED_RF_CFG_BITS_PER_PORT - 1 - b)] = (line[b] == "1");
      end

      io_port_index++;
    end
    $fclose(fd);
    $display("[%0t] Loaded bitstream into %0d predicate IO ports.", $time, io_port_index);

    //load gprf_bitstream
    //rf_latency_in = '0;
    //rf_latency_out = '0;
    //rf_rd_en = '0;
    //rf_wr_en = '0;
    //rd_override_enable = '0;
    //rd_override_address = '0;
    //wr_override_enable = '0;
    //wr_override_address = '0;
    //spec_rd_en = '0;
    //spec_rd_select = '0;

    io_port_index = 0;
    fd = $fopen("bitstreams/gprf_bitstream.txt", "r");
    if (!fd) $fatal("Cannot open gprf_bitstream.txt");

    while (!$feof(fd) && io_port_index < NUM_CGRA_IO) begin
      status = $fgets(line, fd);

      // -----------------------------------------------------
      // Manually trim trailing whitespace and newline chars
      // -----------------------------------------------------
      last = line.len() - 1;
      while (last >= 0 &&
             (line[last] == "\n" || line[last] == "\r" ||
              line[last] == " "  || line[last] == "\t"))
        last--;
      if (last >= 0)
        line = line.substr(0, last);
      else
        continue;  // skip empty line

      // -----------------------------------------------------
      // Skip invalid lines that are shorter than expected
      // -----------------------------------------------------
      if (line.len() < GPRF_CFG_BITS_PER_PORT)
        continue;

      // -----------------------------------------------------
      // Convert ASCII '1'/'0' to bits
      // -----------------------------------------------------
      for (int b = 0; b < GPRF_CFG_BITS_PER_PORT; b++) begin
        gprf_cfg[io_port_index * GPRF_CFG_BITS_PER_PORT +
                   (GPRF_CFG_BITS_PER_PORT - 1 - b)] = (line[b] == "1");
      end

      io_port_index++;
    end
    $fclose(fd);
    $display("[%0t] Loaded bitstream into %0d general-purpose IO ports.", $time, io_port_index);
    cgra_compute_latency = 72; // Example compute latency

    
    cgra_cfg = '0;
    fd = $fopen("bitstreams/cgra_bitstream.txt", "r");
    if (!fd) $fatal("Cannot open cgra_bitstream.txt");

    while (!$feof(fd) && tile_idx < NUM_TILES) begin
    status = $fgets(line, fd);

    // -----------------------------------------------------
    // Manually trim trailing whitespace and newline chars
    // -----------------------------------------------------
    last = line.len() - 1;
    while (last >= 0 &&
           (line[last] == "\n" || line[last] == "\r" ||
            line[last] == " "  || line[last] == "\t"))
      last--;
    if (last >= 0)
      line = line.substr(0, last);
    else
      continue; // skip empty lines

    // -----------------------------------------------------
    // Skip invalid lines shorter than expected bit width
    // -----------------------------------------------------
    if (line.len() < TILE_BITS)
      continue;

    // -----------------------------------------------------
    // Convert ASCII '1'/'0' to bits (MSB-first)
    // -----------------------------------------------------
    for (int b = 0; b < TILE_BITS; b++) begin
      cgra_cfg[tile_idx * TILE_BITS + (TILE_BITS - 1 - b)] = (line[b] == "1");
    end

    tile_idx++;
  end
    $fclose(fd);
    $display("[%0t] Loaded %0d tiles into CGRA config", $time, tile_idx);
  end

  // -------------------------------------------------------------
  // Load all register file memories and save outputs
  // -------------------------------------------------------------
  generate
    for (genvar gi = 0; gi < NUM_CGRA_IO; gi++) begin : gen_rf_io

      // ---------------------------
      // Load memory after reset
      // ---------------------------
      initial begin
        string rf_in_r, rf_in_p;
        wait(rst_n);
        #20;
        rf_in_r = $sformatf("rf_input/r%0d_in.txt", gi);
        rf_in_p = $sformatf("rf_input/p%0d_in.txt", gi);

        // Each instance index (gi) is elaboration-time constant
        u_cgra_subsystem.u_gprf_ctrl.gen_rf_banks[gi]
          .u_dice_register_file.gen_bank[0].bank_ram.load_memory_from_file(rf_in_r);

        u_cgra_subsystem.u_pred_rf_ctrl.gen_rf_banks[gi]
          .u_dice_register_file.gen_bank[0].bank_ram.load_memory_from_file(rf_in_p);

        $display("[%0t] Port %0d RF memories loaded", $time, gi);
      end

      // ---------------------------
      // Save output memory at end
      // ---------------------------
      initial begin
        string rf_out_r, rf_out_p;
        wait(rst_n);
        wait(cgra_done & disp_done);
        rf_out_r = $sformatf("rf_output/r%0d_out.txt", gi);
        rf_out_p = $sformatf("rf_output/p%0d_out.txt", gi);

        u_cgra_subsystem.u_gprf_ctrl.gen_rf_banks[gi]
          .u_dice_register_file.gen_bank[0].bank_ram.save_memory_to_file(rf_out_r);

        u_cgra_subsystem.u_pred_rf_ctrl.gen_rf_banks[gi]
          .u_dice_register_file.gen_bank[0].bank_ram.save_memory_to_file(rf_out_p);

        $display("[%0t] Port %0d RF outputs saved", $time, gi);
      end

    end
  endgenerate
  //-----------------------------------------------------------
  // Clock / Reset
  //-----------------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // -------------------------------------------------------------
  // Run simulation
  // -------------------------------------------------------------
  initial begin
    rst_n = 0;
    clr = 1;
    disp_clr = 1;
    disp_enable = 0;
    repeat (10) @(negedge clk);
    rst_n = 1;
    repeat (10) @(negedge clk);
    clr = 0;
    disp_clr = 0;
    disp_enable = 1;
    repeat (10) @(negedge clk);
    wait(cgra_done & disp_done);
    #100;
    $display("[%0t] Simulation completed", $time);
    $finish;
  end

  initial begin
    //dump fsdb
    $fsdbDumpfile("tb_dice_cgra.fsdb");
    $fsdbDumpvars(0, tb_dice_cgra);
  end
endmodule
