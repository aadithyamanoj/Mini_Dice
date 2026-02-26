module dice_tile (
    input logic clk,
    input logic rst_n,
    //North port
    input logic [31:0] N_in_t0,
    input logic [31:0] N_in_t1,
    output logic [31:0] N_out_t0,
    output logic [31:0] N_out_t1,
    input logic  N_in_p0,
    input logic N_in_p1,
    output logic N_out_p0,
    output logic N_out_p1,

    //East port
    input logic [31:0] E_in_t0,
    input logic [31:0] E_in_t1,
    output logic [31:0] E_out_t0,
    output logic [31:0] E_out_t1,
    input logic  E_in_p0,
    input logic E_in_p1,
    output logic E_out_p0,
    output logic E_out_p1,

    //South port
    input logic [31:0] S_in_t0,
    input logic [31:0] S_in_t1,
    output logic [31:0] S_out_t0,
    output logic [31:0] S_out_t1,
    input logic  S_in_p0,
    input logic S_in_p1,
    output logic S_out_p0,
    output logic S_out_p1,

    //West port
    input logic [31:0] W_in_t0,
    input logic [31:0] W_in_t1,
    output logic [31:0] W_out_t0,
    output logic [31:0] W_out_t1,
    input logic  W_in_p0,
    input logic W_in_p1,
    output logic W_out_p0,
    output logic W_out_p1,


    //static CFG
    input logic [155:0] tile_cfg
);

    logic dff_input_mode;
    logic dff_output_mode;
    logic [31:0] pe_out_t0;
    logic [31:0] pe_out_t1;
    logic pe_out_p0;
    logic [31:0] L_out_t0;
    logic [31:0] L_out_t1;
    logic [31:0] L_out_t2;
    logic [31:0] L_out_t3;
    logic L_out_p0;
    logic L_out_p1;
    logic L_out_p2;
    //initialize the router
    //total cfg bits:
    //2_1 router: 11 + 11*4 = 55
        // 11 bits for registered_mode
        // 11*4 bits for sel
    //2_32 router: 8 + 12 + 4 * 12 = 68
        // 8 bits for overload_en
        // 12*4 bits for registered_mode
        // 4*12 bits for sel
    //PE: opcode 32 + out_sel 1 = 33
        // 32 bits for opcode
        // 1 bit for out_sel
    //total = 156
    dice_2_1_router u_pred_router (
        .clk(clk),
        .rst_n(rst_n),
        .registered_mode_N_t0(tile_cfg[155]),
        .registered_mode_N_t1(tile_cfg[150]),
        .registered_mode_E_t0(tile_cfg[145]),
        .registered_mode_E_t1(tile_cfg[140]),
        .registered_mode_S_t0(tile_cfg[135]),
        .registered_mode_S_t1(tile_cfg[130]),
        .registered_mode_W_t0(tile_cfg[125]),
        .registered_mode_W_t1(tile_cfg[120]),
        .registered_mode_L_t0(tile_cfg[115]),
        .registered_mode_L_t1(tile_cfg[110]),
        .registered_mode_L_t2(tile_cfg[105]),
        .N_in_t0(N_in_p0),
        .N_in_t1(N_in_p1),
        .E_in_t0(E_in_p0),
        .E_in_t1(E_in_p1),
        .S_in_t0(S_in_p0),
        .S_in_t1(S_in_p1),
        .W_in_t0(W_in_p0),
        .W_in_t1(W_in_p1),
        .L_in_t0(pe_out_p0),
        .N_out_t0(N_out_p0),
        .N_out_t1(N_out_p1),
        .E_out_t0(E_out_p0),
        .E_out_t1(E_out_p1),
        .S_out_t0(S_out_p0),
        .S_out_t1(S_out_p1),
        .W_out_t0(W_out_p0),
        .W_out_t1(W_out_p1),
        .L_out_t0(L_out_p0),
        .L_out_t1(L_out_p1),
        .L_out_t2(L_out_p2),
        .sel_N_t0(tile_cfg[154:151]),
        .sel_N_t1(tile_cfg[149:146]),
        .sel_E_t0(tile_cfg[144:141]),
        .sel_E_t1(tile_cfg[139:136]),
        .sel_S_t0(tile_cfg[134:131]),
        .sel_S_t1(tile_cfg[129:126]),
        .sel_W_t0(tile_cfg[124:121]),
        .sel_W_t1(tile_cfg[119:116]),
        .sel_L_t0(tile_cfg[114:111]),
        .sel_L_t1(tile_cfg[109:106]),
        .sel_L_t2(tile_cfg[104:101])
    );

    dice_2_32_router u_data_router (
        .clk(clk),
        .rst_n(rst_n),
        .overload_en_N_t0(tile_cfg[100]),
        .overload_ctrl_N_t0(L_out_p2),
        .overload_en_N_t1(tile_cfg[94]),
        .overload_ctrl_N_t1(L_out_p2),
        .overload_en_E_t0(tile_cfg[88]),
        .overload_ctrl_E_t0(L_out_p2),
        .overload_en_E_t1(tile_cfg[82]),
        .overload_ctrl_E_t1(L_out_p2),
        .overload_en_S_t0(tile_cfg[76]),
        .overload_ctrl_S_t0(L_out_p2),
        .overload_en_S_t1(tile_cfg[70]),
        .overload_ctrl_S_t1(L_out_p2),
        .overload_en_W_t0(tile_cfg[64]),
        .overload_ctrl_W_t0(L_out_p2),
        .overload_en_W_t1(tile_cfg[58]),
        .overload_ctrl_W_t1(L_out_p2),
        .overload_en_L_t0('0),
        .overload_ctrl_L_t0('0),
        .overload_en_L_t1('0),
        .overload_ctrl_L_t1('0),
        .overload_en_L_t2('0),
        .overload_ctrl_L_t2('0),
        .overload_en_L_t3('0),
        .overload_ctrl_L_t3('0),
        .registered_mode_N_t0(tile_cfg[99]),
        .registered_mode_N_t1(tile_cfg[93]),
        .registered_mode_E_t0(tile_cfg[87]),
        .registered_mode_E_t1(tile_cfg[81]),
        .registered_mode_S_t0(tile_cfg[75]),
        .registered_mode_S_t1(tile_cfg[69]),
        .registered_mode_W_t0(tile_cfg[63]),
        .registered_mode_W_t1(tile_cfg[57]),
        .registered_mode_L_t0(tile_cfg[52]),
        .registered_mode_L_t1(tile_cfg[47]),
        .registered_mode_L_t2(tile_cfg[42]),
        .registered_mode_L_t3(tile_cfg[37]),
        .N_in_t0(N_in_t0),
        .N_in_t1(N_in_t1),
        .E_in_t0(E_in_t0),
        .E_in_t1(E_in_t1),
        .S_in_t0(S_in_t0),
        .S_in_t1(S_in_t1),
        .W_in_t0(W_in_t0),
        .W_in_t1(W_in_t1),
        .L_in_t0(pe_out_t0),
        .L_in_t1(pe_out_t1),
        .N_out_t0(N_out_t0),
        .N_out_t1(N_out_t1),
        .E_out_t0(E_out_t0),
        .E_out_t1(E_out_t1),
        .S_out_t0(S_out_t0),
        .S_out_t1(S_out_t1),
        .W_out_t0(W_out_t0),
        .W_out_t1(W_out_t1),
        .L_out_t0(L_out_t0),
        .L_out_t1(L_out_t1),
        .L_out_t2(L_out_t2),
        .L_out_t3(L_out_t3),
        .sel_N_t0(tile_cfg[98:95]),
        .sel_N_t1(tile_cfg[92:89]),
        .sel_E_t0(tile_cfg[86:83]),
        .sel_E_t1(tile_cfg[80:77]),
        .sel_S_t0(tile_cfg[74:71]),
        .sel_S_t1(tile_cfg[68:65]),
        .sel_W_t0(tile_cfg[62:59]),
        .sel_W_t1(tile_cfg[56:53]),
        .sel_L_t0(tile_cfg[51:48]),
        .sel_L_t1(tile_cfg[46:43]),
        .sel_L_t2(tile_cfg[41:38]),
        .sel_L_t3(tile_cfg[36:33])
    );
    //initialize the PE
    dice_pe pe_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pe_in0(L_out_t0),
        .pe_in1(L_out_t1),
        .pe_in2(L_out_t2),
        .pe_in3(L_out_p0),
        .dff_in(L_out_t3),
        .pe_out_t0(pe_out_t0),
        .pe_out_t1(pe_out_t1),
        .pe_out_p0(pe_out_p0),

        //static CFG
        .opcode(tile_cfg[32:1]),
        .out_sel(tile_cfg[0]),

        //dynamic CFG
        .dff_input_mode(L_out_p0),
        .dff_latch_enable(L_out_p1)
    );


endmodule
