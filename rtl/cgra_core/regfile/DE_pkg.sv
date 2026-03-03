`ifndef DEIMPORTS
`define DEIMPORTS
`include "dice_define.vh"
package DE_pkg;


parameter int DICE_NUM_REG_BANK = 512;
parameter int DICE_REG_DATA_WIDTH = 32;
parameter int CACHE_LINE_SIZE = 32;
parameter int NUMBER_OF_MAX_COALESCED_COMMANDS = CACHE_LINE_SIZE/4;
parameter int TID_BITMAP_WIDTH = NUMBER_OF_MAX_COALESCED_COMMANDS;
parameter int BASE_ADDRESS_OFFSET = $clog2(CACHE_LINE_SIZE);
parameter int DICE_NUM_BANKS = 32;
parameter int DICE_NUM_REGS = 32;
parameter int DICE_REG_ADDR_WIDTH = $clog2(DICE_NUM_REG_BANK)-1;
// =========================================================
// Dispatcher architecture constants
// =========================================================
parameter int NUM_SCOREBOARDS  = 4;
parameter int NUM_LANES        = 4;
parameter int CHUNK_SIZE       = `DICE_NUM_MAX_THREADS_PER_CORE / NUM_SCOREBOARDS;
parameter int CHUNK_ADDR_WIDTH = (NUM_SCOREBOARDS == 1) ? 1 : $clog2(NUM_SCOREBOARDS);
parameter int LANE_SIZE        = CHUNK_SIZE / NUM_LANES;
parameter int LANE_WIDTH       = $clog2(LANE_SIZE);
typedef struct packed {
    logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0]  outcmd_base_tid;
    logic [TID_BITMAP_WIDTH-1:0]                        outcmd_tid_bitmap;
    logic [DICE_REG_ADDR_WIDTH-1:0]                     outcmd_ld_dest_reg;
    logic [NUMBER_OF_MAX_COALESCED_COMMANDS-1:0]
          [BASE_ADDRESS_OFFSET-1:0]                     outcmd_address_map;
    logic [(CACHE_LINE_SIZE*8)-1:0]                     core_rsp_data;
} cache_wr_cmd;

typedef struct packed {
    // all banks
    logic [(DICE_REG_DATA_WIDTH*DICE_NUM_BANKS)-1:0] data;
    logic [DICE_NUM_BANKS-1:0] mask;
    logic [($clog2(`DICE_NUM_MAX_THREADS_PER_CORE)*DICE_NUM_BANKS)-1:0] tid;
} ldst_wr_cmd;

typedef struct packed {
    // single bank
    logic [DICE_REG_DATA_WIDTH-1:0] data;
    logic mask;
    logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
} reg_wr_cmd;


function automatic reg_wr_cmd [DICE_NUM_BANKS-1:0] unpack_ldsr_wr
(
    input ldst_wr_cmd cmd
); 
    reg_wr_cmd [DICE_NUM_BANKS-1:0] wr_cmd;
    for (int i = 0; i < DICE_NUM_BANKS; i++) begin
        wr_cmd[i].data = cmd.data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH];
        wr_cmd[i].mask = cmd.mask[i];
        wr_cmd[i].tid = cmd.tid[i];
    end
    return wr_cmd;
endfunction


function automatic ldst_wr_cmd assemble_ldst_wr
(
    input cache_wr_cmd cmd
);
    ldst_wr_cmd wr_data;
    for (int i = 0; i < NUMBER_OF_MAX_COALESCED_COMMANDS; i++) begin
        if (cmd.outcmd_tid_bitmap[i]) begin
            wr_data.data[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] 
                = cmd.core_rsp_data[i*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH];
            wr_data.mask[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)] = 1'b1;
            wr_data.tid[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)] = cmd.outcmd_base_tid + cmd.outcmd_address_map[i];
        end else begin
            wr_data.data[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)*DICE_REG_DATA_WIDTH +: DICE_REG_DATA_WIDTH] = '0;
            wr_data.mask[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)] = 1'b0;
            wr_data.tid[bank_select(cmd.outcmd_base_tid + cmd.outcmd_address_map[i], cmd.outcmd_ld_dest_reg)] = '0;
        end
    end
    return wr_data;
endfunction

typedef struct packed {
    logic[$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid;
    logic[$clog2(DICE_NUM_REGS)-1:0] rs;
    logic      re;
} reg_rd_cmd;


function automatic logic [$clog2(DICE_NUM_BANKS)-1:0] bank_select
(
      input logic [$clog2(`DICE_NUM_MAX_THREADS_PER_CORE)-1:0] tid
    , input logic [$clog2(DICE_NUM_REGS)-1:0] rs
);
    return (tid[4:0] + rs[4:0]) & 5'h1F;
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
