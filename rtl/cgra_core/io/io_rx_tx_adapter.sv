module io_rx_tx_adapter
  #(parameter int flit_width_p      = 16
   ,parameter int link_word_width_p = 16
   ,parameter int rx_fifo_els_p     = 16
   ,parameter int tx_fifo_els_p     = 16
   )
  (input  logic                           clk_i
   ,input logic                           reset_i

   // Link RX side (from bsg_link wrapper).
   ,input  logic                          link_rx_v_i
   ,input  logic [link_word_width_p-1:0]  link_rx_data_i
   ,output logic                          link_rx_ready_o

   // Link TX side (to bsg_link wrapper).
   ,output logic                          link_tx_v_o
   ,output logic [link_word_width_p-1:0]  link_tx_data_o
   ,input  logic                          link_tx_ready_i

   // Internal RX flits to router.
   ,output logic                          phy_rx_v_o
   ,output logic [flit_width_p-1:0]       phy_rx_data_o
   ,input  logic                          phy_rx_ready_i

   // Internal TX flits from router.
   ,input  logic                          phy_tx_v_i
   ,input  logic [flit_width_p-1:0]       phy_tx_data_i
   ,output logic                          phy_tx_ready_o
   );

  // --------------------------------------------------------------------------
  // io_rx_tx_adapter
  // --------------------------------------------------------------------------
  // Integration wrapper:
  // - Keeps RX and TX data paths physically separated so they can be tested
  //   independently in isolation before integrated adapter-level validation.
  // - io_rx_adapter handles link_rx_* -> phy_rx_* path.
  // - io_tx_adapter handles phy_tx_* -> link_tx_* path.
  // --------------------------------------------------------------------------

  io_rx_adapter #(
    .flit_width_p     (flit_width_p),
    .link_word_width_p(link_word_width_p),
    .rx_fifo_els_p    (rx_fifo_els_p)
  ) rx_path_i (
    .clk_i         (clk_i),
    .reset_i       (reset_i),
    .link_rx_v_i   (link_rx_v_i),
    .link_rx_data_i(link_rx_data_i),
    .link_rx_ready_o(link_rx_ready_o),
    .phy_rx_v_o    (phy_rx_v_o),
    .phy_rx_data_o (phy_rx_data_o),
    .phy_rx_ready_i(phy_rx_ready_i)
  );

  io_tx_adapter #(
    .flit_width_p     (flit_width_p),
    .link_word_width_p(link_word_width_p),
    .tx_fifo_els_p    (tx_fifo_els_p)
  ) tx_path_i (
    .clk_i         (clk_i),
    .reset_i       (reset_i),
    .phy_tx_v_i    (phy_tx_v_i),
    .phy_tx_data_i (phy_tx_data_i),
    .phy_tx_ready_o(phy_tx_ready_o),
    .link_tx_v_o   (link_tx_v_o),
    .link_tx_data_o(link_tx_data_o),
    .link_tx_ready_i(link_tx_ready_i)
  );

endmodule
