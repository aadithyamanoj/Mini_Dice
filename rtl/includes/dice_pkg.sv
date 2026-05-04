`ifndef DICE_PKG_VH
`define DICE_PKG_VH

`include "dice_define.vh"

package dice_pkg;

  // =========================================================
  // Derived parameters (computed from configuration)
  // =========================================================
  parameter int DICE_NUM_MAX_THREADS_PER_CORE = `DICE_NUM_MAX_THREADS_PER_CORE;
  parameter int DICE_NUM_MAX_CTA_PER_CORE     = `DICE_NUM_MAX_CTA_PER_CORE;
  parameter int DICE_METADATA_WIDTH           = `DICE_METADATA_WIDTH;

  parameter int DICE_ADDR_WIDTH               = `DICE_ADDR_WIDTH;
  parameter int DICE_DATA_WIDTH               = 16;
  parameter int DICE_KERNEL_ID_WIDTH          = $clog2(`DICE_MAX_KERNEL_ID);
  parameter int DICE_CTA_ID_WIDTH             = $clog2(`DICE_MAX_GRID_SIZE);
  parameter int DICE_TID_WIDTH                = $clog2(`DICE_NUM_MAX_THREADS_PER_CORE);
  parameter int DICE_HW_CTA_ID_WIDTH          = (`DICE_NUM_MAX_CTA_PER_CORE <= 1) ? 1 : $clog2(`DICE_NUM_MAX_CTA_PER_CORE);
  parameter int DICE_HW_CTA_SIZE_WIDTH        = $clog2(`DICE_NUM_MAX_THREADS_PER_CORE) + 1;
  parameter int DICE_EBLOCK_ID_WIDTH          = $clog2(`DICE_NUM_RETIRE_TABLE_ENTRIES + 4);
  parameter int DICE_CLUSTER_ID_WIDTH         = $clog2(`DICE_NUM_CGRA_CLUSTERS);
  parameter int DICE_CORE_ID_WIDTH            = $clog2(`DICE_NUM_CGRA_CORES);
  parameter int DICE_SMEM_SIZE_WIDTH          = $clog2(`DICE_SMEM_SIZE_PER_CORE);
  parameter int DICE_BITSTREAM_SIZE           = `DICE_BITSTREAM_SIZE;
  parameter int DICE_MEM_DATA_WIDTH           = 32;
  parameter int DICE_MEM_FLAGS_WIDTH          = 1;
  parameter int DICE_MEM_ADDR_WIDTH           = DICE_ADDR_WIDTH;


  parameter int DICE_NUMBER_OF_MAX_COALESCED_COMMANDS = 8;
  parameter int DICE_CACHE_LINE_SIZE          = 8;
  parameter int DICE_BASE_ADDRESS_OFFSET      = $clog2(DICE_CACHE_LINE_SIZE);
  parameter int DICE_BASE_TID_ADDRESS_OFFSET  = $clog2(DICE_NUMBER_OF_MAX_COALESCED_COMMANDS);
  parameter int DICE_TID_BITMAP_WIDTH         = DICE_NUMBER_OF_MAX_COALESCED_COMMANDS;
  parameter int DICE_MAX_REG_WIDTH            = `DICE_CR_NUM;

  // Memory bus parameters (for VX_mem_bus_if / cgra_cm_if)
  // parameter int DICE_MEM_DATA_WIDTH           = 512;
  // parameter int DICE_MEM_ADDR_WIDTH           = 32;
  // parameter int DICE_MEM_FLAGS_WIDTH          = 4;

  // =========================================================
  // Type definitions
  // =========================================================
  typedef struct packed {
    logic [DICE_CTA_ID_WIDTH:0] x;  //one more bit than needed to represent max value
    logic [DICE_CTA_ID_WIDTH:0] y;  //one more bit than needed to represent max value
    logic [DICE_CTA_ID_WIDTH:0] z;  //one more bit than needed to represent max value
  } dice_grid_size_t;  // Grid size descriptor

  typedef struct packed {
    logic [DICE_TID_WIDTH:0] x;  //one more bit than needed to represent max value
    logic [DICE_TID_WIDTH:0] y;  //one more bit than needed to represent max value
    logic [DICE_TID_WIDTH:0] z;  //one more bit than needed to represent max value
  } dice_cta_size_t;  // CTA size descriptor

  typedef struct packed {
    logic [DICE_CTA_ID_WIDTH-1:0] x;
    logic [DICE_CTA_ID_WIDTH-1:0] y;
    logic [DICE_CTA_ID_WIDTH-1:0] z;
  } dice_cta_id_t;  // CTA ID descriptor

  typedef struct packed {
    logic [DICE_TID_WIDTH-1:0] x;
    logic [DICE_TID_WIDTH-1:0] y;
    logic [DICE_TID_WIDTH-1:0] z;
  } dice_tid_t;  // Thread ID descriptor

  typedef struct packed {
    dice_grid_size_t             grid_size;
    logic [DICE_TID_WIDTH:0]     thread_count;  // Pre-computed CTA thread count, set by dispatcher

    // Initial
    logic [DICE_ADDR_WIDTH-1:0]  start_pc;
  } dice_kernel_desc_t;  // Kernel descriptor for top driver to receive kernel launch info


  typedef struct packed {
    dice_kernel_desc_t kernel_desc;
    dice_cta_id_t      cta_id;
  } dice_cta_desc_t;  // CTA descriptor passed to CGRA core front end

  typedef struct packed {
    logic unresolved_control_divergence;
    logic [DICE_ADDR_WIDTH-1:0] predict_pc;
    logic has_pending_eblock;
    logic eblock_in_flight;
    logic is_return;
  } dice_cta_status_t;  // CTA status descriptor

  typedef struct packed {
    logic [2:0]                      valid_edits_bitmap;
    logic                            unresolved_control_divergence; // [100]
    logic [DICE_ADDR_WIDTH-1:0]      predict_pc; // [010]
    logic                            is_return; // [001]
  } branch_predict_interface_t;  // Branch prediction interface descriptor

  typedef struct packed {
    logic has_pending_eblock;
  } block_retire_status_t;  // Block retire status descriptor

endpackage

`endif  // DICE_PKG_VH
