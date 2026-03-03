module cta_controller
  import dice_pkg::*;
  import dice_frontend_pkg::*;
(
    input  logic                       clk_i,
    input  logic                       rst_i,

    // CTA Interface (dispatch + complete)
    cta_if.slave                       cta_if_inst,

    // Active CTA Table
    output logic                       pop_valid_o,
    input  logic                       pop_ready_i,
    input  logic                       add_ready_i,
    output logic                       add_valid_o,
    output dice_cta_desc_t             add_cta_info_o,
    output logic [DICE_TID_WIDTH:0]    add_cta_thread_count_o,
    input  logic                       active_cta_valid_i,     // Single-entry valid flag
    input  logic                       pop_out_valid_i,
    input  dice_cta_id_t               pop_out_cta_id_i,

    // SIMT Stack Controller
    output logic                       init_valid_o,
    input  logic                       init_ready_i,
    output logic [DICE_ADDR_WIDTH-1:0] init_pc_o,
    output logic [DICE_ADDR_WIDTH-1:0] init_reconvergence_pc_o,

    // CTA Status Table — single entry
    input  dice_cta_status_t           cta_status_i,
    output logic                       clear_entry_valid_o
);

  assign cta_if_inst.dispatch_ready = add_ready_i && init_ready_i;
  assign add_valid_o    = cta_if_inst.dispatch_valid && cta_if_inst.dispatch_ready;
  assign add_cta_info_o = cta_if_inst.dispatch_data;

  // Raw thread count calculation
  logic [DICE_TID_WIDTH+1:0] cta_thread_count;
  assign cta_thread_count = cta_if_inst.dispatch_data.kernel_desc.cta_size.x
                            * cta_if_inst.dispatch_data.kernel_desc.cta_size.y
                            * cta_if_inst.dispatch_data.kernel_desc.cta_size.z;
  assign add_cta_thread_count_o = cta_thread_count;

  // SIMT STACK INIT
  assign init_valid_o            = cta_if_inst.dispatch_valid && cta_if_inst.dispatch_ready;
  assign init_pc_o               = cta_if_inst.dispatch_data.kernel_desc.start_pc;
  assign init_reconvergence_pc_o = '1;

  // Completion Logic
  logic victim_found;
  logic pop_fire;
  assign victim_found = active_cta_valid_i
                        && !cta_status_i.has_pending_eblock // may not work
                        && cta_status_i.is_return;

  // POP FROM ACTIVE CTA TABLE
  assign pop_valid_o = victim_found && !pop_out_valid_i;
  assign pop_fire = pop_valid_o && pop_ready_i;

  // CLEAR CTA STATUS TABLE ENTRY
  assign clear_entry_valid_o = pop_fire;

  // TELL DISPATCHER CTA IS RETURNED
  assign cta_if_inst.complete_valid  = pop_out_valid_i;
  assign cta_if_inst.complete_cta_id = pop_out_cta_id_i;


`ifndef SYNTHESIS
  pop_only_completed_p: assert property (@(posedge clk_i) disable iff (rst_i)
    pop_valid_o |-> (cta_status_i.has_pending_eblock == 1'b0)
  ) else $error("PopOnlyCompleted: Popping CTA with pending eblocks");

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
