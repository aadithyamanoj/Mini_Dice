interface cta_complete_if
  import dice_pkg::*;
();

  logic         valid;
  dice_cta_id_t cta_id;
  logic         ready;

  modport master(output valid, output cta_id, input ready);

  modport slave(input valid, input cta_id, output ready);

endinterface
