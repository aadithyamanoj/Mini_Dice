module dice_read_org
<<<<<<< HEAD
  import DE_pkg::*;
  import dice_pkg::*;
=======
import DE_pkg::*;
import dice_pkg::*;
>>>>>>> origin/merging
#(
    parameter int NUM_PORTS = DICE_NUM_BANKS,
    parameter int DATA_WIDTH = DICE_REG_DATA_WIDTH,
    parameter int NUM_TID = 512,
    parameter int TID_WIDTH = $clog2(NUM_TID),
    parameter int DEPTH = NUM_TID,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
<<<<<<< HEAD
) (
      input logic clk_i
    , input logic reset_i

    // Read Input
    , input  logic rd_tid_valid_i
    , output logic rd_tid_ready_o

    // , input logic                             rd_en_i
    , input logic [TID_WIDTH-1:0] rd_tid_i
    , input logic [NUM_PORTS-1:0] rd_bitmap_i

    // output
    , output logic [NUM_PORTS*TID_WIDTH-1:0] rd_sel_o
    , output logic [          NUM_PORTS-1:0] rd_en_o
    , output logic                           rd_valid_o
);

  // Direct bitmap (no swizzling)
  logic [NUM_PORTS-1:0] shifted_bitmap;

  assign shifted_bitmap = rd_bitmap_i;

  // Ready when enabled
  // change later
  assign rd_tid_ready_o = '1;

  // Route single TID to all banks
  always_comb begin
    rd_sel_o = '0;
    rd_en_o  = '0;

    if (rd_tid_valid_i) begin
      rd_en_o  = shifted_bitmap;
      rd_sel_o = {NUM_PORTS{rd_tid_i}};
    end
  end

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      rd_valid_o <= '0;
    end else begin
      rd_valid_o <= rd_tid_valid_i;
    end
  end

endmodule
=======
)
(
      input  logic              clk_i
    , input  logic              reset_i

    // Read Input
    , input logic                             rd_tid_valid_i
    , output logic                            rd_tid_ready_o

    , input logic                             rd_en_i
    , input logic [TID_WIDTH-1:0]             rd_tid_i
    , input logic [NUM_PORTS-1:0]             rd_bitmap_i

    // output
    , output logic [NUM_PORTS*TID_WIDTH-1:0] rd_sel_o 
    , output logic [NUM_PORTS-1:0]           rd_en_o
    , output logic                           rd_valid_o
);

    // Direct bitmap (no swizzling)
    logic [NUM_PORTS-1:0] shifted_bitmap;

    assign shifted_bitmap = rd_bitmap_i;
   
    // Ready when enabled
    assign rd_tid_ready_o = rd_en_i;

    // Route single TID to all banks
    always_comb begin
        rd_sel_o = '0;
        rd_en_o = '0;

        if (rd_en_i && rd_tid_valid_i) begin
            rd_en_o = shifted_bitmap;
            rd_sel_o = {NUM_PORTS{rd_tid_i}};
        end
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rd_valid_o <= '0;
        end else begin
            rd_valid_o <= rd_tid_valid_i;
        end
    end

endmodule
>>>>>>> origin/merging
