module shift_reg

  import dice_pkg::*;
  import DE_pkg::*;

#(
    // can be configured for other widths, default is a TID shift reg
    parameter int WIDTH          = DICE_TID_WIDTH,
    parameter int MAX_PIPE_STAGE = 128              // must be a power of 2
) (
    input  logic                              clk_i,
    input  logic                              reset_i,  // synchronous reset (active high)
    input  logic                              clear_i,  // zero all entries (eblock transition)
    input  logic [$clog2(MAX_PIPE_STAGE)-1:0] latency,
    input  logic [                 WIDTH-1:0] in_data,
    output logic [                 WIDTH-1:0] out_data
);

  localparam int LAT_W = $clog2(MAX_PIPE_STAGE);  // MAX_PIPE_STAGE must be power-of-2

  // Ring buffer storage and write pointer
  logic [WIDTH-1:0] buffer [0:MAX_PIPE_STAGE-1];
  logic [LAT_W-1:0] wr_ptr;

  always_ff @(posedge clk_i) begin
    if (reset_i || clear_i) begin
      wr_ptr <= '0;
      for (int i = 0; i < MAX_PIPE_STAGE; i++) buffer[i] <= '0;
    end else begin
      buffer[wr_ptr] <= in_data;  // write only ONE entry per cycle
      wr_ptr         <= wr_ptr + 1'b1;  // wraps naturally at LAT_W bits
    end
  end

  // Read index: wr_ptr - latency wraps automatically (power-of-2 depth)
  // buffer[wr_ptr - L] holds the value written exactly L cycles ago
  // assign out_data = (latency == '0) ? in_data : buffer[wr_ptr-latency];
  assign out_data = buffer[wr_ptr-latency];


endmodule
