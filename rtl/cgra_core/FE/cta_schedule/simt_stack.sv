`define NO_SRAM
module simt_stack
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Push interface (can also modify top when modify_top is asserted)
    input logic push_i,
    input logic modify_top_i,  // When 1, don't increment stack, just update top
    input logic [DICE_ADDR_WIDTH-1:0] push_next_pc_i,
    input logic [DICE_ADDR_WIDTH-1:0] push_reconvergence_pc_i,
    input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] push_active_mask_i,

    // Pop interface
    input logic pop_i,

    // Read top interface
    input logic read_top_i,  // Request to read top of stack

    // Stack top outputs (registered - valid next cycle after read_top)
    output logic [DICE_ADDR_WIDTH-1:0] top_next_pc_o,
    output logic [DICE_ADDR_WIDTH-1:0] top_reconvergence_pc_o,
    output logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] top_active_mask_o,
    output logic out_valid_o,  // Indicates top outputs are valid

    // Stack status outputs
    output logic stack_empty_o,
    output logic stack_full_o,
    output logic [SIMT_STACK_ENTRY_COUNT_WIDTH-1:0] stack_entry_count_o
);

  // Local Parameters (derived from packages)
  localparam int StackIndexWidth = $clog2(SIMT_STACK_DEPTH);

  // Constants
  localparam int EntryWidth = DICE_ADDR_WIDTH + DICE_ADDR_WIDTH + DICE_NUM_MAX_THREADS_PER_CORE;

  // Stack pointer (0 = empty, points to top of stack + 1)
  logic [StackIndexWidth:0] stack_ptr_q;  // Extra bit to represent SIMT_STACK_DEPTH

  // Output valid register
  logic out_valid_q;

  // RAM interface signals
  logic ram_wr_en, ram_rd_en;
  logic [StackIndexWidth-1:0] ram_wr_addr, ram_rd_addr;
  logic [EntryWidth-1:0] ram_wr_data, ram_rd_data;

  // Pack/unpack functions for RAM data
  function automatic [EntryWidth-1:0] pack_entry(
      input logic [DICE_ADDR_WIDTH-1:0] next_pc, input logic [DICE_ADDR_WIDTH-1:0] reconvergence_pc,
      input logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] active_mask);
    return {next_pc, reconvergence_pc, active_mask};
  endfunction

  function automatic logic [DICE_ADDR_WIDTH-1:0] unpack_next_pc(input logic [EntryWidth-1:0] entry);
    return entry[EntryWidth-1:DICE_ADDR_WIDTH+DICE_NUM_MAX_THREADS_PER_CORE];
  endfunction

  function automatic logic [DICE_ADDR_WIDTH-1:0] unpack_reconvergence_pc(
      input logic [EntryWidth-1:0] entry);
    return entry[DICE_ADDR_WIDTH+DICE_NUM_MAX_THREADS_PER_CORE-1:DICE_NUM_MAX_THREADS_PER_CORE];
  endfunction

  function automatic logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] unpack_active_mask(
      input logic [EntryWidth-1:0] entry);
    return entry[DICE_NUM_MAX_THREADS_PER_CORE-1:0];
  endfunction

  // Instantiate DICE RAM for stack entries
`ifndef NO_SRAM
  sram_0rw1r1w_320_32_freepdk45 stack_ram (
      .clk0 (clk_i),
      .csb0 (~ram_wr_en),
      .addr0(ram_wr_addr),
      .din0 (ram_wr_data),
      .clk1 (clk_i),
      .csb1 (~ram_rd_en),
      .addr1(ram_rd_addr),
      .dout1(ram_rd_data)
  );

`else
  bsg_mem_1r1w_sync #(
      .width_p(EntryWidth),
      .els_p(SIMT_STACK_DEPTH),
      .read_write_same_addr_p(1)
  ) stack_ram (
      .clk_i   (clk_i),
      .reset_i (rst_i),
      .w_v_i   (ram_wr_en),
      .w_addr_i(ram_wr_addr),
      .w_data_i(ram_wr_data),
      .r_v_i   (ram_rd_en),
      .r_addr_i(ram_rd_addr),
      .r_data_o(ram_rd_data)
  );
`endif
  // Stack status
  assign stack_empty_o = (stack_ptr_q == '0);
  assign stack_full_o = (stack_ptr_q == SIMT_STACK_DEPTH);
  assign stack_entry_count_o = stack_ptr_q[SIMT_STACK_ENTRY_COUNT_WIDTH-1:0];

  // Top of stack outputs - directly from RAM (registered)
  assign top_next_pc_o = unpack_next_pc(ram_rd_data);
  assign top_reconvergence_pc_o = unpack_reconvergence_pc(ram_rd_data);
  assign top_active_mask_o = unpack_active_mask(ram_rd_data);
  assign out_valid_o = out_valid_q;

  // Control logic for RAM operations
  always_comb begin
    // Default values
    ram_wr_en   = 1'b0;
    ram_rd_en   = 1'b0;
    ram_wr_addr = '0;
    ram_rd_addr = '0;
    ram_wr_data = '0;

    if ((push_i == 1'b1) && (stack_full_o == 1'b0)) begin
      if ((modify_top_i == 1'b1) && (stack_ptr_q > '0)) begin
        // Modify top: write to current top location
        ram_wr_en   = 1'b1;
        ram_wr_addr = (StackIndexWidth)'(stack_ptr_q - 1);
        ram_wr_data = pack_entry(push_next_pc_i, push_reconvergence_pc_i, push_active_mask_i);
      end else if (modify_top_i == 1'b0) begin
        // Normal push: write to next location
        ram_wr_en   = 1'b1;
        ram_wr_addr = (StackIndexWidth)'(stack_ptr_q);
        ram_wr_data = pack_entry(push_next_pc_i, push_reconvergence_pc_i, push_active_mask_i);
      end
    end

    // Read top of stack when requested
    if ((read_top_i == 1'b1) && (stack_ptr_q > '0)) begin
      ram_rd_en   = 1'b1;
      ram_rd_addr = (StackIndexWidth)'(stack_ptr_q - 1);  // Top of stack
    end
  end

  // Sequential logic for stack pointer management and output valid
  always_ff @(posedge clk_i) begin
    if (rst_i == 1'b1) begin
      stack_ptr_q <= '0;
      out_valid_q <= 1'b0;

    end else begin
      // Handle stack pointer updates
      if ((push_i == 1'b1) && (stack_full_o == 1'b0) && (modify_top_i == 1'b0)) begin
        // Normal push: increment stack pointer
        stack_ptr_q <= stack_ptr_q + 1;

      end else if ((pop_i == 1'b1) && (stack_empty_o == 1'b0)) begin
        // Pop: decrement stack pointer
        stack_ptr_q <= stack_ptr_q - 1;
      end
      // modify_top doesn't change stack_ptr_q

      // Handle output valid - becomes valid one cycle after read_top
      if ((read_top_i == 1'b1) && (stack_ptr_q > '0)) begin
        out_valid_q <= 1'b1;
      end else begin
        out_valid_q <= 1'b0;
      end
    end
  end

  // Assertions for debugging
`ifndef SYNTHESIS
  logic [DICE_ADDR_WIDTH-1:0] sim_debug_next_pc[SIMT_STACK_DEPTH];
  logic [DICE_ADDR_WIDTH-1:0] sim_debug_reconvergence_pc[SIMT_STACK_DEPTH];
  logic [DICE_NUM_MAX_THREADS_PER_CORE-1:0] sim_debug_active_mask[SIMT_STACK_DEPTH];
  logic [StackIndexWidth:0] sim_debug_depth;

  function automatic string sim_debug_op_name();
    if (push_i && modify_top_i) return "MODIFY_TOP";
    if (push_i) return "PUSH";
    if (pop_i) return "POP";
    return "NOOP";
  endfunction

  task automatic sim_debug_dump_stack(input string reason, input logic [StackIndexWidth:0] depth);
    $display("[SIMT_STACK] t=%0t %s depth=%0d", $time, reason, depth);
    if (depth == '0) begin
      $display("[SIMT_STACK] t=%0t   <empty>", $time);
    end else begin
      for (int i = SIMT_STACK_DEPTH - 1; i >= 0; i--) begin
        if (i < depth) begin
          $display(
              "[SIMT_STACK] t=%0t   entry[%0d]%s pc=%0d reconv=%0d mask=%h",
              $time,
              i,
              (i == depth - 1) ? " TOP" : "",
              sim_debug_next_pc[i],
              sim_debug_reconvergence_pc[i],
              sim_debug_active_mask[i]
          );
        end
      end
    end
  endtask

  always @(posedge clk_i) begin
    if (rst_i == 1'b1) begin
      sim_debug_depth = '0;
      for (int i = 0; i < SIMT_STACK_DEPTH; i++) begin
        sim_debug_next_pc[i] = '0;
        sim_debug_reconvergence_pc[i] = '0;
        sim_debug_active_mask[i] = '0;
      end
    end else begin
      if ((push_i == 1'b1) && (stack_full_o == 1'b1)) begin
        $error("SIMT Stack overflow: trying to push when stack is full");
      end
      if ((pop_i == 1'b1) && (stack_empty_o == 1'b1)) begin
        $error("SIMT Stack underflow: trying to pop empty stack");
      end
      if ((modify_top_i == 1'b1) && (stack_empty_o == 1'b1)) begin
        $error("SIMT Stack: trying to modify top of empty stack");
      end

      if ((push_i == 1'b1) && (stack_full_o == 1'b0) && (modify_top_i == 1'b1) &&
          (stack_ptr_q > '0)) begin
        sim_debug_next_pc[stack_ptr_q-1] = push_next_pc_i;
        sim_debug_reconvergence_pc[stack_ptr_q-1] = push_reconvergence_pc_i;
        sim_debug_active_mask[stack_ptr_q-1] = push_active_mask_i;
        sim_debug_depth = stack_ptr_q;
        $display(
            "[SIMT_STACK] t=%0t op=%s idx=%0d pc=%0d reconv=%0d mask=%h",
            $time,
            sim_debug_op_name(),
            stack_ptr_q - 1,
            push_next_pc_i,
            push_reconvergence_pc_i,
            push_active_mask_i
        );
        sim_debug_dump_stack("after MODIFY_TOP", stack_ptr_q);
      end else if ((push_i == 1'b1) && (stack_full_o == 1'b0) && (modify_top_i == 1'b0)) begin
        sim_debug_next_pc[stack_ptr_q] = push_next_pc_i;
        sim_debug_reconvergence_pc[stack_ptr_q] = push_reconvergence_pc_i;
        sim_debug_active_mask[stack_ptr_q] = push_active_mask_i;
        sim_debug_depth = stack_ptr_q + 1;
        $display(
            "[SIMT_STACK] t=%0t op=%s idx=%0d pc=%0d reconv=%0d mask=%h",
            $time,
            sim_debug_op_name(),
            stack_ptr_q,
            push_next_pc_i,
            push_reconvergence_pc_i,
            push_active_mask_i
        );
        sim_debug_dump_stack("after PUSH", stack_ptr_q + 1);
      end else if ((pop_i == 1'b1) && (stack_empty_o == 1'b0)) begin
        $display(
            "[SIMT_STACK] t=%0t op=%s idx=%0d popped_pc=%0d popped_reconv=%0d popped_mask=%h",
            $time,
            sim_debug_op_name(),
            stack_ptr_q - 1,
            sim_debug_next_pc[stack_ptr_q-1],
            sim_debug_reconvergence_pc[stack_ptr_q-1],
            sim_debug_active_mask[stack_ptr_q-1]
        );
        sim_debug_next_pc[stack_ptr_q-1] = '0;
        sim_debug_reconvergence_pc[stack_ptr_q-1] = '0;
        sim_debug_active_mask[stack_ptr_q-1] = '0;
        sim_debug_depth = stack_ptr_q - 1;
        sim_debug_dump_stack("after POP", stack_ptr_q - 1);
      end
    end
  end
`endif

endmodule
