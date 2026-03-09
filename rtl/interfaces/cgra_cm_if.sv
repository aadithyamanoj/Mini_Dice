/**
 * CGRA Configuration Memory Interface
 * Carries bitstream data and chunk enables from FDR to CGRA configuration memory.
 */
interface cgra_cm_if
  import dice_pkg::*;
();

  localparam int CHUNK_COUNT = (DICE_BITSTREAM_SIZE + DICE_MEM_DATA_WIDTH - 1)
                               / DICE_MEM_DATA_WIDTH;

  logic [DICE_MEM_DATA_WIDTH-1:0] data;
  logic [CHUNK_COUNT-1:0]         chunk_en;

  // FDR produces configuration data
  modport master (
    output data,
    output chunk_en
  );

  // CGRA consumes configuration data
  modport slave (
    input data,
    input chunk_en
  );

endinterface
