`ifndef DEIMPORTS
`define DEIMPORTS
`include "dice_define.vh"
package DE_pkg;


// =========================================================
// Dispatcher architecture constants
// =========================================================
parameter int NUM_CREDITS      = 100;

parameter int NUM_SCOREBOARDS  = 1;
parameter int NUM_LANES        = 1;
parameter int NUM_MEM_PORTS    = `DICE_CGRA_MEM_PORTS;
parameter int CHUNK_SIZE       = `DICE_NUM_MAX_THREADS_PER_CORE / NUM_SCOREBOARDS;
parameter int CHUNK_ADDR_WIDTH = (NUM_SCOREBOARDS == 1) ? 1 : $clog2(NUM_SCOREBOARDS);
parameter int LANE_SIZE        = CHUNK_SIZE / NUM_LANES;
parameter int LANE_WIDTH       = $clog2(LANE_SIZE);

parameter int DICE_REG_DATA_WIDTH = 16;
parameter int CACHE_LINE_SIZE = 32;
parameter int NUMBER_OF_MAX_COALESCED_COMMANDS = CACHE_LINE_SIZE/4;
parameter int TID_BITMAP_WIDTH = NUMBER_OF_MAX_COALESCED_COMMANDS;
parameter int BASE_ADDRESS_OFFSET = $clog2(CACHE_LINE_SIZE);
parameter int DICE_NUM_REGS = `DICE_GPR_NUM;
parameter int DICE_NUM_CONST = `DICE_CR_NUM;
parameter int DICE_NUM_PRED = `DICE_PR_NUM;
parameter int DICE_NUM_BANKS = DICE_NUM_REGS;
parameter int DICE_REGS_PER_BANK = `DICE_NUM_MAX_THREADS_PER_CORE;
parameter int DICE_TOTAL_REGS = DICE_NUM_REGS + DICE_NUM_CONST + DICE_NUM_PRED;
parameter int DICE_REG_ADDR_WIDTH = $clog2(DICE_TOTAL_REGS);
parameter int LDST_BUF_DEPTH = 8;
localparam int EBLOCK_ID_W = $clog2(`DICE_NUM_RETIRE_TABLE_ENTRIES + 4);
typedef struct packed {
    logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic [EBLOCK_ID_W-1:0] e_block_id;
    logic [DICE_REG_DATA_WIDTH-1:0] data;
    logic [DICE_TOTAL_REGS-1:0] wr_bitmap;
} cache_wr_cmd;

typedef struct packed {
    // all banks
    logic [(DICE_REG_DATA_WIDTH*DICE_NUM_BANKS)-1:0] data;
    logic [DICE_NUM_BANKS-1:0] mask;
    logic [($clog2(`DICE_NUM_MAX_THREADS_PER_CORE)*DICE_NUM_BANKS)-1:0] tid;
    logic [(EBLOCK_ID_W*DICE_NUM_BANKS)-1:0] e_block_id;
} ldst_wr_cmd;

typedef struct packed {
    // single bank
    logic [DICE_REG_DATA_WIDTH-1:0] data;
    logic mask;
    logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic [EBLOCK_ID_W-1:0] e_block_id;
} reg_wr_cmd;

// Const and predicate register write command (not per-bank)
typedef struct packed {
    logic [EBLOCK_ID_W-1:0] e_block_id;
    logic [DICE_NUM_CONST*DICE_REG_DATA_WIDTH-1:0] const_data;
    logic [DICE_NUM_CONST-1:0] const_mask;
    logic [DICE_NUM_PRED-1:0] pred_data;
    logic [DICE_NUM_PRED-1:0] pred_mask;
} special_regs_cmd;


function automatic reg_wr_cmd [DICE_NUM_BANKS-1:0] unpack_ldsr_wr
(
    input ldst_wr_cmd cmd
); 
    reg_wr_cmd [DICE_NUM_BANKS-1:0] wr_cmd;
    for (int i = 0; i < DICE_NUM_BANKS; i++) begin
        wr_cmd[i].data = cmd.data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH];
        wr_cmd[i].mask = cmd.mask[i];
        wr_cmd[i].tid = cmd.tid[i*$clog2(`DICE_NUM_MAX_THREADS_PER_CORE) +: $clog2(`DICE_NUM_MAX_THREADS_PER_CORE)];
        wr_cmd[i].e_block_id = cmd.e_block_id[i*EBLOCK_ID_W +: EBLOCK_ID_W];
    end
    return wr_cmd;
endfunction


function automatic ldst_wr_cmd assemble_ldst_wr
(
    input cache_wr_cmd cmd
);
    ldst_wr_cmd wr_data;
    wr_data = '0;
    for (int i = 0; i < DICE_NUM_BANKS; i++) begin
        wr_data.data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] = cmd.data;
        wr_data.mask[i] = cmd.wr_bitmap[i];
        wr_data.tid[i*$clog2(`DICE_NUM_MAX_THREADS_PER_CORE) +: $clog2(`DICE_NUM_MAX_THREADS_PER_CORE)] = cmd.tid;
        wr_data.e_block_id[i*EBLOCK_ID_W +: EBLOCK_ID_W] = cmd.e_block_id;
    end
    return wr_data;
endfunction

function automatic special_regs_cmd assemble_special_wr
(
    input cache_wr_cmd cmd
);
    special_regs_cmd wr_data;
    wr_data = '0;
    wr_data.e_block_id = cmd.e_block_id;

    for (int i = 0; i < DICE_NUM_CONST; i++) begin
        wr_data.const_mask[i] = cmd.wr_bitmap[DICE_NUM_BANKS + i];
        wr_data.const_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] = cmd.data;
    end

    for (int i = 0; i < DICE_NUM_PRED; i++) begin
        wr_data.pred_mask[i] = cmd.wr_bitmap[DICE_NUM_BANKS + DICE_NUM_CONST + i];
        wr_data.pred_data[i] = cmd.data[0];
    end

    return wr_data;
endfunction

typedef struct packed {
    logic[$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic[$clog2(DICE_NUM_REGS)-1:0] rs;
    logic      re;
} reg_rd_cmd;

function automatic logic [NUM_MEM_PORTS-1:0] gen_mem_port_valid
(
    input logic [NUM_MEM_PORTS-1:0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs,
    input logic [$clog2(NUM_MEM_PORTS+1)-1:0]                num_stores
);
    logic [NUM_MEM_PORTS-1:0] valid_vec;
    valid_vec = '0;

    for (int i = 0; i < NUM_MEM_PORTS; i++) begin
        valid_vec[i] = (i < num_stores) || (ld_dest_regs[i] != DICE_REG_ADDR_WIDTH'(31));
    end

    return valid_vec;
endfunction

function automatic logic [NUM_MEM_PORTS-1:0] gen_mem_port_op
(
    input logic [NUM_MEM_PORTS-1:0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs,
    input logic [$clog2(NUM_MEM_PORTS+1)-1:0]                num_stores
);
    logic [NUM_MEM_PORTS-1:0] op_vec;
    op_vec = '0;

    for (int i = 0; i < NUM_MEM_PORTS; i++) begin
        op_vec[i] = (i < num_stores);
    end

    return op_vec;
endfunction

function automatic logic [$clog2(NUM_MEM_PORTS+1)-1:0] gen_num_loads
(
    input logic [NUM_MEM_PORTS-1:0][DICE_REG_ADDR_WIDTH-1:0] ld_dest_regs,
    input logic [$clog2(NUM_MEM_PORTS+1)-1:0]                num_stores
);
    logic [$clog2(NUM_MEM_PORTS+1)-1:0] load_cnt;
    logic [NUM_MEM_PORTS-1:0] valid_vec;
    logic [NUM_MEM_PORTS-1:0] op_vec;

    load_cnt = '0;
    valid_vec = gen_mem_port_valid(ld_dest_regs, num_stores);
    op_vec = gen_mem_port_op(ld_dest_regs, num_stores);

    for (int i = 0; i < NUM_MEM_PORTS; i++) begin
        load_cnt += valid_vec[i] & ~op_vec[i];
    end

    return load_cnt;
endfunction


function automatic logic [$clog2(DICE_NUM_BANKS)-1:0] bank_select
(
      input logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid
    , input logic [$clog2(DICE_NUM_REGS)-1:0] rs
);
    return (tid[$clog2(DICE_NUM_REGS)-1:0] + rs[$clog2(DICE_NUM_REGS)-1:0]) & ($clog2(DICE_NUM_REGS))'(DICE_NUM_REGS - 1);
endfunction

// Circular left shift of bitmap by tid[log2(NUM_BANKS)-1:0]
// Used to align read/write bitmaps based on thread ID
function automatic logic [DICE_NUM_BANKS-1:0] shift_bitmap
(
      input logic [DICE_NUM_BANKS-1:0] bitmap
    , input logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid
);
    logic [$clog2(DICE_NUM_BANKS)-1:0] shift_amt;
    shift_amt = tid[$clog2(DICE_NUM_BANKS)-1:0];
    return (bitmap << shift_amt) | (bitmap >> (DICE_NUM_BANKS[$clog2(DICE_NUM_BANKS)-1:0] - shift_amt));
endfunction

endpackage
`endif
