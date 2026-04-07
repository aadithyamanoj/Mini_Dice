// =============================================================================
// fetch_axi_read_if.sv
//
// Lightweight read-only AXI4-compatible interface used by the fetch stage
// (meta_fetch, bitstream_fetch_load) to request data from the AXI4 crossbar.
//
// Only AR and R channels are included; AW/W/B are absent because the fetch
// units are read-only masters.
//
// When wired to axi4_full_crossbar (via cgra_io_axi4_top promotion):
//   ar.burst  = BURST_INCR  (set by the promotion stub, not this interface)
//   ar.size   = 3'b001      (2 bytes per beat, driven by the master)
//   ar.id / lock / cache / prot / qos / user = '0  (set by promotion stub)
// =============================================================================

interface fetch_axi_read_if #(
    parameter int ADDR_WIDTH = 16  // matches DICE_ADDR_WIDTH
) ();

  // ---------------------------------------------------------------------------
  // AR channel  (address / request — master drives, slave accepts)
  // ---------------------------------------------------------------------------
  logic                  ar_valid;
  logic                  ar_ready;
  logic [ADDR_WIDTH-1:0] ar_addr;
  logic [7:0]            ar_len;   // burst length: number of beats − 1
  logic [2:0]            ar_size;  // always driven 3'b001 (2 bytes per beat)

  // ---------------------------------------------------------------------------
  // R channel   (data / response — slave drives, master accepts)
  // ---------------------------------------------------------------------------
  logic        r_valid;
  logic        r_ready;
  logic [15:0] r_data;
  logic        r_last;

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------
  modport master (
      output ar_valid,
      output ar_addr,
      output ar_len,
      output ar_size,
      input  ar_ready,
      input  r_valid,
      input  r_data,
      input  r_last,
      output r_ready
  );

  modport slave (
      input  ar_valid,
      input  ar_addr,
      input  ar_len,
      input  ar_size,
      output ar_ready,
      output r_valid,
      output r_data,
      output r_last,
      input  r_ready
  );

endinterface : fetch_axi_read_if
