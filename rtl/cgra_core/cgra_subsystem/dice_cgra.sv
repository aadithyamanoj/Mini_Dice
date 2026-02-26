module dice_cgra(
    input logic clk,
    input logic rst_n,
    //North port
    input logic [31:0] CGRA_N_in_t0,
    input logic [31:0] CGRA_N_in_t1,
    input logic [31:0] CGRA_N_in_t2,
    input logic [31:0] CGRA_N_in_t3,
    input logic [31:0] CGRA_N_in_t4,
    input logic [31:0] CGRA_N_in_t5,
    input logic [31:0] CGRA_N_in_t6,
    input logic [31:0] CGRA_N_in_t7,
    output logic [31:0] CGRA_N_out_t0,
    output logic [31:0] CGRA_N_out_t1,
    output logic [31:0] CGRA_N_out_t2,
    output logic [31:0] CGRA_N_out_t3,
    output logic [31:0] CGRA_N_out_t4,
    output logic [31:0] CGRA_N_out_t5,
    output logic [31:0] CGRA_N_out_t6,
    output logic [31:0] CGRA_N_out_t7,
    input logic  CGRA_N_in_p0,
    input logic  CGRA_N_in_p1,
    input logic  CGRA_N_in_p2,
    input logic  CGRA_N_in_p3,
    input logic  CGRA_N_in_p4,
    input logic  CGRA_N_in_p5,
    input logic  CGRA_N_in_p6,
    input logic  CGRA_N_in_p7,
    output logic CGRA_N_out_p0,
    output logic CGRA_N_out_p1,
    output logic CGRA_N_out_p2,
    output logic CGRA_N_out_p3,
    output logic CGRA_N_out_p4,
    output logic CGRA_N_out_p5,
    output logic CGRA_N_out_p6,
    output logic CGRA_N_out_p7,

    //East port
    input logic [31:0] CGRA_E_in_t0,
    input logic [31:0] CGRA_E_in_t1,
    input logic [31:0] CGRA_E_in_t2,
    input logic [31:0] CGRA_E_in_t3,
    input logic [31:0] CGRA_E_in_t4,
    input logic [31:0] CGRA_E_in_t5,
    input logic [31:0] CGRA_E_in_t6,
    input logic [31:0] CGRA_E_in_t7,
    output logic [31:0] CGRA_E_out_t0,
    output logic [31:0] CGRA_E_out_t1,
    output logic [31:0] CGRA_E_out_t2,
    output logic [31:0] CGRA_E_out_t3,
    output logic [31:0] CGRA_E_out_t4,
    output logic [31:0] CGRA_E_out_t5,
    output logic [31:0] CGRA_E_out_t6,
    output logic [31:0] CGRA_E_out_t7,
    input logic  CGRA_E_in_p0,
    input logic CGRA_E_in_p1,
    input logic CGRA_E_in_p2,
    input logic CGRA_E_in_p3,
    input logic CGRA_E_in_p4,
    input logic CGRA_E_in_p5,
    input logic CGRA_E_in_p6,
    input logic CGRA_E_in_p7,
    output logic CGRA_E_out_p0,
    output logic CGRA_E_out_p1,
    output logic CGRA_E_out_p2,
    output logic CGRA_E_out_p3,
    output logic CGRA_E_out_p4,
    output logic CGRA_E_out_p5,
    output logic CGRA_E_out_p6,
    output logic CGRA_E_out_p7,

    //South port
    input logic [31:0] CGRA_S_in_t0,
    input logic [31:0] CGRA_S_in_t1,
    input logic [31:0] CGRA_S_in_t2,
    input logic [31:0] CGRA_S_in_t3,
    input logic [31:0] CGRA_S_in_t4,
    input logic [31:0] CGRA_S_in_t5,
    input logic [31:0] CGRA_S_in_t6,
    input logic [31:0] CGRA_S_in_t7,
    output logic [31:0] CGRA_S_out_t0,
    output logic [31:0] CGRA_S_out_t1,
    output logic [31:0] CGRA_S_out_t2,
    output logic [31:0] CGRA_S_out_t3,
    output logic [31:0] CGRA_S_out_t4,
    output logic [31:0] CGRA_S_out_t5,
    output logic [31:0] CGRA_S_out_t6,
    output logic [31:0] CGRA_S_out_t7,
    input logic  CGRA_S_in_p0,
    input logic CGRA_S_in_p1,
    input logic CGRA_S_in_p2,
    input logic CGRA_S_in_p3,
    input logic CGRA_S_in_p4,
    input logic CGRA_S_in_p5,
    input logic CGRA_S_in_p6,
    input logic CGRA_S_in_p7,
    output logic CGRA_S_out_p0,
    output logic CGRA_S_out_p1,
    output logic CGRA_S_out_p2,
    output logic CGRA_S_out_p3,
    output logic CGRA_S_out_p4,
    output logic CGRA_S_out_p5,
    output logic CGRA_S_out_p6,
    output logic CGRA_S_out_p7,

    //West port
    input logic [31:0] CGRA_W_in_t0,
    input logic [31:0] CGRA_W_in_t1,
    input logic [31:0] CGRA_W_in_t2,
    input logic [31:0] CGRA_W_in_t3,
    input logic [31:0] CGRA_W_in_t4,
    input logic [31:0] CGRA_W_in_t5,
    input logic [31:0] CGRA_W_in_t6,
    input logic [31:0] CGRA_W_in_t7,
    output logic [31:0] CGRA_W_out_t0,
    output logic [31:0] CGRA_W_out_t1,
    output logic [31:0] CGRA_W_out_t2,
    output logic [31:0] CGRA_W_out_t3,
    output logic [31:0] CGRA_W_out_t4,
    output logic [31:0] CGRA_W_out_t5,
    output logic [31:0] CGRA_W_out_t6,
    output logic [31:0] CGRA_W_out_t7,
    input logic  CGRA_W_in_p0,
    input logic CGRA_W_in_p1,
    input logic CGRA_W_in_p2,
    input logic CGRA_W_in_p3,
    input logic CGRA_W_in_p4,
    input logic CGRA_W_in_p5,
    input logic CGRA_W_in_p6,
    input logic CGRA_W_in_p7,
    output logic CGRA_W_out_p0,
    output logic CGRA_W_out_p1,
    output logic CGRA_W_out_p2,
    output logic CGRA_W_out_p3,
    output logic CGRA_W_out_p4,
    output logic CGRA_W_out_p5,
    output logic CGRA_W_out_p6,
    output logic CGRA_W_out_p7,

    //configuration
    input logic [156*16-1:0] cgra_cfg
);



    //North port
    logic [31:0] N_in_t0 [0:15];
    logic [31:0] N_in_t1 [0:15];
    logic [31:0] N_out_t0 [0:15];
    logic [31:0] N_out_t1 [0:15];
    logic [15:0] N_in_p0 ;
    logic [15:0] N_in_p1;
    logic [15:0] N_out_p0;
    logic [15:0] N_out_p1;

    //East port
    logic [31:0] E_in_t0 [0:15];
    logic [31:0] E_in_t1 [0:15];
    logic [31:0] E_out_t0 [0:15];
    logic [31:0] E_out_t1 [0:15];
    logic [15:0] E_in_p0;
    logic [15:0] E_in_p1;
    logic [15:0] E_out_p0;
    logic [15:0] E_out_p1;

    //South port
    logic [31:0] S_in_t0 [0:15];
    logic [31:0] S_in_t1 [0:15];
    logic [31:0] S_out_t0 [0:15];
    logic [31:0] S_out_t1 [0:15];
    logic [15:0] S_in_p0;
    logic [15:0] S_in_p1;
    logic [15:0] S_out_p0;
    logic [15:0] S_out_p1;

    //West port
    logic [31:0] W_in_t0 [0:15];
    logic [31:0] W_in_t1 [0:15];
    logic [31:0] W_out_t0 [0:15];
    logic [31:0] W_out_t1 [0:15];
    logic [15:0] W_in_p0;
    logic [15:0] W_in_p1;
    logic [15:0] W_out_p0;
    logic [15:0] W_out_p1;



    //generate a row of 4 tiles
    genvar i, j;
    generate
        for(i = 0; i < 4; i = i + 1) begin : row_tile_gen
            for (j = 0; j < 4; j = j + 1) begin : col_tile_gen
                dice_tile tile_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    //North port
                    .N_in_t0(N_in_t0[i*4 + j]),
                    .N_in_t1(N_in_t1[i*4 + j]),
                    .N_out_t0(N_out_t0[i*4 + j]),
                    .N_out_t1(N_out_t1[i*4 + j]),
                    .N_in_p0(N_in_p0[i*4 + j]),
                    .N_in_p1(N_in_p1[i*4 + j]),
                    .N_out_p0(N_out_p0[i*4 + j]),
                    .N_out_p1(N_out_p1[i*4 + j]),
                    //East port
                    .E_in_t0(E_in_t0[i*4 + j]),
                    .E_in_t1(E_in_t1[i*4 + j]),
                    .E_out_t0(E_out_t0[i*4 + j]),
                    .E_out_t1(E_out_t1[i*4 + j]),
                    .E_in_p0(E_in_p0[i*4 + j]),
                    .E_in_p1(E_in_p1[i*4 + j]),
                    .E_out_p0(E_out_p0[i*4 + j]),
                    .E_out_p1(E_out_p1[i*4 + j]),
                    //South port
                    .S_in_t0(S_in_t0[i*4 + j]),
                    .S_in_t1(S_in_t1[i*4 + j]),
                    .S_out_t0(S_out_t0[i*4 + j]),
                    .S_out_t1(S_out_t1[i*4 + j]),
                    .S_in_p0(S_in_p0[i*4 + j]),
                    .S_in_p1(S_in_p1[i*4 + j]),
                    .S_out_p0(S_out_p0[i*4 + j]),
                    .S_out_p1(S_out_p1[i*4 + j]),
                    //West port
                    .W_in_t0(W_in_t0[i*4 + j]),
                    .W_in_t1(W_in_t1[i*4 + j]),
                    .W_out_t0(W_out_t0[i*4 + j]),
                    .W_out_t1(W_out_t1[i*4 + j]),
                    .W_in_p0(W_in_p0[i*4 + j]),
                    .W_in_p1(W_in_p1[i*4 + j]),
                    .W_out_p0(W_out_p0[i*4 + j]),
                    .W_out_p1(W_out_p1[i*4 + j]),

                    //static CFG
                    .tile_cfg(cgra_cfg[(i*4 + j)*156 +: 156])
                );

                //connect the tiles
                //N-S connection, edge case define outside the generate block
                if (i != 0) begin: north_south_connection
                    assign N_in_t0[i*4 + j] = S_out_t0[(i-1)*4 + j];
                    assign N_in_t1[i*4 + j] = S_out_t1[(i-1)*4 + j];
                    assign N_in_p0[i*4 + j] = S_out_p0[(i-1)*4 + j];
                    assign N_in_p1[i*4 + j] = S_out_p1[(i-1)*4 + j];
                end 

                //S - N connection, edge case define outside the generate block
                if (i != 3) begin: south_north_connection
                    assign S_in_t0[i*4 + j] = N_out_t0[(i+1)*4 + j];
                    assign S_in_t1[i*4 + j] = N_out_t1[(i+1)*4 + j];
                    assign S_in_p0[i*4 + j] = N_out_p0[(i+1)*4 + j]; 
                    assign S_in_p1[i*4 + j] = N_out_p1[(i+1)*4 + j];
                end

                //E - W connection, edge case define outside the generate block
                if (j != 3) begin: east_west_connection
                    assign E_in_t0[i*4 + j] = W_out_t0[i*4 + (j+1)];
                    assign E_in_t1[i*4 + j] = W_out_t1[i*4 + (j+1)];
                    assign E_in_p0[i*4 + j] = W_out_p0[i*4 + (j+1)];
                    assign E_in_p1[i*4 + j] = W_out_p1[i*4 + (j+1)];
                end

                //W - E connection, edge case define outside the generate block
                if (j != 0) begin: west_east_connection
                    assign W_in_t0[i*4 + j] = E_out_t0[i*4 + (j-1)];
                    assign W_in_t1[i*4 + j] = E_out_t1[i*4 + (j-1)];
                    assign W_in_p0[i*4 + j] = E_out_p0[i*4 + (j-1)];
                    assign W_in_p1[i*4 + j] = E_out_p1[i*4 + (j-1)];
                end
            end
        end
    endgenerate


    //connect the edge tiles to the CGRA ports
    //North edge
    assign N_in_t0[0] = CGRA_N_in_t0;
    assign N_in_t1[0] = CGRA_N_in_t1;
    assign N_in_t0[1] = CGRA_N_in_t2;
    assign N_in_t1[1] = CGRA_N_in_t3;
    assign N_in_t0[2] = CGRA_N_in_t4;
    assign N_in_t1[2] = CGRA_N_in_t5;
    assign N_in_t0[3] = CGRA_N_in_t6;
    assign N_in_t1[3] = CGRA_N_in_t7;
    assign N_in_p0[0] = CGRA_N_in_p0;
    assign N_in_p1[0] = CGRA_N_in_p1;
    assign N_in_p0[1] = CGRA_N_in_p2;
    assign N_in_p1[1] = CGRA_N_in_p3;
    assign N_in_p0[2] = CGRA_N_in_p4;
    assign N_in_p1[2] = CGRA_N_in_p5;
    assign N_in_p0[3] = CGRA_N_in_p6;
    assign N_in_p1[3] = CGRA_N_in_p7;   


    assign CGRA_N_out_t0 = N_out_t0[0];
    assign CGRA_N_out_t1 = N_out_t1[0];
    assign CGRA_N_out_t2 = N_out_t0[1];
    assign CGRA_N_out_t3 = N_out_t1[1];
    assign CGRA_N_out_t4 = N_out_t0[2];
    assign CGRA_N_out_t5 = N_out_t1[2];
    assign CGRA_N_out_t6 = N_out_t0[3];
    assign CGRA_N_out_t7 = N_out_t1[3];
    assign CGRA_N_out_p0 = N_out_p0[0];
    assign CGRA_N_out_p1 = N_out_p1[0];
    assign CGRA_N_out_p2 = N_out_p0[1];
    assign CGRA_N_out_p3 = N_out_p1[1];
    assign CGRA_N_out_p4 = N_out_p0[2];
    assign CGRA_N_out_p5 = N_out_p1[2];
    assign CGRA_N_out_p6 = N_out_p0[3];
    assign CGRA_N_out_p7 = N_out_p1[3];

    //South edge
    assign S_in_t0[12] = CGRA_S_in_t0;
    assign S_in_t1[12] = CGRA_S_in_t1;
    assign S_in_t0[13] = CGRA_S_in_t2;
    assign S_in_t1[13] = CGRA_S_in_t3;
    assign S_in_t0[14] = CGRA_S_in_t4;
    assign S_in_t1[14] = CGRA_S_in_t5;
    assign S_in_t0[15] = CGRA_S_in_t6;      
    assign S_in_t1[15] = CGRA_S_in_t7;
    assign S_in_p0[12] = CGRA_S_in_p0;
    assign S_in_p1[12] = CGRA_S_in_p1;
    assign S_in_p0[13] = CGRA_S_in_p2;
    assign S_in_p1[13] = CGRA_S_in_p3;
    assign S_in_p0[14] = CGRA_S_in_p4;
    assign S_in_p1[14] = CGRA_S_in_p5;
    assign S_in_p0[15] = CGRA_S_in_p6;
    assign S_in_p1[15] = CGRA_S_in_p7;  

    assign CGRA_S_out_t0 = S_out_t0[12];
    assign CGRA_S_out_t1 = S_out_t1[12];
    assign CGRA_S_out_t2 = S_out_t0[13];
    assign CGRA_S_out_t3 = S_out_t1[13];
    assign CGRA_S_out_t4 = S_out_t0[14];
    assign CGRA_S_out_t5 = S_out_t1[14];
    assign CGRA_S_out_t6 = S_out_t0[15];
    assign CGRA_S_out_t7 = S_out_t1[15];
    assign CGRA_S_out_p0 = S_out_p0[12];
    assign CGRA_S_out_p1 = S_out_p1[12];
    assign CGRA_S_out_p2 = S_out_p0[13];
    assign CGRA_S_out_p3 = S_out_p1[13];
    assign CGRA_S_out_p4 = S_out_p0[14];
    assign CGRA_S_out_p5 = S_out_p1[14];
    assign CGRA_S_out_p6 = S_out_p0[15];
    assign CGRA_S_out_p7 = S_out_p1[15];

    //East edge
    assign E_in_t0[3] = CGRA_E_in_t0;
    assign E_in_t1[3] = CGRA_E_in_t1;
    assign E_in_t0[7] = CGRA_E_in_t2;
    assign E_in_t1[7] = CGRA_E_in_t3;
    assign E_in_t0[11] = CGRA_E_in_t4;
    assign E_in_t1[11] = CGRA_E_in_t5;
    assign E_in_t0[15] = CGRA_E_in_t6;
    assign E_in_t1[15] = CGRA_E_in_t7;
    assign E_in_p0[3] = CGRA_E_in_p0;
    assign E_in_p1[3] = CGRA_E_in_p1;
    assign E_in_p0[7] = CGRA_E_in_p2;
    assign E_in_p1[7] = CGRA_E_in_p3;
    assign E_in_p0[11] = CGRA_E_in_p4;
    assign E_in_p1[11] = CGRA_E_in_p5;
    assign E_in_p0[15] = CGRA_E_in_p6;
    assign E_in_p1[15] = CGRA_E_in_p7;
    assign CGRA_E_out_t0 = E_out_t0[3];
    assign CGRA_E_out_t1 = E_out_t1[3];
    assign CGRA_E_out_t2 = E_out_t0[7];
    assign CGRA_E_out_t3 = E_out_t1[7];
    assign CGRA_E_out_t4 = E_out_t0[11];
    assign CGRA_E_out_t5 = E_out_t1[11];
    assign CGRA_E_out_t6 = E_out_t0[15];
    assign CGRA_E_out_t7 = E_out_t1[15];
    assign CGRA_E_out_p0 = E_out_p0[3];
    assign CGRA_E_out_p1 = E_out_p1[3];
    assign CGRA_E_out_p2 = E_out_p0[7];
    assign CGRA_E_out_p3 = E_out_p1[7];
    assign CGRA_E_out_p4 = E_out_p0[11];
    assign CGRA_E_out_p5 = E_out_p1[11];
    assign CGRA_E_out_p6 = E_out_p0[15];
    assign CGRA_E_out_p7 = E_out_p1[15];   

    //West edge
    assign W_in_t0[0] = CGRA_W_in_t0;
    assign W_in_t1[0] = CGRA_W_in_t1;
    assign W_in_t0[4] = CGRA_W_in_t2;
    assign W_in_t1[4] = CGRA_W_in_t3;
    assign W_in_t0[8] = CGRA_W_in_t4;
    assign W_in_t1[8] = CGRA_W_in_t5;
    assign W_in_t0[12] = CGRA_W_in_t6;
    assign W_in_t1[12] = CGRA_W_in_t7;
    assign W_in_p0[0] = CGRA_W_in_p0;
    assign W_in_p1[0] = CGRA_W_in_p1;
    assign W_in_p0[4] = CGRA_W_in_p2;
    assign W_in_p1[4] = CGRA_W_in_p3;
    assign W_in_p0[8] = CGRA_W_in_p4;
    assign W_in_p1[8] = CGRA_W_in_p5;
    assign W_in_p0[12] = CGRA_W_in_p6;
    assign W_in_p1[12] = CGRA_W_in_p7;
    assign CGRA_W_out_t0 = W_out_t0[0];
    assign CGRA_W_out_t1 = W_out_t1[0];
    assign CGRA_W_out_t2 = W_out_t0[4];
    assign CGRA_W_out_t3 = W_out_t1[4];
    assign CGRA_W_out_t4 = W_out_t0[8];
    assign CGRA_W_out_t5 = W_out_t1[8];
    assign CGRA_W_out_t6 = W_out_t0[12];
    assign CGRA_W_out_t7 = W_out_t1[12];
    assign CGRA_W_out_p0 = W_out_p0[0];
    assign CGRA_W_out_p1 = W_out_p1[0];
    assign CGRA_W_out_p2 = W_out_p0[4];
    assign CGRA_W_out_p3 = W_out_p1[4];
    assign CGRA_W_out_p4 = W_out_p0[8];
    assign CGRA_W_out_p5 = W_out_p1[8];
    assign CGRA_W_out_p6 = W_out_p0[12];
    assign CGRA_W_out_p7 = W_out_p1[12];
endmodule