module tb_dice_core_pkg();

  // =========================================================================
  // Randomization Class - MAYBE MOVE THIS TO A SEPARATE FILE
  // =========================================================================
  class CtaGenerator;
    rand dice_cta_desc_t desc;

    constraint c_grid_size {
      desc.kernel_desc.grid_size.x inside {[1:4]};
      desc.kernel_desc.grid_size.y inside {[1:4]};
      desc.kernel_desc.grid_size.z inside {[1:4]};
    }

    constraint c_cta_size {
      desc.kernel_desc.cta_size.x inside {[1:32]};
      desc.kernel_desc.cta_size.y inside {[1:4]};
      desc.kernel_desc.cta_size.z inside {[1:3]};
    }

    constraint c_cta_id {
      desc.cta_id.x < desc.kernel_desc.grid_size.x;
      desc.cta_id.y < desc.kernel_desc.grid_size.y;
      desc.cta_id.z < desc.kernel_desc.grid_size.z;
    }

    constraint c_params {
      desc.kernel_desc.kernel_id inside {[0:16]};
      desc.kernel_desc.smem_per_cta inside {[0:16]};
      desc.kernel_desc.start_pc == 32'h1000; // So that we can get correct metadata
      desc.kernel_desc.arg_ptr == 32'h2000;
    }
  endclass

  class MetadataGenerator;
    rand pgraph_meta_t metadata;

    constraint base_metadata {
      metadata.bitstream_length == 512;
      metadata.num_stores inside {[0:3]};
      metadata.lat inside {[1:10]};
      metadata.unrolling_factor == 0;
      metadata.barrier == 0;
      metadata.parameter_load == 0;
      metadata.bitstream_addr[0:$clog2(DICE_METADATA_WIDTH)-1] == '0; // MAY BE WRONG
    }

    constraint branch_metadata {
      metadata.branch_meta.branch_ena == 0;
      // metadata.branch_meta.branch_ena dist {0:=80, 1:=20};
      metadata.branch_meta.branch_uni dist {0:=50, 1:=50};
      metadata.branch_meta.branch_pred_reg inside {[0:7]};
      metadata.branch_meta.branch_jump_target_offset inside {[1:3]};
      metadata.branch_meta.branch_reconv_offset inside {[1:3]};
    }
  endclass





endmodule


  // Task to generate and dispatch random CTA
  // task automatic dispatch_random_cta();
  //   CtaGenerator gen;
  //   gen = new();

  //   if(gen.randomize()) begin
  //     $display("Dispatching CTA: KernelID=%0d, Grid=(%0d,%0d,%0d), CTA_ID=(%0d,%0d,%0d)",
  //               gen.desc.kernel_desc.kernel_id,
  //               gen.desc.kernel_desc.grid_size.x, gen.desc.kernel_desc.grid_size.y, gen.desc.kernel_desc.grid_size.z,
  //               gen.desc.cta_id.x, gen.desc.cta_id.y, gen.desc.cta_id.z);
  //     dispatch_cta(gen.desc);
  //   end else begin
  //     $error("Failed to randomize CTA descriptor");
  //   end
  // endtask