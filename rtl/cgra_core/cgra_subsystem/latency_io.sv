module latency_io #(
  parameter int NUM_PORTS = 4,
  parameter int WIDTH = 32,
  parameter int MAX_PIPE_STAGE = 16
)(
  input  logic                             clk,
  input  logic                             rst_n,
  input  logic                             clr,  

  // Latency control
  input  logic [NUM_PORTS*$clog2(MAX_PIPE_STAGE)-1:0] latency_in,
  input  logic [NUM_PORTS*$clog2(MAX_PIPE_STAGE)-1:0] latency_out,

  // Interface to RAM
  input  logic [NUM_PORTS*WIDTH-1:0]        rf_rdata,
  output logic [NUM_PORTS*WIDTH-1:0]        rf_wdata,
  // Interface to CGRA
  output logic [NUM_PORTS*WIDTH-1:0]        cgra_in,
  input  logic [NUM_PORTS*WIDTH-1:0]        cgra_out
);

  //----------------------------
  // Latency pipes
  //----------------------------
  genvar i;
  generate
    for (i = 0; i < NUM_PORTS; i++) begin : gen_port
      latency_pipe #(
        .WIDTH(WIDTH),
        .MAX_PIPE_STAGE(MAX_PIPE_STAGE)
      ) in_lat (
        .clk     (clk),
        .rst_n   (rst_n),
        .clr     (clr),
        .latency (latency_in[i*$clog2(MAX_PIPE_STAGE)+:$clog2(MAX_PIPE_STAGE)]),
        .in_data (rf_rdata[(i+1)*WIDTH-1:i*WIDTH]),
        .out_data(cgra_in[(i+1)*WIDTH-1:i*WIDTH])
      );

      latency_pipe #(
        .WIDTH(WIDTH), // extra bit for pred
        .MAX_PIPE_STAGE(MAX_PIPE_STAGE)
      ) out_lat (
        .clk     (clk),
        .rst_n   (rst_n),
        .clr     (clr),
        .latency (latency_out[i*$clog2(MAX_PIPE_STAGE)+:$clog2(MAX_PIPE_STAGE)]),
        .in_data (cgra_out[(i+1)*WIDTH-1:i*WIDTH]),
        .out_data(rf_wdata[(i+1)*WIDTH-1:i*WIDTH])
      );
    end
  endgenerate
endmodule
