`include "dice_define.vh"

package dice_frontend_pkg;
  import dice_pkg::*;

  parameter int BITSTREAM_LENGTH_WIDTH = 8;
  parameter int MAX_EBLOCK = 2**DICE_EBLOCK_ID_WIDTH;
  parameter int EBLOCK_ID_WIDTH = DICE_EBLOCK_ID_WIDTH;
  parameter int SIMT_STACK_COUNT = `DICE_NUM_MAX_CTA_PER_CORE;
  parameter int SIMT_STACK_THREAD_WIDTH = `DICE_NUM_MAX_THREADS_PER_CORE;
  parameter int SIMT_STACK_DEPTH = `DICE_SIMT_STACK_DEPTH;
  parameter int SIMT_STACK_ENTRY_COUNT_WIDTH = $clog2(SIMT_STACK_DEPTH + 1);

  parameter int REG_NUM = `DICE_GPR_NUM + `DICE_PR_NUM + `DICE_CR_NUM;
  parameter int REG_INDEX_WIDTH = $clog2(REG_NUM);  // Width to index a register
  parameter int PR_INDEX_WIDTH = $clog2(`DICE_PR_NUM);  // Width to index a predicate register


  // =========================================================
  // Type definitions
  // =========================================================
  typedef struct packed {
    logic branch_ena;  // Active if branch associated with p-graph
    logic branch_uni;  // Universal branch
    logic [PR_INDEX_WIDTH-1:0] branch_pred_reg;  // Predicate register index
    logic branch_neg_pred;  // Jump polarity (1: jump if 0)
    logic is_return;  // Return instruction
    logic [$clog2(`DICE_MAX_PGRAPHS)-1:0] branch_jump_target_offset;  // Jump target offset
    logic [$clog2(`DICE_MAX_PGRAPHS)-1:0] branch_reconv_offset;  // Reconvergence offset
  } branch_meta_t;

  //metadata
  // pgraph_meta_t: Complete metadata from kernel descriptor
  // Contains all information needed to execute a p-graph including branch metadata
  typedef struct packed {
    logic [DICE_ADDR_WIDTH-1:0]                                   bitstream_addr;
    logic [1:0]                                                   unrolling_factor;
    logic [7:0]                                                   lat;
    logic [REG_NUM-1:0]                                           in_regs_bitmap;
    logic [REG_NUM-1:0]                                           out_regs_bitmap;
    logic [`DICE_CGRA_MEM_PORTS-1:0][REG_INDEX_WIDTH-1:0]         ld_dest_regs;
    logic [$clog2(`DICE_CGRA_MEM_PORTS+1)-1:0]                    num_stores;
    branch_meta_t                                                 branch_meta;
    logic                                                         barrier;
    logic                                                         parameter_load;
  } pgraph_meta_t;

  // Thread mask type: Used throughout pipeline stages for semantic clarity.
  // Represents which threads in a CTA are active/valid.
  typedef logic [`DICE_NUM_MAX_THREADS_PER_CORE-1:0] thread_mask_t;

  typedef struct packed {
    logic [REG_NUM-1:0]                                           in_regs_bitmap;
    logic [REG_NUM-1:0]                                           out_regs_bitmap;
    logic [`DICE_CGRA_MEM_PORTS-1:0][REG_INDEX_WIDTH-1:0]         ld_dest_regs;
    logic [$clog2(`DICE_CGRA_MEM_PORTS+1)-1:0]                    num_stores;
    logic [1:0]                                                   unrolling_factor;
    logic [7:0]                                                   lat;
    logic                                                         parameter_load;
  } fdr_meta_t;

  //stage borders
  typedef struct packed {
    logic [DICE_ADDR_WIDTH-1:0] schedule_next_pc;
    logic [EBLOCK_ID_WIDTH-1:0] schedule_eblock_id;
    thread_mask_t               schedule_active_mask;     // Initial mask from scheduler
    logic                       schedule_prefetch_block;
    dice_cta_id_t               schedule_cta_id;
  } schedule_eblock_t;


  typedef struct packed {
    logic [EBLOCK_ID_WIDTH-1:0]               schedule_eblock_id;
    dice_cta_id_t                             schedule_cta_id;
    logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] real_active_mask;
    fdr_meta_t                                metadata;
    logic                                     loaded_buffer;
  } fdr_t;


  // CTA table entry structure
  typedef struct packed {
    logic            cta_valid;
    dice_cta_id_t    cta_id;
  } active_cta_t;


  typedef struct packed {
    logic                       is_prefetch;
    logic [DICE_ADDR_WIDTH-1:0] predict_pc;
  } cta_status_t;

  typedef struct packed {
    logic                       update_with_divergence;   // 0 = no divergence, 1 = with divergence
    logic [DICE_ADDR_WIDTH-1:0] update_next_pc;           // No divergence: next PC
    thread_mask_t               predicate_regs_value;
    logic [DICE_ADDR_WIDTH-1:0] branch_not_taken_pc;
    logic [DICE_ADDR_WIDTH-1:0] branch_reconvergence_pc;
  } simt_stack_update_t;

  typedef struct packed {
    // CTA info
    logic [DICE_HW_CTA_ID_WIDTH-1:0] hw_cta_id;
    logic                            branch_ena;
    logic                            branch_uni;
    logic [DICE_ADDR_WIDTH-1:0]      branch_taken_pc;
    logic [DICE_ADDR_WIDTH-1:0]      branch_not_taken_pc;
    logic [DICE_ADDR_WIDTH-1:0]      branch_reconvergence_pc;
    logic                            branch_neg_pred;
  } branch_info_t;

  // =========================================================
  // SIMT Stack Structures
  // =========================================================

  typedef struct packed {
    logic [DICE_ADDR_WIDTH-1:0]         pc;
    logic [DICE_ADDR_WIDTH-1:0]         reconvergence_pc;
    logic [SIMT_STACK_THREAD_WIDTH-1:0] active_mask;
  } stack_entry_t;

  // =========================================================
  // Interface Support Structures
  // =========================================================

  typedef struct packed {
    logic                               valid;
    logic [DICE_ADDR_WIDTH-1:0]         next_pc;
    logic [DICE_ADDR_WIDTH-1:0]         reconvergence_pc;
    logic [SIMT_STACK_THREAD_WIDTH-1:0] active_mask;
    logic                               empty;
    logic                               full;
  } simt_stack_status_entry_t;

endpackage
