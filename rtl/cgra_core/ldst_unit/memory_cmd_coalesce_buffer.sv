`include "dice_pkg.sv"

module memory_cmd_coalesce_buffer
import dice_pkg::*;   
#(parameter MAP = DICE_NUMBER_OF_MAX_COALESCED_COMMANDS * DICE_BASE_ADDRESS_OFFSET
)(
    input logic clk_i,                        // Clock signal
    input logic rst,                      // Active high reset signal
    input logic clear,
    input logic update_new,                  //update existing cmd to new commnd
    
    // Input command interface
    input logic incmd_valid,                // Input command valid signal
    input logic [DICE_EBLOCK_ID_WIDTH-1:0] incmd_block_id,       // Input command block ID
    input logic [DICE_TID_WIDTH-1:0] incmd_tid,            // Input command thread ID
    input logic incmd_write_enable,         // Write enable signal
    input logic [DICE_DATA_WIDTH-1:0] incmd_write_data,    // Data to write
    input logic [DICE_DATA_WIDTH/8-1:0] incmd_write_mask,     // 1 means no write, 0 means write
    input logic [DICE_ADDR_WIDTH-1:0] incmd_address,       // Address for the command
    input logic [1:0] incmd_size,          // Size of the command (e.g., 00=1B, 01=2B, 10=4B, 11=8B)
    input logic [DICE_MAX_REG_WIDTH-1:0] incmd_ld_dest_reg,    // Load destination register
    
    // Ready signal for input command
    output logic can_coalesce,                // Ready signal for input command
    
    // Output command interface
    output logic outcmd_valid,              // Output command valid signal
    output logic [DICE_EBLOCK_ID_WIDTH-1:0] outcmd_block_id,     // Output command block ID
    output logic [DICE_TID_WIDTH-1:0] outcmd_base_tid,     // Output command thread ID
    output logic [DICE_TID_BITMAP_WIDTH-1:0] outcmd_tid_bitmap,  // Bitmap of TIDs for the command
    output logic outcmd_write_enable,       // Write enable signal
    output logic [DICE_CACHE_LINE_SIZE*8-1:0] outcmd_write_data,  // Data to write
    output logic [DICE_CACHE_LINE_SIZE-1:0] outcmd_write_mask, // 1 means no write, 0 means write
    output logic [DICE_ADDR_WIDTH-1:0] outcmd_address,     // Address for the command
    output logic [1:0] outcmd_size,        // Size of the command (e.g., 00=1B, 01=2B, 10=4B, 11=8B)
    output logic [DICE_MAX_REG_WIDTH-1:0] outcmd_ld_dest_reg,  // Load destination register

    output logic [MAP-1:0] outcmd_address_map
);
    localparam BYTES_PER_WORD = DICE_DATA_WIDTH/8;
    logic outcmd_valid_next; 
    logic [DICE_EBLOCK_ID_WIDTH-1:0] outcmd_block_id_next;
    logic [DICE_TID_WIDTH-1:0] outcmd_base_tid_next;
    logic [DICE_TID_BITMAP_WIDTH-1:0] outcmd_tid_bitmap_next;
    logic outcmd_write_enable_next;
    logic [DICE_CACHE_LINE_SIZE*8-1:0] outcmd_write_data_next;
    logic [DICE_CACHE_LINE_SIZE-1:0] outcmd_write_mask_next;
    logic [DICE_ADDR_WIDTH-1:0] outcmd_address_next;
    logic [1:0] outcmd_size_next; // Size of the command (e.g., 00=1B, 01=2B, 10=4B, 11=8B)
    logic [DICE_MAX_REG_WIDTH-1:0] outcmd_ld_dest_reg_next; 
    logic [DICE_NUMBER_OF_MAX_COALESCED_COMMANDS-1:0][DICE_BASE_ADDRESS_OFFSET-1:0] outcmd_address_map_next; //map from tid bitmap to address_offset

    always_ff@(posedge clk_i) begin
        if (rst) begin
            // Reset logic
            outcmd_valid <= 1'b0;
            outcmd_block_id <= {DICE_EBLOCK_ID_WIDTH{1'b0}};
            outcmd_base_tid <= {DICE_TID_WIDTH{1'b0}};
            outcmd_tid_bitmap <= {DICE_TID_BITMAP_WIDTH{1'b0}};
            outcmd_write_enable <= 1'b0;
            outcmd_write_data <= {(DICE_CACHE_LINE_SIZE*8){1'b0}};
            outcmd_write_mask <= {(DICE_CACHE_LINE_SIZE){1'b1}}; // Initialize write mask to all masked
            outcmd_address <= {DICE_ADDR_WIDTH{1'b0}};
            outcmd_size <= 2'b10; // Reset size to 4B
            outcmd_ld_dest_reg <= {DICE_MAX_REG_WIDTH{1'b0}};
            outcmd_address_map <= '0; // Reset address map to zero
        end else if (clear) begin
            // Clear logic
            if(!update_new) begin
                outcmd_valid <= 1'b0; // Clear output command if not updating
            end else begin
                outcmd_valid <= outcmd_valid_next;
                outcmd_block_id <= outcmd_block_id_next;
                outcmd_base_tid <= outcmd_base_tid_next;
                outcmd_tid_bitmap <= outcmd_tid_bitmap_next;    
                outcmd_write_enable <= outcmd_write_enable_next;
                outcmd_write_data <= outcmd_write_data_next;
                outcmd_write_mask <= outcmd_write_mask_next;
                outcmd_address <= outcmd_address_next;
                outcmd_size <= outcmd_size_next; // Update size based on input command
                outcmd_ld_dest_reg <= outcmd_ld_dest_reg_next;
                outcmd_address_map <= outcmd_address_map_next;
            end
        end else begin
            outcmd_valid <= outcmd_valid_next;
            outcmd_block_id <= outcmd_block_id_next;
            outcmd_base_tid <= outcmd_base_tid_next;
            outcmd_tid_bitmap <= outcmd_tid_bitmap_next;    
            outcmd_write_enable <= outcmd_write_enable_next;
            outcmd_write_data <= outcmd_write_data_next;
            outcmd_write_mask <= outcmd_write_mask_next;
            outcmd_address <= outcmd_address_next;
            outcmd_size <= outcmd_size_next; // Update size based on input command
            outcmd_ld_dest_reg <= outcmd_ld_dest_reg_next;
            outcmd_address_map <= outcmd_address_map_next;
        end
    end


    logic same_block_id;
    logic same_ld_dest_reg;
    logic same_tid_chunk;
    logic same_rd_wr;
    logic same_base_address;
    logic same_write_enable;

    // Adjusted internal logic to match [DICE_TID_WIDTH:0]
    logic [DICE_TID_WIDTH-1:0] incmd_base_tid;
    assign incmd_base_tid = {incmd_tid[DICE_TID_WIDTH-1:DICE_BASE_TID_ADDRESS_OFFSET], {(DICE_BASE_TID_ADDRESS_OFFSET){1'b0}}};

    logic [DICE_BASE_TID_ADDRESS_OFFSET-1:0] incmd_tid_offset;
    assign incmd_tid_offset = incmd_tid[DICE_BASE_TID_ADDRESS_OFFSET-1:0];

    logic [DICE_ADDR_WIDTH-1:0] incmd_base_address;
    assign incmd_base_address = {incmd_address[DICE_ADDR_WIDTH-1:DICE_BASE_ADDRESS_OFFSET], {(DICE_BASE_ADDRESS_OFFSET){1'b0}}};

    logic [DICE_BASE_ADDRESS_OFFSET-1:0] incmd_address_offset;
    assign incmd_address_offset = incmd_address[DICE_BASE_ADDRESS_OFFSET-1:0];

    logic [DICE_CACHE_LINE_SIZE-1:0] incmd_coalesce_mask;

    logic [3:0] incmd_actual_size;
    assign incmd_actual_size = incmd_size == 2'b00 ? 4'd1: 
                               incmd_size == 2'b01 ? 4'd2: 
                               incmd_size == 2'b10 ? 4'd4: 4'd8 ; // Calculate the actual size based on the command size

    always_comb begin
        // Generate the coalesce mask based on the command size
        incmd_coalesce_mask = '1; // Initialize to all masked
        for(int i = 0; i < BYTES_PER_WORD; i++) begin
            if (i >= incmd_actual_size) begin
                incmd_coalesce_mask[i+incmd_address_offset] = 1'b1; // Mask bits that are not part of the command
            end else begin
                incmd_coalesce_mask[i+incmd_address_offset] = incmd_write_mask[i]; // Use the input write mask for the first few bits
            end
        end
    end

    assign same_write_enable = (outcmd_write_enable == incmd_write_enable);
    assign same_block_id = (outcmd_block_id == incmd_block_id);
    assign same_ld_dest_reg = (outcmd_ld_dest_reg == incmd_ld_dest_reg) || outcmd_write_enable; // Coalesce if the destination register is the same or write enable is set
    assign same_tid_chunk = (outcmd_base_tid == incmd_base_tid);
    assign same_rd_wr = (outcmd_write_enable == incmd_write_enable);
    assign same_base_address = (outcmd_address == incmd_base_address);
    
    assign can_coalesce = (outcmd_valid && incmd_valid && 
        same_write_enable && same_block_id && same_ld_dest_reg && same_tid_chunk && 
        same_rd_wr && same_base_address); //can coalesce


    always_comb begin
        // Default values for next output command
        outcmd_valid_next = outcmd_valid;
        outcmd_block_id_next = outcmd_block_id;
        outcmd_base_tid_next = outcmd_base_tid;
        outcmd_tid_bitmap_next = outcmd_tid_bitmap;
        outcmd_write_enable_next = outcmd_write_enable;
        outcmd_write_data_next = outcmd_write_data;
        outcmd_write_mask_next = outcmd_write_mask;
        outcmd_address_next = outcmd_address;   
        outcmd_size_next = outcmd_size; // Keep the size same as current
        outcmd_ld_dest_reg_next = outcmd_ld_dest_reg;
        outcmd_address_map_next = outcmd_address_map;

        // start a new command to be coalesced
        if ((update_new || (incmd_valid && !outcmd_valid))) begin
            outcmd_valid_next = 1'b1; // Set output command valid
            outcmd_block_id_next = incmd_block_id; // Update block ID
            outcmd_base_tid_next = incmd_base_tid; // Update base TID
            outcmd_tid_bitmap_next = (1 << incmd_tid_offset); // Set the TID in the bitmap
            outcmd_write_enable_next = incmd_write_enable; // Update write enable
            if(incmd_write_enable) begin
                for(int i=0;i<BYTES_PER_WORD;i++) begin
                    if(i < incmd_actual_size) begin
                        if(!incmd_write_mask[i]) begin
                            outcmd_write_data_next[(i+incmd_address_offset)*8 +: 8] = incmd_write_data[i*8 +: 8]; // Update write data for the coalesced bits
                        end
                    end
                end
            end

            //outcmd_write_data_next = '0 | (incmd_write_data<< ({incmd_address_offset,3'b0})); // Update write data
            outcmd_write_mask_next = incmd_coalesce_mask; // Update write mask
            outcmd_address_next = incmd_base_address; // Update address
            outcmd_size_next = incmd_size; // Update size based on input command
            outcmd_ld_dest_reg_next = incmd_ld_dest_reg; // Update load destination register
            // Update address map for the coalesced command
            if(!incmd_write_enable) begin
                outcmd_address_map_next[incmd_tid_offset][DICE_BASE_ADDRESS_OFFSET-1:0]= incmd_address_offset;
            end
        end else if (incmd_valid) begin
            // coalesce if can
            if(can_coalesce) begin
                // Coalesce the command
                outcmd_tid_bitmap_next = outcmd_tid_bitmap | (1 << incmd_tid_offset); // Set the TID in the bitmap
                if(incmd_write_enable) begin
                    for(int i=0;i<BYTES_PER_WORD;i++) begin
                        if(i < incmd_actual_size) begin
                            if(!incmd_write_mask[i]) begin
                                outcmd_write_data_next[(i+incmd_address_offset)*8 +: 8] = incmd_write_data[i*8 +: 8]; // Update write data for the coalesced bits
                                outcmd_write_mask_next[i+incmd_address_offset] = 1'b0; 
                            end else begin
                                outcmd_write_mask_next[i+incmd_address_offset] = 1'b1; 
                            end
                        end
                    end
                end
                if(!incmd_write_enable) begin
                    outcmd_address_map_next[incmd_tid_offset][DICE_BASE_ADDRESS_OFFSET-1:0]= incmd_address_offset;
                end
            end 
        end
    end
endmodule