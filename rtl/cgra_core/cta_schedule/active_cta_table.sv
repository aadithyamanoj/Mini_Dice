module active_cta_table
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Add new entry interface (table is slave)
    output logic           add_ready_o,
    input  logic           add_valid_i,
    input  dice_cta_desc_t add_cta_info_i,

    // Pop interface
    input  logic           pop_valid_i,
    output logic           pop_ready_o,

    // Output popped CTA interface (table is master)
    output logic                            out_valid_o,
    input  logic                            out_ready_i,
    output dice_cta_id_t                    out_cta_id_o,
    output logic [DICE_KERNEL_ID_WIDTH-1:0] out_kernel_id_o,

    // Status outputs
    output active_cta_t active_cta_entry_o,

    // Output flags
    output logic full_o
);

  // Single CTA entry storage
  active_cta_t cta_entry_q;

  // Output buffer for popped entries
  logic output_buffer_valid_q;
  dice_cta_id_t output_buffer_cta_id_q;
  logic [DICE_KERNEL_ID_WIDTH-1:0] output_buffer_kernel_id_q;

  // Simple full/ready logic — full when entry is valid
  assign full_o      = cta_entry_q.cta_valid;
  assign add_ready_o = ~cta_entry_q.cta_valid;

  // Output interface
  assign out_valid_o     = output_buffer_valid_q;
  assign out_cta_id_o    = output_buffer_cta_id_q;
  assign out_kernel_id_o = output_buffer_kernel_id_q;

  logic pop_this_cycle;
  logic output_consumed_this_cycle;

  // Pop ready when buffer is empty or being consumed this cycle
  assign pop_ready_o = (output_buffer_valid_q == 1'b0) || (output_consumed_this_cycle == 1'b1);

  assign pop_this_cycle = (pop_valid_i == 1'b1) && (pop_ready_o == 1'b1) &&
                          (cta_entry_q.cta_valid == 1'b1);
  assign output_consumed_this_cycle = (out_valid_o == 1'b1) && (out_ready_i == 1'b1);

  // Active CTA entry output — direct from single entry
  assign active_cta_entry_o = cta_entry_q;

  // Main table logic
  always_ff @(posedge clk_i) begin
    if (rst_i == 1'b1) begin
      cta_entry_q <= '0;
      output_buffer_valid_q <= 1'b0;
      output_buffer_cta_id_q <= '0;
      output_buffer_kernel_id_q <= '0;
    end else begin
      if ((pop_this_cycle == 1'b1) && (output_consumed_this_cycle == 1'b1)) begin
        output_buffer_valid_q <= 1'b1;
        output_buffer_cta_id_q <= cta_entry_q.cta_id;
        output_buffer_kernel_id_q <= cta_entry_q.kernel_id;
        cta_entry_q <= '0;
      end else if ((pop_this_cycle == 1'b1) && (output_buffer_valid_q == 1'b0)) begin
        output_buffer_valid_q <= 1'b1;
        output_buffer_cta_id_q <= cta_entry_q.cta_id;
        output_buffer_kernel_id_q <= cta_entry_q.kernel_id;
        cta_entry_q <= '0;

      end else if (output_consumed_this_cycle == 1'b1) begin
        output_buffer_valid_q <= 1'b0;
        output_buffer_cta_id_q <= '0;
        output_buffer_kernel_id_q <= '0;
      end
      if ((add_valid_i == 1'b1) && (add_ready_o == 1'b1)) begin
        cta_entry_q.cta_valid        <= 1'b1;
        cta_entry_q.cta_id           <= add_cta_info_i.cta_id;
        cta_entry_q.grid_size        <= add_cta_info_i.kernel_desc.grid_size;
        cta_entry_q.kernel_id        <= add_cta_info_i.kernel_desc.kernel_id;
        cta_entry_q.smem_per_cta     <= add_cta_info_i.kernel_desc.smem_per_cta;
      end
    end
  end


`ifndef SYNTHESIS

`endif

endmodule
