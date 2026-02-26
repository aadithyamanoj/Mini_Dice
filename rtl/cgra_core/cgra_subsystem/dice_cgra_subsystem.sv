module dice_cgra_subsystem #(
    parameter int NUM_CGRA_IO = 32,
    parameter int DATA_WIDTH = 32,
    parameter int NUM_TID = 512,
    parameter int TID_WIDTH = $clog2(NUM_TID),
    parameter int MAX_CTA_ID = 65535,
    parameter int CTA_ID_WIDTH = $clog2(MAX_CTA_ID),
    parameter int RF_ADDR_WIDTH = $clog2(NUM_TID),
    parameter int MAX_IO_PIPE_STAGE = 8,
    parameter int MAX_CGRA_PIPE_STAGE = 32,
    parameter int CGRA_CFG_WIDTH = 16*156
)(
    input  logic                             clk,
    input  logic                             rst_n,
    input  logic                             clr,
    output logic                             done,

    // From Dispatcher
    input  logic [TID_WIDTH-1:0]          disp_tid,
    input  logic                          disp_valid,
    input  logic [TID_WIDTH-1:0]          tid_x,
    input  logic [TID_WIDTH-1:0]          tid_y,
    input  logic [TID_WIDTH-1:0]          tid_z,
    input  logic [TID_WIDTH-1:0]          ntid_x,
    input  logic [TID_WIDTH-1:0]          ntid_y,
    input  logic [TID_WIDTH-1:0]          ntid_z,
    input  logic [CTA_ID_WIDTH-1:0]          ctaid_x,
    input  logic [CTA_ID_WIDTH-1:0]          ctaid_y,
    input  logic [CTA_ID_WIDTH-1:0]          ctaid_z,
    input  logic [CTA_ID_WIDTH-1:0]          nctaid_x,
    input  logic [CTA_ID_WIDTH-1:0]          nctaid_y,
    input  logic [CTA_ID_WIDTH-1:0]          nctaid_z,
    // From metadata to control RF read/write enables
    // special reg
    input logic [NUM_CGRA_IO-1:0] spec_rd_enable,
    input logic [4*NUM_CGRA_IO-1:0] spec_rd_select,
    input logic [NUM_CGRA_IO*DATA_WIDTH-1:0] const_reg,
    // general purpose register file
    input logic [NUM_CGRA_IO-1:0]       rf_rd_en,
    input logic [NUM_CGRA_IO-1:0]       rf_wr_en,
    // predicate register file
    input logic [NUM_CGRA_IO-1:0]       prf_rd_en,
    input logic [NUM_CGRA_IO-1:0]       prf_wr_en,

    // Config
    // Latency control
    input  logic [NUM_CGRA_IO*$clog2(MAX_IO_PIPE_STAGE)-1:0] rf_latency_in_cgra,
    input  logic [NUM_CGRA_IO*$clog2(MAX_IO_PIPE_STAGE)-1:0] rf_latency_out_cgra,
    input  logic [NUM_CGRA_IO*$clog2(MAX_IO_PIPE_STAGE)-1:0] prf_latency_in_cgra,
    input  logic [NUM_CGRA_IO*$clog2(MAX_IO_PIPE_STAGE)-1:0] prf_latency_out_cgra,
    // RF address override
    input logic [NUM_CGRA_IO*RF_ADDR_WIDTH-1:0] rd_override_enable,
    input logic [NUM_CGRA_IO*RF_ADDR_WIDTH-1:0] rd_override_address,
    input logic [NUM_CGRA_IO*RF_ADDR_WIDTH-1:0] wr_override_enable,
    input logic [NUM_CGRA_IO*RF_ADDR_WIDTH-1:0] wr_override_address,
    // CGRA config
    input logic [$clog2(MAX_CGRA_PIPE_STAGE)-1:0] cgra_compute_latency,
    input logic [CGRA_CFG_WIDTH-1:0] cgra_cfg
);
    //-----------------------------------------------------------
    // Wires
    //-----------------------------------------------------------
    // CGRA I/O
    localparam int CGRA_IO_PER_EDGE = NUM_CGRA_IO / 4;

    logic [DATA_WIDTH-1:0] N_in_t[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] N_out_t[0:CGRA_IO_PER_EDGE-1];
    logic N_in_p[0:CGRA_IO_PER_EDGE-1];
    logic N_out_p[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] E_in_t[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] E_out_t[0:CGRA_IO_PER_EDGE-1];
    logic E_in_p[0:CGRA_IO_PER_EDGE-1];
    logic E_out_p[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] S_in_t[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] S_out_t[0:CGRA_IO_PER_EDGE-1];
    logic S_in_p[0:CGRA_IO_PER_EDGE-1];
    logic S_out_p[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] W_in_t[0:CGRA_IO_PER_EDGE-1];
    logic [DATA_WIDTH-1:0] W_out_t[0:CGRA_IO_PER_EDGE-1];
    logic W_in_p[0:CGRA_IO_PER_EDGE-1];
    logic W_out_p[0:CGRA_IO_PER_EDGE-1];

    //indexer
    logic [DATA_WIDTH-1:0] CGRA_in_t[0:NUM_CGRA_IO-1];
    logic [DATA_WIDTH-1:0] CGRA_out_t[0:NUM_CGRA_IO-1];
    logic [NUM_CGRA_IO-1:0] CGRA_in_p;
    logic [NUM_CGRA_IO-1:0] CGRA_out_p;
    logic [NUM_CGRA_IO-1:0] rf_rd_en_final;
    logic [NUM_CGRA_IO-1:0] prf_rd_en_final;
    assign rf_rd_en_final = rf_rd_en & {NUM_CGRA_IO{disp_valid}};
    assign prf_rd_en_final = prf_rd_en & {NUM_CGRA_IO{disp_valid}};

    // Reorganize CGRA I/O
    // CGRA port order:
    //                        N
    //                 0 1 2 3 4 5 6 7
    //              r8 r9 r10 r11 r12 r13 r14 r15
    //               8 9 10 11 12 13 14 15
    //    0  r0  0 --|--------------------|-- 16   r16   0    
    //    1  r1  1 --|                    |-- 17   r17   1
    //    2  r2  2 --|                    |-- 18   r18   2
    // W  3  r3  3 --|                    |-- 19   r19   3   E
    //    4  r4  4 --|                    |-- 20   r20  4
    //    5  r5  5 --|                    |-- 21   r21  5
    //    6  r6  6 --|                    |-- 22   r22  6  
    //    7  r7  7 --|--------------------|-- 23   r23  7      
    //              24 25 26 27 28 29 30 31
    //              r24 r25 r26 r27 r28 r29 r30 r31
    //                   0 1 2 3 4 5 6 7
    //                         S
    always_comb begin
        for (int i=0; i<CGRA_IO_PER_EDGE; i++) begin
            W_in_t[i] = CGRA_in_t[i];
            N_in_t[i] = CGRA_in_t[i+CGRA_IO_PER_EDGE];
            E_in_t[i] = CGRA_in_t[i+2*CGRA_IO_PER_EDGE];
            S_in_t[i] = CGRA_in_t[i+3*CGRA_IO_PER_EDGE];

            CGRA_out_t[i] = W_out_t[i];
            CGRA_out_t[i+CGRA_IO_PER_EDGE] = N_out_t[i];
            CGRA_out_t[i+2*CGRA_IO_PER_EDGE] = E_out_t[i];
            CGRA_out_t[i+3*CGRA_IO_PER_EDGE] = S_out_t[i];

            W_in_p[i] = CGRA_in_p[i];
            N_in_p[i] = CGRA_in_p[i+CGRA_IO_PER_EDGE];
            E_in_p[i] = CGRA_in_p[i+2*CGRA_IO_PER_EDGE];
            S_in_p[i] = CGRA_in_p[i+3*CGRA_IO_PER_EDGE];

            CGRA_out_p[i] = W_out_p[i];
            CGRA_out_p[i+CGRA_IO_PER_EDGE] = N_out_p[i];
            CGRA_out_p[i+2*CGRA_IO_PER_EDGE] = E_out_p[i];
            CGRA_out_p[i+3*CGRA_IO_PER_EDGE] = S_out_p[i];
        end
    end
    
    // cgra output tid and valid
    logic [$clog2(NUM_TID)-1:0] out_tid;
    logic out_valid;

    //-----------------------------------------------------------
    // TID Shift Register
    //-----------------------------------------------------------
    dice_cgra_tid_sr #(
      .TOTAL_TID(NUM_TID),
      .MAX_LATENCY(MAX_CGRA_PIPE_STAGE)
    ) u_tid_sr (
      .clk(clk),
      .rst_n(rst_n),
      .clr(clr),
      .latency(cgra_compute_latency), // Set appropriate latency
      .in_tid(disp_tid),
      .in_valid(disp_valid),
      .out_tid(out_tid),
      .out_valid(out_valid),
      .empty(done) //done when the pipe is empty
    );

    logic [DATA_WIDTH*NUM_CGRA_IO-1:0] rf_rd_data;
    logic [DATA_WIDTH*NUM_CGRA_IO-1:0] rf_wr_data;
    logic [NUM_CGRA_IO-1:0] rf_wr_enable_final;
    logic [NUM_CGRA_IO-1:0] rf_pred_in;

    logic [NUM_CGRA_IO-1:0] prf_rd_data;
    logic [NUM_CGRA_IO-1:0] prf_wr_data;
    logic [NUM_CGRA_IO-1:0] prf_wr_en_final;

    // mapping from CGRA ports to RF ports
    always_comb begin
        //overwrite CGRA ports with general purpose registers
        for (int i=0; i<NUM_CGRA_IO; i++) begin
            CGRA_in_t[i] = rf_rd_data[i*DATA_WIDTH +: DATA_WIDTH];
            rf_wr_data[i*DATA_WIDTH +: DATA_WIDTH] = CGRA_out_t[i];
        end

        //predicate register
        for (int i=0; i<NUM_CGRA_IO; i++) begin
            CGRA_in_p[i] = prf_rd_data[i];
            prf_wr_data[i] = CGRA_out_p[i];
            rf_pred_in[i] = CGRA_out_p[i]; //use the predicate output from CGRA at the same port location as the write-enable
        end
    end

    //a register write back must be enabled by (1) metadata (2) valid output tid (3) predicate signal true.
    always_comb begin
        for (int i=0; i<NUM_CGRA_IO; i++) begin
            rf_wr_enable_final[i] = rf_wr_en[i] & rf_pred_in[i] & out_valid;
            prf_wr_en_final[i] = prf_wr_en[i] & out_valid;
        end
    end
    //-----------------------------------------------------------

    dice_gprf_ctrl #(
      .NUM_PORTS(NUM_CGRA_IO),
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_TID(NUM_TID),
      .MAX_IO_PIPE_STAGE(MAX_IO_PIPE_STAGE)
    ) u_gprf_ctrl (
      .clk(clk),
      .rst_n(rst_n),
      .clr(clr),
      // read interface
      .rd_en(rf_rd_en_final),
      .rd_tid(disp_tid),
      .rd_data(rf_rd_data),
      //write interface
      .wr_en(rf_wr_enable_final),
      .wr_tid(out_tid),
      .wr_data(rf_wr_data),
      // RF address override
      .rd_addr_override_enable(rd_override_enable),
      .rd_addr_override_address(rd_override_address),
      .wr_addr_override_enable(wr_override_enable),
      .wr_addr_override_address(wr_override_address),
      // Latency control
      .input_latency(rf_latency_in_cgra),
      .output_latency(rf_latency_out_cgra),

      // gprf/special reg select
      .spec_rd_enable(spec_rd_enable),
      .spec_reg_sel(spec_rd_select),
      .const_reg(const_reg),
      //tid info
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
      .nctaid_z(nctaid_z) 
    );

    dice_pred_rf_ctrl #(
      .NUM_PORTS(NUM_CGRA_IO),
      .DATA_WIDTH(1),
      .NUM_TID(NUM_TID),
      .MAX_IO_PIPE_STAGE(MAX_IO_PIPE_STAGE)
    ) u_pred_rf_ctrl (
      .clk(clk),
      .rst_n(rst_n),
      .clr(clr),
      // read interface
      .rd_en(prf_rd_en_final),
      .rd_tid(disp_tid),
      .rd_data(prf_rd_data),
      //write interface
      .wr_en(prf_wr_en_final),
      .wr_tid(out_tid),
      .wr_data(prf_wr_data),
      // RF address override
      .rd_addr_override_enable('0),
      .rd_addr_override_address('0),
      .wr_addr_override_enable('0),
      .wr_addr_override_address('0),
      // Latency control
      .input_latency(prf_latency_in_cgra),
      .output_latency(prf_latency_out_cgra)
    );

    //-----------------------------------------------------------
    // CGRA
    //-----------------------------------------------------------
    dice_cgra u_cgra (
      .clk(clk),
      .rst_n(rst_n),
      // North I/O
      .CGRA_N_in_t0(N_in_t[0]), .CGRA_N_in_t1(N_in_t[1]),
      .CGRA_N_in_t2(N_in_t[2]), .CGRA_N_in_t3(N_in_t[3]),
      .CGRA_N_in_t4(N_in_t[4]), .CGRA_N_in_t5(N_in_t[5]),
      .CGRA_N_in_t6(N_in_t[6]), .CGRA_N_in_t7(N_in_t[7]),
      .CGRA_N_out_t0(N_out_t[0]), .CGRA_N_out_t1(N_out_t[1]),
      .CGRA_N_out_t2(N_out_t[2]), .CGRA_N_out_t3(N_out_t[3]),
      .CGRA_N_out_t4(N_out_t[4]), .CGRA_N_out_t5(N_out_t[5]),
      .CGRA_N_out_t6(N_out_t[6]), .CGRA_N_out_t7(N_out_t[7]),
      .CGRA_N_in_p0(N_in_p[0]), .CGRA_N_in_p1(N_in_p[1]),
      .CGRA_N_in_p2(N_in_p[2]), .CGRA_N_in_p3(N_in_p[3]),
      .CGRA_N_in_p4(N_in_p[4]), .CGRA_N_in_p5(N_in_p[5]),
      .CGRA_N_in_p6(N_in_p[6]), .CGRA_N_in_p7(N_in_p[7]),
      .CGRA_N_out_p0(N_out_p[0]), .CGRA_N_out_p1(N_out_p[1]),
      .CGRA_N_out_p2(N_out_p[2]), .CGRA_N_out_p3(N_out_p[3]),
      .CGRA_N_out_p4(N_out_p[4]), .CGRA_N_out_p5(N_out_p[5]),
      .CGRA_N_out_p6(N_out_p[6]), .CGRA_N_out_p7(N_out_p[7]),
      // East I/O
      .CGRA_E_in_t0(E_in_t[0]), .CGRA_E_in_t1(E_in_t[1]),
      .CGRA_E_in_t2(E_in_t[2]), .CGRA_E_in_t3(E_in_t[3]),
      .CGRA_E_in_t4(E_in_t[4]), .CGRA_E_in_t5(E_in_t[5]),
      .CGRA_E_in_t6(E_in_t[6]), .CGRA_E_in_t7(E_in_t[7]),
      .CGRA_E_out_t0(E_out_t[0]), .CGRA_E_out_t1(E_out_t[1]),
      .CGRA_E_out_t2(E_out_t[2]), .CGRA_E_out_t3(E_out_t[3]),
      .CGRA_E_out_t4(E_out_t[4]), .CGRA_E_out_t5(E_out_t[5]),
      .CGRA_E_out_t6(E_out_t[6]), .CGRA_E_out_t7(E_out_t[7]),
      .CGRA_E_in_p0(E_in_p[0]), .CGRA_E_in_p1(E_in_p[1]),
      .CGRA_E_in_p2(E_in_p[2]), .CGRA_E_in_p3(E_in_p[3]),
      .CGRA_E_in_p4(E_in_p[4]), .CGRA_E_in_p5(E_in_p[5]),
      .CGRA_E_in_p6(E_in_p[6]), .CGRA_E_in_p7(E_in_p[7]),
      .CGRA_E_out_p0(E_out_p[0]), .CGRA_E_out_p1(E_out_p[1]),
      .CGRA_E_out_p2(E_out_p[2]), .CGRA_E_out_p3(E_out_p[3]),
      .CGRA_E_out_p4(E_out_p[4]), .CGRA_E_out_p5(E_out_p[5]),
      .CGRA_E_out_p6(E_out_p[6]), .CGRA_E_out_p7(E_out_p[7]),
      // South I/O
      .CGRA_S_in_t0(S_in_t[0]), .CGRA_S_in_t1(S_in_t[1]),
      .CGRA_S_in_t2(S_in_t[2]), .CGRA_S_in_t3(S_in_t[3]),
      .CGRA_S_in_t4(S_in_t[4]), .CGRA_S_in_t5(S_in_t[5]),
      .CGRA_S_in_t6(S_in_t[6]), .CGRA_S_in_t7(S_in_t[7]),
      .CGRA_S_out_t0(S_out_t[0]), .CGRA_S_out_t1(S_out_t[1]),
      .CGRA_S_out_t2(S_out_t[2]), .CGRA_S_out_t3(S_out_t[3]),
      .CGRA_S_out_t4(S_out_t[4]), .CGRA_S_out_t5(S_out_t[5]),
      .CGRA_S_out_t6(S_out_t[6]), .CGRA_S_out_t7(S_out_t[7]),
      .CGRA_S_in_p0(S_in_p[0]), .CGRA_S_in_p1(S_in_p[1]),
      .CGRA_S_in_p2(S_in_p[2]), .CGRA_S_in_p3(S_in_p[3]),
      .CGRA_S_in_p4(S_in_p[4]), .CGRA_S_in_p5(S_in_p[5]),
      .CGRA_S_in_p6(S_in_p[6]), .CGRA_S_in_p7(S_in_p[7]),
      .CGRA_S_out_p0(S_out_p[0]), .CGRA_S_out_p1(S_out_p[1]),
      .CGRA_S_out_p2(S_out_p[2]), .CGRA_S_out_p3(S_out_p[3]),
      .CGRA_S_out_p4(S_out_p[4]), .CGRA_S_out_p5(S_out_p[5]),
      .CGRA_S_out_p6(S_out_p[6]), .CGRA_S_out_p7(S_out_p[7]),
      // West I/O
      .CGRA_W_in_t0(W_in_t[0]), .CGRA_W_in_t1(W_in_t[1]),
      .CGRA_W_in_t2(W_in_t[2]), .CGRA_W_in_t3(W_in_t[3]),
      .CGRA_W_in_t4(W_in_t[4]), .CGRA_W_in_t5(W_in_t[5]),
      .CGRA_W_in_t6(W_in_t[6]), .CGRA_W_in_t7(W_in_t[7]),
      .CGRA_W_out_t0(W_out_t[0]), .CGRA_W_out_t1(W_out_t[1]),
      .CGRA_W_out_t2(W_out_t[2]), .CGRA_W_out_t3(W_out_t[3]),
      .CGRA_W_out_t4(W_out_t[4]), .CGRA_W_out_t5(W_out_t[5]),
      .CGRA_W_out_t6(W_out_t[6]), .CGRA_W_out_t7(W_out_t[7]),
      .CGRA_W_in_p0(W_in_p[0]), .CGRA_W_in_p1(W_in_p[1]),
      .CGRA_W_in_p2(W_in_p[2]), .CGRA_W_in_p3(W_in_p[3]),
      .CGRA_W_in_p4(W_in_p[4]), .CGRA_W_in_p5(W_in_p[5]),
      .CGRA_W_in_p6(W_in_p[6]), .CGRA_W_in_p7(W_in_p[7]),
      .CGRA_W_out_p0(W_out_p[0]), .CGRA_W_out_p1(W_out_p[1]),
      .CGRA_W_out_p2(W_out_p[2]), .CGRA_W_out_p3(W_out_p[3]),
      .CGRA_W_out_p4(W_out_p[4]), .CGRA_W_out_p5(W_out_p[5]),
      .CGRA_W_out_p6(W_out_p[6]), .CGRA_W_out_p7(W_out_p[7]),
      // TID and Valid
      .cgra_cfg(cgra_cfg)
    );


endmodule