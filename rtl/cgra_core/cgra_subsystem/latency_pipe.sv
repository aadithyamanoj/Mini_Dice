module latency_pipe #(
  parameter int WIDTH = 32,
  parameter int MAX_PIPE_STAGE = 1
)(
  input  logic                     clk,
  input  logic                     rst_n,   // asynchronous reset (active low)
  input  logic                     clr,     // synchronous clear (active high)
  input  logic [$clog2(MAX_PIPE_STAGE)-1:0]         latency,
  input  logic [WIDTH-1:0]         in_data,
  output logic [WIDTH-1:0]         out_data
);
  localparam int LAT_W = (MAX_PIPE_STAGE > 1) ? $clog2(MAX_PIPE_STAGE) : 1;

  logic [WIDTH-1:0] pipe [0:MAX_PIPE_STAGE-1];

  // Pipeline shift + clear
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // async reset clears everything
      for (int i = 0; i < MAX_PIPE_STAGE; i++)
        pipe[i] <= '0;
    end else if (clr) begin
      // sync clear clears everything
      for (int i = 0; i < MAX_PIPE_STAGE; i++)
        pipe[i] <= '0;
    end else begin
      // only shift up to latency
      if (latency != 0) begin
        pipe[0] <= in_data;
        for (int i = 1; i < MAX_PIPE_STAGE; i++) begin
          if (i < latency)
            pipe[i] <= pipe[i-1];
        end
      end
    end
  end

  assign out_data = (latency == 0) ? in_data : pipe[latency-1];

endmodule
