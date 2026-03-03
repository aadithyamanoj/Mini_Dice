// can hold a constant 32bit value and tid.x, tid.y, tid.z, ntid.x, ntid.y, ntid.z, ctaid.x, ctaid.y, ctaid.z, nctaid.x, nctaid.y, nctaid.z
module dice_special_reg#(
    parameter int DATA_WIDTH = 32,
    parameter int NUM_TID = 512,
    parameter int TID_WIDTH = $clog2(NUM_TID),
    parameter int MAX_CTA_ID = 65535,
    parameter int CTA_ID_WIDTH = $clog2(MAX_CTA_ID)
)(
    input logic clk_i,
    input logic reset_i,
    input logic clear_i,

    //config
    input logic rd_en,
    input logic [3:0] rd_sel,
    
    //dispatcher input
    input logic [DATA_WIDTH-1:0] const_data, //constant value register
    input logic [TID_WIDTH-1:0] tid_x,
    input logic [TID_WIDTH-1:0] tid_y,
    input logic [TID_WIDTH-1:0] tid_z,
    input logic [TID_WIDTH-1:0] ntid_x,
    input logic [TID_WIDTH-1:0] ntid_y,
    input logic [TID_WIDTH-1:0] ntid_z,
    input logic [CTA_ID_WIDTH-1:0] ctaid_x,
    input logic [CTA_ID_WIDTH-1:0] ctaid_y,
    input logic [CTA_ID_WIDTH-1:0] ctaid_z,
    input logic [CTA_ID_WIDTH-1:0] nctaid_x,
    input logic [CTA_ID_WIDTH-1:0] nctaid_y,
    input logic [CTA_ID_WIDTH-1:0] nctaid_z,
    //output
    output logic [DATA_WIDTH-1:0] out_data
);  

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            out_data <= '0;
        end else if (clear_i) begin
            out_data <= '0;
        end else if (rd_en) begin
            case (rd_sel)
                4'd0: out_data <= const_data;
                4'd1: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, tid_x};
                4'd2: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, tid_y};
                4'd3: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, tid_z};
                4'd4: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, ntid_x};
                4'd5: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, ntid_y};
                4'd6: out_data <= {{(DATA_WIDTH-TID_WIDTH){1'b0}}, ntid_z};
                4'd7: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, ctaid_x};
                4'd8: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, ctaid_y};
                4'd9: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, ctaid_z};
                4'd10: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, nctaid_x};
                4'd11: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, nctaid_y};
                4'd12: out_data <= {{(DATA_WIDTH-CTA_ID_WIDTH){1'b0}}, nctaid_z};
                default: out_data <= '0;
            endcase
        end
    end

endmodule
