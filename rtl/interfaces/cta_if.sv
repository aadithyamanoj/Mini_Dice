interface cta_if
  import dice_pkg::*;
();

  // Dispatch channel (master drives valid/data, slave drives ready)
  logic           dispatch_valid;
  dice_cta_desc_t dispatch_data;
  logic           dispatch_ready;

  // Complete channel (slave drives valid/cta_id, master drives ready)
  logic           complete_valid;
  dice_cta_id_t   complete_cta_id;
  logic           complete_ready;

  modport master(
    output dispatch_valid, output dispatch_data,  input  dispatch_ready,
    input  complete_valid, input  complete_cta_id, output complete_ready
  );

  modport slave(
    input  dispatch_valid, input  dispatch_data,   output dispatch_ready,
    output complete_valid, output complete_cta_id,  input  complete_ready
  );

endinterface
