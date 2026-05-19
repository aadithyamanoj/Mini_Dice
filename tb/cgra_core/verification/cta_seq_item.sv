// One CTA kernel dispatch transaction.
class cta_seq_item extends uvm_sequence_item;
  `uvm_object_utils(cta_seq_item)


  // Fields match dice_cta_desc_t
  rand logic [15:0]            start_pc;
  rand logic [DICE_TID_WIDTH:0] thread_count;
  rand dice_grid_size_t        grid_size;
  rand dice_cta_id_t           cta_id;

  // How many cycles to hold dispatch_valid before de-asserting (1 = single pulse)
  rand int unsigned hold_cycles;

  constraint c_hold      { hold_cycles  inside {[1:4]}; }
  constraint c_threads   { thread_count > 0;
                           thread_count <= `DICE_NUM_MAX_THREADS_PER_CORE; }
  // For our current kernel suite the FE only fetches metadata at 0x1000.
  // Loosen this if you add kernel images at other base PCs.
  constraint c_start_pc  { start_pc == 16'h1000; }
  // The design is single-cluster / single-CTA (presentation slide 12: the
  // scheduler always re-uses one CTA slot). These constraints pin the
  // randomized config to {1x1x1, (0,0,0)} — the canonical case. Tests that
  // dispatch a second CTA through the same slot (e.g. sequential_cta_test)
  // construct their seq item directly and assign cta_id outside randomize().
  constraint c_grid_size { grid_size.x == 1; grid_size.y == 1; grid_size.z == 1; }
  constraint c_cta_id    { cta_id.x    == 0; cta_id.y    == 0; cta_id.z    == 0; }

  function new(string name = "cta_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("CTA pc=0x%04x threads=%0d cta_id=(%0d,%0d,%0d)",
                     start_pc, thread_count, cta_id.x, cta_id.y, cta_id.z);
  endfunction

endclass
