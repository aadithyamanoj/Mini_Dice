module cta_controller
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input  logic                                            clk_i,
    input  logic                                            rst_i,

    // CTA Dispatcher Interface
    cta_dispatch_if.slave                                   dispatch_if,
    cta_complete_if.master                                  complete_if,

    // Active CTA Table
    output logic                                            pop_valid_o,
    output logic [DICE_HW_CTA_ID_WIDTH-1:0]                 pop_hw_cta_id_o,
    input  logic                                            pop_ready_i,            // Backpressure from active_cta_table
    input  logic                                            add_ready_i,
    output logic                                            add_valid_o,
    output dice_cta_desc_t                                  add_cta_info_o,
    output cta_size_e                                       add_hw_cta_size_o,      // CTA_SIZE_1/2/4
    output logic [DICE_TID_WIDTH:0]                         add_cta_thread_count_o, // Exact thread count
    input  logic [DICE_HW_CTA_ID_WIDTH-1:0]                 next_empty_cta_index_i,
    input  logic [DICE_NUM_MAX_CTA_PER_CORE-1:0]            active_cta_status_i,    // Validity bitmap
    input  logic                                            pop_out_valid_i,
    input  dice_cta_id_t                                    pop_out_cta_id_i,

    // SIMT Stack Controller
    output logic                                            init_valid_o,
    input  logic                                            init_ready_i,
    output logic [DICE_HW_CTA_ID_WIDTH-1:0]                 init_hw_cta_id_o,
    output cta_size_e                                       init_hw_cta_size_o,     // CTA_SIZE_1/2/4
    output logic [DICE_ADDR_WIDTH-1:0]                      init_pc_o,
    output logic [DICE_ADDR_WIDTH-1:0]                      init_reconvergence_pc_o,

    input  dice_cta_status_t [DICE_NUM_MAX_CTA_PER_CORE-1:0]cta_status_table_i,
    output logic                                            clear_entry_valid_o,
    output logic [DICE_HW_CTA_ID_WIDTH-1:0]                 clear_entry_hw_id_o
);

  // Threads per CTA slot (threads that fit in one stack)
  localparam int THREADS_PER_SLOT = DICE_NUM_MAX_THREADS_PER_CORE / DICE_NUM_MAX_CTA_PER_CORE;

  assign dispatch_if.ready = add_ready_i && init_ready_i;  //can accept from dispatcher

  assign add_valid_o = dispatch_if.valid && dispatch_if.ready;  //can add to the active cta table
  assign add_cta_info_o = dispatch_if.data;  //the info that will be given to active cta table


  //=================================================================
  // DETERMINE HOW MANY STACKS/SLOTS CTA WILL TAKE UP
  //=================================================================
  logic [DICE_TID_WIDTH+1:0] cta_thread_count;
  assign cta_thread_count = dispatch_if.data.kernel_desc.cta_size.x
                            * dispatch_if.data.kernel_desc.cta_size.y
                            * dispatch_if.data.kernel_desc.cta_size.z;



  function automatic cta_size_e encode_hw_cta_size(
    input logic [DICE_TID_WIDTH+1:0] cta_size
  );
    // Thresholds sized to match cta_size exactly
    logic [DICE_TID_WIDTH+1:0] thr1;
    logic [DICE_TID_WIDTH+1:0] thr2;
    begin
      thr1 = (DICE_TID_WIDTH + 1)'(THREADS_PER_SLOT);
      thr2 = (DICE_TID_WIDTH + 1)'(2 * THREADS_PER_SLOT);

      if (cta_size <= thr1)
        encode_hw_cta_size = CTA_SIZE_1;
      else if (cta_size <= thr2)
        encode_hw_cta_size = CTA_SIZE_2;
      else
        encode_hw_cta_size = CTA_SIZE_4;
    end
  endfunction

  assign add_hw_cta_size_o = encode_hw_cta_size(cta_thread_count);
  assign add_cta_thread_count_o = cta_thread_count;


  //=================================================================
  // ADD TO THE SIMT STACK CONTROLLER
  //=================================================================
  assign init_valid_o            = dispatch_if.valid && dispatch_if.ready;
  assign init_hw_cta_id_o        = next_empty_cta_index_i;
  assign init_hw_cta_size_o      = add_hw_cta_size_o;
  assign init_pc_o               = dispatch_if.data.kernel_desc.start_pc;
  assign init_reconvergence_pc_o = '1;


  //=================================================================
  // Completion Logic
  //=================================================================
  logic [DICE_HW_CTA_ID_WIDTH-1:0] completion_ptr_q;  // Round-robin
  logic [DICE_HW_CTA_ID_WIDTH-1:0] victim_id;
  logic victim_found;
  logic [DICE_HW_CTA_ID_WIDTH-1:0] idx;

  // Round robin for fairness
  always_ff @(posedge clk_i) begin
    if (rst_i == 1'b1) completion_ptr_q <= '0;
    else completion_ptr_q <= completion_ptr_q + 1'b1;  //automatically wraps around
  end

  always_comb begin
    victim_found = 1'b0;
    victim_id = '0;
    idx = '0;

    // We need to check all slots
    for (int i = 0; i < DICE_NUM_MAX_CTA_PER_CORE; i++) begin
      idx = completion_ptr_q + i;
      if ((active_cta_status_i[idx] == 1'b1) &&
          (cta_status_table_i[idx].has_pending_eblock == 1'b0) &&
          (victim_found == 1'b0) &&
          (cta_status_table_i[idx].is_return == 1'b1)) begin
        victim_found = 1'b1;
        victim_id = idx;
      end
    end
  end


  //=================================================================
  // POP FROM ACTIVE CTA TABLE
  //=================================================================
  assign pop_valid_o = victim_found && (pop_out_valid_i == 1'b0); //ensure nothing is in active cta buffer
  assign pop_hw_cta_id_o = victim_id;

  //=================================================================
  // CLEAR CTA STATUS TABLE ENTRY
  //=================================================================
  assign clear_entry_valid_o = pop_valid_o;  // Clear status same cycle we pop
  assign clear_entry_hw_id_o = victim_id;

  //=================================================================
  // TELL DISPATCHER CTA IS RETURNED
  //=================================================================
  assign complete_if.valid = pop_out_valid_i;
  assign complete_if.cta_id = pop_out_cta_id_i;



`ifndef SYNTHESIS
  pop_only_completed_p: assert property (@(posedge clk_i) disable iff (rst_i)
    pop_valid_o |-> (cta_status_table_i[pop_hw_cta_id_o].has_pending_eblock == 1'b0)
  ) else $error("PopOnlyCompleted: Popping CTA with pending eblocks");

  // Control outputs must never be X (when not in reset)
  pop_valid_known_p: assert property (@(posedge clk_i) disable iff (rst_i)
    !$isunknown(pop_valid_o)
  ) else $error("ControlOutputs: pop_valid_o is X");

  clear_entry_valid_known_p: assert property (@(posedge clk_i) disable iff (rst_i)
    !$isunknown(clear_entry_valid_o)
  ) else $error("ControlOutputs: clear_entry_valid_o is X");

  init_valid_known_p: assert property (@(posedge clk_i) disable iff (rst_i)
    !$isunknown(init_valid_o)
  ) else $error("ControlOutputs: init_valid_o is X");

  dispatch_sync: assert property (@(posedge clk_i) disable iff (rst_i)
    add_valid_o == init_valid_o
  ) else $error("DispatchSync: active cta table and simt_stack add/init signal mismatch");
`endif

endmodule
