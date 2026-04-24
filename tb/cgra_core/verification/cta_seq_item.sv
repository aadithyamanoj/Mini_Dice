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

  constraint c_hold { hold_cycles inside {[1:4]}; }
  constraint c_threads { thread_count > 0; thread_count <= `DICE_NUM_MAX_THREADS_PER_CORE; }

  function new(string name = "cta_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("CTA pc=0x%04x threads=%0d cta_id=(%0d,%0d,%0d)",
                     start_pc, thread_count, cta_id.x, cta_id.y, cta_id.z);
  endfunction

endclass
