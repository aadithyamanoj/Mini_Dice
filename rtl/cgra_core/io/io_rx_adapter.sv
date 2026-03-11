module io_rx_adapter
  #(parameter int flit_width_p      = 16
   ,parameter int link_word_width_p = 16
   ,parameter int rx_fifo_els_p     = 64
   )
  (input  logic                           clk_i
   ,input logic                           reset_i

   // Link RX stream coming from FPGA-side bsg_link wrapper.
   // A link word is accepted on the rising edge when (link_rx_v_i && link_rx_ready_o).
   ,input  logic                          link_rx_v_i
   ,input  logic [link_word_width_p-1:0]  link_rx_data_i
   ,output logic                          link_rx_ready_o

   // Internal 16-bit PHY/RX stream sent to router logic.
   // A flit is consumed by downstream logic on the rising edge when
   // (phy_rx_v_o && phy_rx_ready_i).
   ,output logic                          phy_rx_v_o
   ,output logic [flit_width_p-1:0]       phy_rx_data_o
   ,input  logic                          phy_rx_ready_i
   );

  // --------------------------------------------------------------------------
  // io_rx_adapter
  // --------------------------------------------------------------------------
  // Purpose:
  //   Convert FPGA link RX words into internal 16-bit flits with clean
  //   backpressure and no data loss.
  //
  // This adapter is intentionally fixed to a 16-bit link datapath:
  // - one accepted link beat maps to one internal 16-bit flit.
  // - no 32->16 split logic is kept.
  //
  // Backpressure path:
  //   router stall -> phy_rx_ready_i low -> FIFO pop stalls -> FIFO fills ->
  //   link_rx_ready_o deasserts -> FPGA sender stalls.
  // --------------------------------------------------------------------------

  // Internal FIFO push side.
  logic        fifo_push_v;
  logic [15:0] fifo_push_data;
  logic        fifo_push_ready;

  // Internal FIFO pop side.
  logic        fifo_pop_v;
  logic [15:0] fifo_pop_data;
  logic        fifo_pop_yumi;

  logic link_accept;

  // Main storage element for RX buffering.
  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (rx_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) rx_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (fifo_push_v),
    .data_i (fifo_push_data),
    .ready_o(fifo_push_ready),
    .v_o    (fifo_pop_v),
    .data_o (fifo_pop_data),
    .yumi_i (fifo_pop_yumi)
  );

  // Output side is always FIFO-backed valid/yumi.
  assign phy_rx_v_o    = fifo_pop_v;
  assign phy_rx_data_o = fifo_pop_data;
  assign fifo_pop_yumi = fifo_pop_v && phy_rx_ready_i;

  assign link_accept   = link_rx_v_i && link_rx_ready_o;

  // --------------------------------------------------------------------------
  // link_rx_ready_o generation
  // --------------------------------------------------------------------------
  always_comb begin
    // 16-bit fixed mode: ready mirrors FIFO push capacity.
    link_rx_ready_o = fifo_push_ready;
  end

  // --------------------------------------------------------------------------
  // FIFO push muxing
  // --------------------------------------------------------------------------
  always_comb begin
    // One accepted link word maps to one FIFO flit.
    fifo_push_v    = link_accept;
    fifo_push_data = link_rx_data_i[15:0];
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if (link_word_width_p != 16)
        $error("io_rx_adapter is fixed to 16-bit link mode, got link_word_width_p=%0d", link_word_width_p);

      if (fifo_push_v && !fifo_push_ready)
        $error("io_rx_adapter tried to push RX FIFO while not ready");

      if (phy_rx_v_o && !phy_rx_ready_i && $past(phy_rx_v_o && !phy_rx_ready_i)) begin
        assert (phy_rx_data_o == $past(phy_rx_data_o))
          else $error("io_rx_adapter phy_rx_data_o changed while stalled");
      end
    end
  end
`endif

endmodule
