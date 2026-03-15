module io_tx_adapter
  #(parameter int flit_width_p      = 16
   ,parameter int link_word_width_p = 16
   ,parameter int tx_fifo_els_p     = 64
   )
  (input  logic                           clk_i
   ,input logic                           reset_i

   // Internal 16-bit flit input stream from router/response sources.
   // Transfer into adapter occurs on (phy_tx_v_i && phy_tx_ready_o).
   ,input  logic                          phy_tx_v_i
   ,input  logic [flit_width_p-1:0]       phy_tx_data_i
   ,output logic                          phy_tx_ready_o

   // Link TX side toward bsg_link wrapper.
   // Transfer to link occurs on (link_tx_v_o && link_tx_ready_i).
   ,output logic                          link_tx_v_o
   ,output logic [link_word_width_p-1:0]  link_tx_data_o
   ,input  logic                          link_tx_ready_i
   );

  // --------------------------------------------------------------------------
  // io_tx_adapter
  // --------------------------------------------------------------------------
  // Role in overall path:
  //   16-bit internal flits -> io_tx_adapter -> bsg_link TX words
  //
  // This adapter is intentionally fixed to a 16-bit link datapath:
  // - one internal flit becomes one link beat
  // - no 16->32 pack logic is kept
  // --------------------------------------------------------------------------

  initial begin
    if (flit_width_p != 16)
      $error("io_tx_adapter requires flit_width_p=16, got %0d", flit_width_p);

    if (link_word_width_p != 16)
      $error("io_tx_adapter requires link_word_width_p=16, got %0d", link_word_width_p);
  end

  logic        tx_fifo_push_ready;
  logic        tx_fifo_pop_v;
  logic [15:0] tx_fifo_pop_data;
  logic        tx_fifo_pop_yumi;

  bsg_fifo_1r1w_small #(
    .width_p            (16),
    .els_p              (tx_fifo_els_p),
    .harden_p           (0),
    .ready_THEN_valid_p (0)
  ) tx_fifo_i (
    .clk_i  (clk_i),
    .reset_i(reset_i),
    .v_i    (phy_tx_v_i),
    .data_i (phy_tx_data_i),
    .ready_o(tx_fifo_push_ready),
    .v_o    (tx_fifo_pop_v),
    .data_o (tx_fifo_pop_data),
    .yumi_i (tx_fifo_pop_yumi)
  );

  assign phy_tx_ready_o = tx_fifo_push_ready;
  assign link_tx_v_o    = tx_fifo_pop_v;
  assign link_tx_data_o = tx_fifo_pop_data;
  assign tx_fifo_pop_yumi = tx_fifo_pop_v && link_tx_ready_i;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!reset_i) begin
      if (link_tx_v_o && !link_tx_ready_i && $past(link_tx_v_o && !link_tx_ready_i)) begin
        assert (link_tx_data_o == $past(link_tx_data_o))
          else $error("io_tx_adapter link_tx_data_o changed while stalled");
      end
    end
  end
`endif

endmodule