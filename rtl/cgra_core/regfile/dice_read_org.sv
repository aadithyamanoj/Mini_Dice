module dice_read_org
import DE_pkg::*;
import dice_pkg::*;
#(
    parameter int NUM_PORTS = DICE_NUM_BANKS,
    parameter int DATA_WIDTH = DICE_REG_DATA_WIDTH,
    parameter int NUM_TID = 512,
    parameter int TID_WIDTH = $clog2(NUM_TID),
    parameter int DEPTH = NUM_TID,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)
(
      input  logic              clk_i
    , input  logic              reset_i

    // Read Input
    // take anywhere from 1 to 4 tids
    // take one bitmap
    // send to a new module called called read_org

    // valid ready for tid and bitmap
    , input logic                             rd_tid_valid_i
    , output logic                            rd_tid_ready_o

    // some signal for unrolling factor to select
    , input logic [1:0]                       rd_unroll_factor_i
    , input logic                             rd_en_i
    , input logic [(4*TID_WIDTH)-1:0]         rd_tid_i
    , input logic [NUM_PORTS-1:0]             rd_bitmap_i

    // output
    , output logic [NUM_PORTS*TID_WIDTH-1:0] rd_sel_o 
    , output logic [NUM_PORTS-1:0]           rd_en_o
    , output logic                           rd_valid_o
);

    // Extract TIDs from packed input (up to 4 TIDs)
    logic [TID_WIDTH-1:0] tid_0, tid_1, tid_2, tid_3;
    assign tid_0 = rd_tid_i[0*TID_WIDTH +: TID_WIDTH];
    assign tid_1 = rd_tid_i[1*TID_WIDTH +: TID_WIDTH];
    assign tid_2 = rd_tid_i[2*TID_WIDTH +: TID_WIDTH];
    assign tid_3 = rd_tid_i[3*TID_WIDTH +: TID_WIDTH];


    // Circular left shift of bitmap by shift_amt
    // result = (bitmap << shift_amt) | (bitmap >> (NUM_PORTS - shift_amt))
    logic [NUM_PORTS-1:0] shifted_bitmap;

    assign shifted_bitmap = shift_bitmap(rd_bitmap_i, tid_0);
   
    // Ready when enabled
    assign rd_tid_ready_o = rd_en_i;

    // Swizzle logic: route TIDs to banks based on unrolling factor
    always_comb begin
        // Initialize outputs to zero

        rd_sel_o = '0;
        rd_en_o = '0;

        if (rd_en_i && rd_tid_valid_i) begin
            case (rd_unroll_factor_i)
                // No unrolling: 1 TID
              

                2'b00: begin
                    // Set valid bits from shifted bitmap
                    rd_en_o = shifted_bitmap;

                    // For each bank with valid bit set, place the TID
                    for (int i = 0; i < NUM_PORTS; i++) begin
                        if (shifted_bitmap[i]) begin
                            rd_sel_o[i*TID_WIDTH +: TID_WIDTH] = tid_0;
                        end
                    end
                end

                // Unroll factor 1: 2 TIDs
                2'b01: begin
                    // TODO: implement 2 TID case
                end

                // Unroll factor 2: 4 TIDs
                2'b10: begin
                    // TODO: implement 4 TID case
                end

                default: begin
                    // Invalid unroll factor, outputs remain zero
                end
            endcase
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