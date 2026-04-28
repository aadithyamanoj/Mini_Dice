module chip_top (
    inout wire [47:0] PAD,
    inout wire VDDPST,
    inout wire VSSPST,
    inout wire VDD,
    inout wire VSS
);

    // Pad control and data signals
    logic [47:0] I;       // Output data to PAD
    logic [47:0] C;       // Input data from PAD
    logic [47:0] DS;      // Drive strength control
    logic [47:0] OEN;     // Output enable (active-low)
    logic [47:0] PE;      // Pull-down enable
    logic [47:0] IE;      // Input enable

    // Instantiate pad ring
    pad_ring_64 u_pad_ring (
        .I      (I),
        .DS     (DS),
        .OEN    (OEN),
        .PE     (PE),
        .IE     (IE),
        .C      (C), 
        .PAD    (PAD)
        ,.VDDPST (VDDPST),
        .VSSPST (VSSPST),
        .VDD    (VDD),
        .VSS    (VSS)
    );



    // ------------------------------------------------------------------------
    // Mini_Dice pad map
    // ------------------------------------------------------------------------
    localparam int CHANNEL_WIDTH = 8;

    localparam int CORE_CLK_PAD             = 0;
    localparam int CORE_RST_PAD             = 1;
    localparam int IO_MASTER_CLK_PAD        = 2;
    localparam int UPSTREAM_LINK_RST_PAD    = 3;
    localparam int ASYNC_TOKEN_RST_PAD      = 4;
    localparam int TOKEN_CLK_PAD            = 5;
    localparam int DOWNSTREAM_LINK_RST_PAD  = 6;
    localparam int DOWNSTREAM_CLK_PAD       = 7;
    localparam int DOWNSTREAM_DATA_PAD_BASE = 8;   // PAD[15:8]
    localparam int DOWNSTREAM_VALID_PAD     = 16;

    localparam int UPSTREAM_CLK_PAD         = 17;
    localparam int UPSTREAM_DATA_PAD_BASE   = 18;  // PAD[25:18]
    localparam int UPSTREAM_VALID_PAD       = 26;
    localparam int DOWNSTREAM_TOKEN_PAD     = 27;

    wire core_clk;
    wire core_rst;
    wire io_master_clk;
    wire upstream_io_link_reset;
    wire async_token_reset;
    wire token_clk;
    wire downstream_io_link_reset;
    wire downstream_io_clk;
    wire [CHANNEL_WIDTH-1:0] downstream_io_data;
    wire downstream_io_valid;

    wire upstream_io_clk_r;
    wire [CHANNEL_WIDTH-1:0] upstream_io_data_r;
    wire upstream_io_valid_r;
    wire downstream_core_token_r;

    assign core_clk                 = C[CORE_CLK_PAD];
    assign core_rst                 = C[CORE_RST_PAD];
    assign io_master_clk            = C[IO_MASTER_CLK_PAD];
    assign upstream_io_link_reset   = C[UPSTREAM_LINK_RST_PAD];
    assign async_token_reset        = C[ASYNC_TOKEN_RST_PAD];
    assign token_clk                = C[TOKEN_CLK_PAD];
    assign downstream_io_link_reset = C[DOWNSTREAM_LINK_RST_PAD];
    assign downstream_io_clk        = C[DOWNSTREAM_CLK_PAD];
    assign downstream_io_valid      = C[DOWNSTREAM_VALID_PAD];

    for (genvar i = 0; i < CHANNEL_WIDTH; i++) begin : gen_downstream_data
        assign downstream_io_data[i] = C[DOWNSTREAM_DATA_PAD_BASE+i];
    end

    // Default pad configuration
    always_comb begin
        // Default: All pads as inputs, high-Z, no pull-down, low drive strength
        IE    = 48'h0;               // Disable input by default
        OEN   = 48'hffff_ffff_ffff;  // High-Z (output disabled)
        PE    = 48'h0;               // No pull-down
        DS    = 48'h0;               // Low drive strength
        //need to tie low for all other I, otherwise it will cause floating gates
        I     = 48'h0; // Disable input for PAD[6]

        // Mini_Dice input pads.
        IE[CORE_CLK_PAD]            = 1'b1;
        IE[CORE_RST_PAD]            = 1'b1;
        IE[IO_MASTER_CLK_PAD]       = 1'b1;
        IE[UPSTREAM_LINK_RST_PAD]   = 1'b1;
        IE[ASYNC_TOKEN_RST_PAD]     = 1'b1;
        IE[TOKEN_CLK_PAD]           = 1'b1;
        IE[DOWNSTREAM_LINK_RST_PAD] = 1'b1;
        IE[DOWNSTREAM_CLK_PAD]      = 1'b1;
        IE[DOWNSTREAM_VALID_PAD]    = 1'b1;

        for (int i = 0; i < CHANNEL_WIDTH; i++) begin
            IE[DOWNSTREAM_DATA_PAD_BASE+i]  = 1'b1;
            OEN[DOWNSTREAM_DATA_PAD_BASE+i] = 1'b1;
        end

        // Mini_Dice output pads.
        IE[UPSTREAM_CLK_PAD]       = 1'b0;
        OEN[UPSTREAM_CLK_PAD]      = 1'b0;
        I[UPSTREAM_CLK_PAD]        = upstream_io_clk_r;

        for (int i = 0; i < CHANNEL_WIDTH; i++) begin
            IE[UPSTREAM_DATA_PAD_BASE+i]  = 1'b0;
            OEN[UPSTREAM_DATA_PAD_BASE+i] = 1'b0;
            I[UPSTREAM_DATA_PAD_BASE+i]   = upstream_io_data_r[i];
        end

        IE[UPSTREAM_VALID_PAD]   = 1'b0;
        OEN[UPSTREAM_VALID_PAD]  = 1'b0;
        I[UPSTREAM_VALID_PAD]    = upstream_io_valid_r;

        IE[DOWNSTREAM_TOKEN_PAD]  = 1'b0;
        OEN[DOWNSTREAM_TOKEN_PAD] = 1'b0;
        I[DOWNSTREAM_TOKEN_PAD]   = downstream_core_token_r;
    end

    mini_dice_top #(
        .CHANNEL_WIDTH(CHANNEL_WIDTH)
    ) u_mini_dice_top (
        .clk_i(core_clk),
        .rst_i(core_rst),

        .io_master_clk_i(io_master_clk),
        .upstream_io_link_reset_i(upstream_io_link_reset),
        .async_token_reset_i(async_token_reset),
        .token_clk_i(token_clk),
        .upstream_io_clk_r_o(upstream_io_clk_r),
        .upstream_io_data_r_o(upstream_io_data_r),
        .upstream_io_valid_r_o(upstream_io_valid_r),

        .downstream_io_link_reset_i(downstream_io_link_reset),
        .downstream_io_clk_i(downstream_io_clk),
        .downstream_io_data_i(downstream_io_data),
        .downstream_io_valid_i(downstream_io_valid),
        .downstream_core_token_r_o(downstream_core_token_r)
    );
endmodule

module pad_ring_64 (
    input  wire [47:0] I,      // Output data to PAD
    input  wire [47:0] DS,     // Drive strength control
    input  wire [47:0] OEN,    // Output enable (active-low)
    input  wire [47:0] PE,     // Pull-down enable
    input  wire [47:0] IE,     // Input enable
    output wire [47:0] C,      // Input data from PAD
    inout  wire [47:0] PAD     // Bidirectional PAD pins
    ,inout wire VDDPST,
    inout wire VSSPST,
    inout wire VDD,
    inout wire VSS
);

    PVDD2POC Pad_VDDPST_top(.VDDPST(VDDPST));
	PVSS2CDG Pad_VSSPST_top(.VSSPST(VSSPST));
	PVDD1CDG Pad_VDD_top(.VDD(VDD));
	PVSS1CDG Pad_VSS_top(.VSS(VSS));

	PVDD2CDG Pad_VDDPST_bottom(.VDDPST(VDDPST));
	PVSS2CDG Pad_VSSPST_bottom(.VSSPST(VSSPST));
	PVDD1CDG Pad_VDD_bottom(.VDD(VDD));
	PVSS1CDG Pad_VSS_bottom(.VSS(VSS));

	PVDD2CDG Pad_VDDPST_left(.VDDPST(VDDPST));
	PVSS2CDG Pad_VSSPST_left(.VSSPST(VSSPST));
	PVDD1CDG Pad_VDD_left(.VDD(VDD));
	PVSS1CDG Pad_VSS_left(.VSS(VSS));

	PVDD2CDG Pad_VDDPST_right(.VDDPST(VDDPST));
	PVSS2CDG Pad_VSSPST_right(.VSSPST(VSSPST));
	PVDD1CDG Pad_VDD_right(.VDD(VDD));
	PVSS1CDG Pad_VSS_right(.VSS(VSS));

    // Pad cell instantiation
    genvar i;
    generate
        for (i = 0; i < 48; i++) begin: Pad_IO
            PDDW1216CDG in_out (
                .C    (C[i]),       // Input data from PAD
                .DS   (DS[i]),      // Drive strength
                .OEN  (OEN[i]),     // Output enable (active-low)
                .PAD  (PAD[i]),     // Bidirectional PAD pin
                .I    (I[i]),       // Output data to PAD
                .PE   (PE[i]),      // Pull-down enable
                .IE   (IE[i])       // Input enable
            );
        end
    endgenerate

endmodule
