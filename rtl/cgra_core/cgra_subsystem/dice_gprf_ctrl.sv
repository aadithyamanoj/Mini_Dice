//these module includes all 32-bit general-purpose register file banks (16 banks) and rf input/output address converter and input/output latency management and special register control
module dice_gprf_ctrl #(
    parameter int NUM_PORTS = 16,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_TID = 512,
    parameter int MAX_CTA_ID = 65535,
    parameter int RF_ADDR_WIDTH = $clog2(NUM_TID),
    parameter int CTAID_WIDTH = $clog2(MAX_CTA_ID),
    parameter int MAX_IO_PIPE_STAGE = 8
)(
    input  logic              clk,
    input  logic              rst_n,
    input logic               clr,
    // Read Input
    input  logic [NUM_PORTS-1:0]    rd_en,
    input  logic [RF_ADDR_WIDTH-1:0] rd_tid,
    output logic [NUM_PORTS*DATA_WIDTH-1:0] rd_data,
    // Write Input
    input  logic [NUM_PORTS-1:0]    wr_en,
    input  logic [RF_ADDR_WIDTH-1:0] wr_tid,
    input  logic [NUM_PORTS*DATA_WIDTH-1:0] wr_data,
    //rf control config
    input logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] rd_addr_override_enable,
    input logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] rd_addr_override_address,
    input logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] wr_addr_override_enable,
    input logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] wr_addr_override_address,
    //latency config
    input logic [NUM_PORTS*$clog2(MAX_IO_PIPE_STAGE)-1:0] input_latency,
    input logic [NUM_PORTS*$clog2(MAX_IO_PIPE_STAGE)-1:0] output_latency,
    // gprf/special reg select
    input logic [NUM_PORTS-1:0] spec_rd_enable,
    input logic [NUM_PORTS*4-1:0] spec_reg_sel,
    input logic [NUM_PORTS*DATA_WIDTH-1:0] const_reg,
    //tid info
    input logic [RF_ADDR_WIDTH-1:0] tid_x,
    input logic [RF_ADDR_WIDTH-1:0] tid_y,
    input logic [RF_ADDR_WIDTH-1:0] tid_z,
    input logic [RF_ADDR_WIDTH-1:0] ntid_x,
    input logic [RF_ADDR_WIDTH-1:0] ntid_y,
    input logic [RF_ADDR_WIDTH-1:0] ntid_z,
    input logic [CTAID_WIDTH-1:0] ctaid_x,
    input logic [CTAID_WIDTH-1:0] ctaid_y,
    input logic [CTAID_WIDTH-1:0] ctaid_z,
    input logic [CTAID_WIDTH-1:0] nctaid_x,
    input logic [CTAID_WIDTH-1:0] nctaid_y,
    input logic [CTAID_WIDTH-1:0] nctaid_z
);
    localparam int LATW = $clog2(MAX_IO_PIPE_STAGE);
    //address converter
    logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] conv_rd_addr;
    logic [NUM_PORTS*RF_ADDR_WIDTH-1:0] conv_wr_addr;
    //data after latency pipe
    logic [NUM_PORTS*DATA_WIDTH-1:0] pipe_rf_rd_data;
    logic [NUM_PORTS*DATA_WIDTH-1:0] pipe_rd_data;
    logic [NUM_PORTS*DATA_WIDTH-1:0] pipe_wr_data;
    logic [NUM_PORTS*DATA_WIDTH-1:0] spec_reg_out;
    
    logic [NUM_PORTS*DATA_WIDTH-1:0] pipe_rd_data_final;
    logic [NUM_PORTS-1:0] rd_en_pre;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_en_pre <= '0;
        end else if (clr) begin
            rd_en_pre <= '0;
        end else begin
            rd_en_pre <= rd_en; 
        end
    end

    always_comb begin
        for (int i = 0; i < NUM_PORTS; i++) begin
            pipe_rd_data_final[i*DATA_WIDTH +: DATA_WIDTH] = rd_en_pre[i]? pipe_rd_data[i*DATA_WIDTH +: DATA_WIDTH] : '0;
        end
    end
    //generate individual instance for each port to ease debug from waveform
    genvar i;
    generate
        for (i = 0; i < NUM_PORTS; i++) begin : gen_rf_banks
            dice_special_reg #(
              .DATA_WIDTH(DATA_WIDTH),
              .NUM_TID(NUM_TID),
              .MAX_CTA_ID(MAX_CTA_ID)
            ) u_special_reg_extra (
              .clk(clk),
              .rst_n(rst_n),
              .clr(clr),
              .rd_en(spec_rd_enable[i]),
              .rd_sel(spec_reg_sel[i*4 +: 4]),
              .const_data(const_reg[i*DATA_WIDTH +: DATA_WIDTH]),
              .tid_x(tid_x),
              .tid_y(tid_y),
              .tid_z(tid_z),
              .ntid_x(ntid_x),
              .ntid_y(ntid_y),
              .ntid_z(ntid_z),
              .ctaid_x(ctaid_x),
              .ctaid_y(ctaid_y),
              .ctaid_z(ctaid_z),
              .nctaid_x(nctaid_x),
              .nctaid_y(nctaid_y),
              .nctaid_z(nctaid_z),
              .out_data(spec_reg_out[i*DATA_WIDTH +: DATA_WIDTH])
            );

            assign pipe_rd_data[i*DATA_WIDTH +: DATA_WIDTH] = spec_rd_enable[i] ? spec_reg_out[i*DATA_WIDTH +: DATA_WIDTH] : pipe_rf_rd_data[i*DATA_WIDTH +: DATA_WIDTH];

            latency_io #(
                .NUM_PORTS(1),
                .WIDTH(DATA_WIDTH),
                .MAX_PIPE_STAGE(MAX_IO_PIPE_STAGE)
            ) u_cgra_port_io (
                .clk         (clk),
                .rst_n       (rst_n),
                .clr         (clr),
                .latency_in  (input_latency[i*LATW+:LATW]),
                .latency_out (output_latency[i*LATW+:LATW]),
                .rf_rdata    (pipe_rd_data_final[i*DATA_WIDTH +: DATA_WIDTH]),
                .rf_wdata    (pipe_wr_data[i*DATA_WIDTH +: DATA_WIDTH]),
                .cgra_in     (rd_data[i*DATA_WIDTH +: DATA_WIDTH]),
                .cgra_out    (wr_data[i*DATA_WIDTH +: DATA_WIDTH])
            );

            dice_rf_address_converter #(
                .NUM_BANK(1),
                .DEPTH(NUM_TID)
            ) u_rd_address_converter (
                .disp_tid         (rd_tid[0 +: RF_ADDR_WIDTH]),
                .rf_addr         (conv_rd_addr[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .override_enable  (rd_addr_override_enable[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .override_address (rd_addr_override_address[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH])
            );

            dice_rf_address_converter #(
                .NUM_BANK(1),
                .DEPTH(NUM_TID)
            ) u_wr_address_converter (
                .disp_tid         (wr_tid[0 +: RF_ADDR_WIDTH]),
                .rf_addr         (conv_wr_addr[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .override_enable  (wr_addr_override_enable[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .override_address (wr_addr_override_address[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH])
            );

            dice_register_file #(
                .NUM_BANK(1),
                .WIDTH(DATA_WIDTH),
                .DEPTH(NUM_TID)
            ) u_dice_register_file (
                .clk     (clk),
                .rst_n   (rst_n),
                .rd_en   (rd_en[i]),
                .rd_addr (conv_rd_addr[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .rd_data (pipe_rf_rd_data[i*DATA_WIDTH +: DATA_WIDTH]),
                .wr_en   (wr_en[i]), //from outside
                .wr_addr (conv_wr_addr[i*RF_ADDR_WIDTH +: RF_ADDR_WIDTH]),
                .wr_data (pipe_wr_data[i*DATA_WIDTH +: DATA_WIDTH])
            );

        end
    endgenerate

    // Guards
    initial begin
      if (MAX_IO_PIPE_STAGE < 0) $fatal(1, "MAX_IO_PIPE_STAGE must be >= 0");
      if (NUM_TID <= 0)          $fatal(1, "NUM_TID must be > 0");
    end
endmodule