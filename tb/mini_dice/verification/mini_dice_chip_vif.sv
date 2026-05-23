// Virtual interface for mini_dice_top chip-level UVM env.
//
// Exposes:
//   - clk_i / rst_i              : core clock/reset
//   - link_rx_* / link_tx_*      : 32-bit flits between TB and DUT
//   - cgra_prog_dout/we_o        : observation only
//   - ep_rx_* / ep_tx_*          : AXI command/response signals on the
//                                  FPGA-side of axi_link_rx/tx in tb_top.
//                                  The UVM agents drive ep_tx_* and respond
//                                  to ep_rx_* (chip's outbound traffic).

interface mini_dice_chip_vif (input logic clk);
  // Clock / reset
  logic        clk_i;
  logic        rst_i;
  // Test-level reset override: when force_rst_en is 1, the TB drives rst_i =
  // force_rst_val (so tests can assert/deassert reset mid-run). When 0, the
  // tb_top's initial sequencer owns rst_i and force_rst_val is ignored.
  logic        force_rst_en;
  logic        force_rst_val;

  // CHIP-mode bringup trigger: test sets force_bringup to 1; tb_chip's
  // watcher calls bsg_link_bringup() and clears the flag when done. Tests
  // can `wait(!vif.force_bringup)` to block until the bringup finishes.
  // tb_top (FAST) leaves this signal unused.
  logic        force_bringup;
  assign clk_i = clk;

  // Link RX (FPGA → chip): packed by TB axi_link_tx
  logic [31:0] link_rx_data;
  logic        link_rx_valid;
  logic        link_rx_yumi;

  // Link TX (chip → FPGA): unpacked by TB axi_link_rx
  logic [31:0] link_tx_data;
  logic        link_tx_valid;
  logic        link_tx_ready;

  // Observation
  logic        cgra_prog_dout;
  logic        cgra_prog_we;

  // FPGA-side RX (chip's outbound AXI as decoded by TB axi_link_rx).
  // Agents observe arvalid/awvalid/wvalid and respond on the R path.
  logic        ep_rx_awvalid;
  logic [15:0] ep_rx_awaddr;
  logic [7:0]  ep_rx_awlen;
  logic [1:0]  ep_rx_awid;
  logic        ep_rx_wvalid;
  logic [31:0] ep_rx_wdata;
  logic        ep_rx_wlast;
  logic        ep_rx_arvalid;
  logic        ep_rx_arready;
  logic [15:0] ep_rx_araddr;
  logic [7:0]  ep_rx_arlen;
  logic        ep_rx_ar_is_burst;
  logic [1:0]  ep_rx_arid;
  logic [3:0]  ep_rx_ar_tid;
  logic [2:0]  ep_rx_ar_eblock;
  logic [4:0]  ep_rx_ar_regaddr;
  // R-channel from chip-side axi_link_rx is unused; read responses are
  // packed via ep_tx_* below.

  // FPGA-side TX (agents drive these to send AXI commands into the chip via
  // TB axi_link_tx).
  logic        ep_tx_awvalid;
  logic        ep_tx_awready;
  logic [15:0] ep_tx_awaddr;
  logic [7:0]  ep_tx_awlen;
  logic [1:0]  ep_tx_awid;
  logic        ep_tx_wvalid;
  logic        ep_tx_wready;
  logic [31:0] ep_tx_wdata;
  logic        ep_tx_wlast;
  logic        ep_tx_arvalid;
  logic        ep_tx_arready;
  logic [15:0] ep_tx_araddr;
  logic [7:0]  ep_tx_arlen;
  logic        ep_tx_ar_is_burst;
  logic [1:0]  ep_tx_arid;
  logic        ep_tx_rvalid;
  logic        ep_tx_rready;
  logic [31:0] ep_tx_rdata;
  logic [1:0]  ep_tx_rresp;
  logic        ep_tx_rlast;
  logic [1:0]  ep_tx_rid;
  logic        ep_tx_r_is_burst;
  logic [7:0]  ep_tx_rlen;

  // Read responses arriving back from the chip when WE (the TB) sent a READ
  // flit to a chip slave (e.g. CSR readback). Decoded by tb_top's axi_link_rx
  // R-channel outputs.
  logic        ep_rx_rvalid;
  logic        ep_rx_rready;
  logic [31:0] ep_rx_rdata;
  logic [1:0]  ep_rx_rresp;
  logic        ep_rx_rlast;
  logic [1:0]  ep_rx_rid;
endinterface
