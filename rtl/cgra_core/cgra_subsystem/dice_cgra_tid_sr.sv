module dice_cgra_tid_sr #(
    parameter int TOTAL_TID   = 512,
    parameter int TID_WIDTH   = $clog2(TOTAL_TID),
    parameter int MAX_LATENCY = 32
)(
    input  logic                             clk,
    input  logic                             rst_n,
    // latency control
    input  logic                             clr,   // flush pipe
    input  logic [$clog2(MAX_LATENCY)-1:0] latency,

    input  logic [TID_WIDTH-1:0]             in_tid,
    input  logic                             in_valid,

    output logic [TID_WIDTH-1:0]            out_tid,
    output logic                            out_valid,

    output logic                            empty
);

  //-------------------------------
  // Latency shifter
  //-------------------------------
  latency_pipe #(
    .WIDTH(TID_WIDTH+1),
    .MAX_PIPE_STAGE(MAX_LATENCY)
  ) tid_sr_pipe_inst (
    .clk      (clk),
    .rst_n    (rst_n),
    .clr      (clr),
    .latency  (latency),
    .in_data  ({in_valid, in_tid}),    // valid as MSB
    .out_data ({out_valid, out_tid})
  );

  //empty is calculated by a counter to counter input valid and output valids
  logic [$clog2(MAX_LATENCY)-1:0] counter;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 0;
    end else if (clr) begin
        counter <= 0;
    end else begin
        if (in_valid && !out_valid) begin
            if (counter < MAX_LATENCY)
                counter <= counter + 1;
        end else if (!in_valid && out_valid) begin
            if (counter > 0)
                counter <= counter - 1;
        end
    end
  end

  assign empty = (counter == 0);

endmodule
