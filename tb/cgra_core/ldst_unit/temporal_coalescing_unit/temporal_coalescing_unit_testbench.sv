`include "dice_pkg.sv"

module temporal_coalescing_unit_testbench;
    import dice_pkg::*;
    
    // Test parameters
    parameter CLK_PERIOD = 20000;
    parameter MAP = DICE_NUMBER_OF_MAX_COALESCED_COMMANDS * DICE_BASE_ADDRESS_OFFSET;
    // Clock and reset
    bit clk_i;
    bit rst;
    
    // DUT input signals
    bit incmd_valid;
    bit [DICE_EBLOCK_ID_WIDTH-1:0] incmd_block_id;
    bit [DICE_TID_WIDTH-1:0] incmd_tid;
    bit incmd_write_enable;
    bit [DICE_DATA_WIDTH-1:0] incmd_write_data;
    bit [DICE_DATA_WIDTH/8-1:0] incmd_write_mask;
    bit [DICE_ADDR_WIDTH-1:0] incmd_address;
    bit [1:0] incmd_size;
    bit [DICE_MAX_REG_WIDTH-1:0] incmd_ld_dest_reg;
    bit outcmd_ready;
    
    // DUT output signals
    logic incmd_ready;
    logic outcmd_valid;
    logic [DICE_EBLOCK_ID_WIDTH-1:0] outcmd_block_id;
    logic [DICE_TID_WIDTH-1:0] outcmd_base_tid;
    logic [DICE_TID_BITMAP_WIDTH-1:0] outcmd_tid_bitmap;
    logic outcmd_write_enable;
    logic [DICE_CACHE_LINE_SIZE*8-1:0] outcmd_write_data;
    logic [DICE_CACHE_LINE_SIZE-1:0] outcmd_write_mask;
    logic [DICE_ADDR_WIDTH-1:0] outcmd_address;
    logic [1:0] outcmd_size;
    logic [DICE_MAX_REG_WIDTH-1:0] outcmd_ld_dest_reg;
    logic [MAP-1:0] outcmd_address_map;
    
    // Test tracking variables
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    int commands_sent = 0;
    int commands_received = 0;
    string current_test_name;
    
    // Input command structure
    typedef struct {
        logic [DICE_EBLOCK_ID_WIDTH-1:0] block_id;
        logic [DICE_TID_WIDTH-1:0] tid;
        logic write_enable;
        logic [DICE_DATA_WIDTH-1:0] write_data;
        logic [DICE_DATA_WIDTH/8-1:0] write_mask;
        logic [DICE_ADDR_WIDTH-1:0] address;
        logic [1:0] size;
        logic [DICE_MAX_REG_WIDTH-1:0] ld_dest_reg;
        string description;
    } input_cmd_t;
    
    // Expected output command structure
    typedef struct {
        logic [DICE_EBLOCK_ID_WIDTH-1:0] block_id;
        logic [DICE_TID_WIDTH-1:0] base_tid;
        logic [DICE_TID_BITMAP_WIDTH-1:0] tid_bitmap;
        logic write_enable;
        logic [DICE_CACHE_LINE_SIZE*8-1:0] write_data;
        logic [DICE_CACHE_LINE_SIZE-1:0] write_mask;
        logic [DICE_ADDR_WIDTH-1:0] address;
        logic [1:0] size;
        logic [DICE_MAX_REG_WIDTH-1:0] ld_dest_reg;
        string description;
        logic check_tid_bitmap;
        logic check_write_data;
        logic check_write_mask;
    } expected_cmd_t;
    
    // Command queues
    input_cmd_t input_queue[$];
    expected_cmd_t expected_output_queue[$];
    
    // Driver and checker control
    logic driver_active = 0;
    logic checker_active = 0;
    logic test_complete = 0;
    
    // Clock generation
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end
    
    // DUT instantiation
    temporal_coalescing_unit #(
    ) dut (
        .clk_i(clk_i),
        .rst(rst),
        .incmd_valid(incmd_valid),
        .incmd_block_id(incmd_block_id),
        .incmd_tid(incmd_tid),
        .incmd_write_enable(incmd_write_enable),
        .incmd_write_data(incmd_write_data),
        .incmd_write_mask(incmd_write_mask),
        .incmd_address(incmd_address),
        .incmd_size(incmd_size),
        .incmd_ld_dest_reg(incmd_ld_dest_reg),
        .incmd_ready(incmd_ready),
        .outcmd_valid(outcmd_valid),
        .outcmd_block_id(outcmd_block_id),
        .outcmd_base_tid(outcmd_base_tid),
        .outcmd_tid_bitmap(outcmd_tid_bitmap),
        .outcmd_write_enable(outcmd_write_enable),
        .outcmd_write_data(outcmd_write_data),
        .outcmd_write_mask(outcmd_write_mask),
        .outcmd_address(outcmd_address),
        .outcmd_size(outcmd_size),
        .outcmd_ld_dest_reg(outcmd_ld_dest_reg),
        .outcmd_address_map(outcmd_address_map),
        .outcmd_ready(outcmd_ready)
    );
    
    // Task to add input command to queue
    task automatic add_input_command(
        input [DICE_EBLOCK_ID_WIDTH-1:0] block_id,
        input [DICE_TID_WIDTH-1:0] tid,
        input logic write_enable,
        input [DICE_DATA_WIDTH-1:0] write_data,
        input [DICE_DATA_WIDTH/8-1:0] write_mask,
        input [DICE_ADDR_WIDTH-1:0] address,
        input [1:0] size,
        input [DICE_MAX_REG_WIDTH-1:0] ld_dest_reg,
        input string description
    );
        input_cmd_t cmd;
        input_cmd_t last_cmd;
        cmd.block_id = block_id;
        cmd.tid = tid;
        cmd.write_enable = write_enable;
        cmd.write_data = write_data;
        cmd.write_mask = write_mask;
        cmd.address = address;
        cmd.size = size;
        cmd.ld_dest_reg = ld_dest_reg;
        cmd.description = description;
        input_queue.push_back(cmd);
        $display("Added input command: %s (Queue size: %0d)", cmd.description, input_queue.size());
        $display("  Block ID: %0d, TID: %0d, Write Enable: %b", cmd.block_id, cmd.tid, cmd.write_enable);
        $display("  Write Data: 0x%h, Write Mask: 0x%h", cmd.write_data, cmd.write_mask);
        $display("  Address: 0x%h, Size: %0d, Load Dest Reg: %0d", cmd.address, cmd.size, cmd.ld_dest_reg);
    endtask
    
    // Task to add expected output command to queue
    task automatic add_expected_output(
        input [DICE_EBLOCK_ID_WIDTH-1:0] block_id,
        input [DICE_TID_WIDTH-1:0] base_tid,
        input [DICE_TID_BITMAP_WIDTH-1:0] tid_bitmap,
        input logic write_enable,
        input [DICE_CACHE_LINE_SIZE*8-1:0] write_data,
        input [DICE_CACHE_LINE_SIZE-1:0] write_mask,
        input [DICE_ADDR_WIDTH-1:0] address,
        input [1:0] size,
        input [DICE_MAX_REG_WIDTH-1:0] ld_dest_reg,
        input string description,
        input logic check_tid_bitmap = 1'b0,
        input logic check_write_data = 1'b0,
        input logic check_write_mask = 1'b0
    );
        expected_cmd_t cmd;
        cmd.block_id = block_id;
        cmd.base_tid = base_tid;
        cmd.tid_bitmap = tid_bitmap;
        cmd.write_enable = write_enable;
        cmd.write_data = write_data;
        cmd.write_mask = write_mask;
        cmd.address = address;
        cmd.size = size;
        cmd.ld_dest_reg = ld_dest_reg;
        cmd.description = description;
        expected_output_queue.push_back(cmd);
        cmd.check_tid_bitmap = check_tid_bitmap;
        cmd.check_write_data = check_write_data;
        cmd.check_write_mask = check_write_mask;
        $display("Added expected output: %s (Queue size: %0d)", description, expected_output_queue.size());
    endtask
    
    // Driver process: sends commands from input queue to DUT
    always @(posedge clk_i) begin
        if (rst) begin
            incmd_valid <= 1'b0;
            incmd_block_id <= {DICE_EBLOCK_ID_WIDTH{1'b0}};;
            incmd_tid <= {DICE_TID_WIDTH{1'b0}};
            incmd_write_enable <= 1'b0;
            incmd_write_data <= {DICE_DATA_WIDTH{1'b0}};
            incmd_write_mask <= {(DICE_DATA_WIDTH/8){1'b0}};
            incmd_address <= {DICE_ADDR_WIDTH{1'b0}};
            incmd_size <= 2'b0;
            incmd_ld_dest_reg <= {DICE_MAX_REG_WIDTH{1'b0}};
 
        end else if (driver_active) begin
            if (incmd_ready) begin
                if(input_queue.size() == 0) begin
                    incmd_valid <= 1'b0; // No more commands to send
                end else if (input_queue.size() > 0) begin
                    input_cmd_t cmd;
                    cmd = input_queue[0];
                    incmd_valid <= 1'b1; // Keep sending commands
                    incmd_block_id <= cmd.block_id;
                    incmd_tid <= cmd.tid;
                    incmd_write_enable <= cmd.write_enable;
                    incmd_write_data <= cmd.write_data;
                    incmd_write_mask <= cmd.write_mask;
                    incmd_address <= cmd.address;
                    incmd_size <= cmd.size;
                    incmd_ld_dest_reg <= cmd.ld_dest_reg;
                    $display("[DRIVER] Sending command at time %0d", $time);
                    $display("  Block ID: %0d, TID: %0d, Write Enable: %b", cmd.block_id, cmd.tid, cmd.write_enable);
                    $display("  Write Data: 0x%h, Write Mask: 0x%h", cmd.write_data, cmd.write_mask);
                    $display("  Address: 0x%h, Size: %0d, Load Dest Reg: %0d", cmd.address, cmd.size, cmd.ld_dest_reg);
                    $display("  Description: %s", cmd.description);
                    input_queue.pop_front(); // Remove command from queue
                    $display("  Input commands left in queue: %0d", input_queue.size());
                end
            end
        end else begin
            incmd_valid <= 1'b0;
            incmd_block_id <= {DICE_EBLOCK_ID_WIDTH{1'b0}};;
            incmd_tid <= {DICE_TID_WIDTH{1'b0}};
            incmd_write_enable <= 1'b0;
            incmd_write_data <= {DICE_DATA_WIDTH{1'b0}};
            incmd_write_mask <= {(DICE_DATA_WIDTH/8){1'b0}};
            incmd_address <= {DICE_ADDR_WIDTH{1'b0}};
            incmd_size <= 2'b0;
            incmd_ld_dest_reg <= {DICE_MAX_REG_WIDTH{1'b0}};
 
        end
    end
    
    // Checker process: verifies output commands against expected queue
    expected_cmd_t expected;
    logic cmd_match;
    always @(posedge clk_i) begin
        if (rst) begin
            outcmd_ready <= 1'b0;
        end else if (checker_active) begin
            outcmd_ready <= 1'b1;
            if (outcmd_valid)  begin
                if(expected_output_queue.size() > 0) begin
                    expected = expected_output_queue.pop_front();
                    cmd_match = 1'b1;
                    // Accept the command
                    commands_received++;

                    $display("[CHECKER] Checking command %0d: %s", commands_received, expected.description);

                    // Check basic fields
                    if (outcmd_block_id !== expected.block_id) begin
                        $display("❌ FAIL: Block ID mismatch - Expected: %0d, Got: %0d", expected.block_id, outcmd_block_id);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (outcmd_base_tid !== expected.base_tid) begin
                        $display("❌ FAIL: Base TID mismatch - Expected: %0d, Got: %0d", expected.base_tid, outcmd_base_tid);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (outcmd_write_enable !== expected.write_enable) begin
                        $display("❌ FAIL: Write enable mismatch - Expected: %b, Got: %b", expected.write_enable, outcmd_write_enable);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (outcmd_address !== expected.address) begin
                        $display("❌ FAIL: Address mismatch - Expected: 0x%h, Got: 0x%h", expected.address, outcmd_address);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (outcmd_size !== expected.size) begin
                        $display("❌ FAIL: Size mismatch - Expected: %0d, Got: %0d", expected.size, outcmd_size);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (outcmd_ld_dest_reg !== expected.ld_dest_reg) begin
                        $display("❌ FAIL: Load dest reg mismatch - Expected: %0d, Got: %0d", expected.ld_dest_reg, outcmd_ld_dest_reg);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    // Optional checks
                    if (expected.check_tid_bitmap && (outcmd_tid_bitmap !== expected.tid_bitmap)) begin
                        $display("❌ FAIL: TID bitmap mismatch - Expected: 0x%h, Got: 0x%h", expected.tid_bitmap, outcmd_tid_bitmap);
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (expected.check_write_data) begin
                        //need to check only not masked parts
                        for (int i = 0; i < DICE_CACHE_LINE_SIZE; i++) begin
                            if (!expected.write_mask[i] && (outcmd_write_data[i*8 +: 8] !== expected.write_data[i*8 +: 8])) begin
                                $display("❌ FAIL: Write data mismatch at byte %0d - Expected: 0x%h, Got: 0x%h", i, expected.write_data[i*8 +: 8], outcmd_write_data[i*8 +: 8]);
                                cmd_match = 1'b0;
                                fail_count++;
                            end
                        end
                    end

                    if (expected.check_write_mask && (outcmd_write_mask !== expected.write_mask)) begin
                        $display("❌ FAIL: Write mask mismatch");
                        cmd_match = 1'b0;
                        fail_count++;
                    end

                    if (cmd_match) begin
                        $display("✅ PASS: Command verified successfully\n\n\n");
                        pass_count++;
                    end else begin
                        $display("❌ FAIL: Command verification failed");
                        $finish;
                    end

                    test_count++;
                
                end else begin
                    // No valid output command to check
                    $display("[ERROR] No valid output command to check, This output cmd is not expected!!");
                    $display("  Block ID: %0d, Base TID: %0d, TID Bitmap: 0x%h", 
                             outcmd_block_id, outcmd_base_tid, outcmd_tid_bitmap);
                    $display("  Write Enable: %b, Address: 0x%h, Size: %0d, Load Dest Reg: %0d", 
                             outcmd_write_enable, outcmd_address, outcmd_size, outcmd_ld_dest_reg);
                    $display("  Write Data: 0x%h, Write Mask: 0x%h", 
                             outcmd_write_data, outcmd_write_mask);
                    $display("❌ FAIL: Unexpected output command received");
                    $finish;
                end
            end
            
            // Stop checker when expected queue is empty and no more outputs expected
            if (expected_output_queue.size() == 0 && !outcmd_valid) begin
                checker_active <= 1'b0;
                $display("[CHECKER] All expected outputs verified, checker stopped");
                test_complete <= 1'b1;
            end
        end
    end
    
    // Task to reset the design
    task automatic reset_dut();
        begin
            @(negedge clk_i); // Align to the negative edge first
            rst = 1;
            driver_active = 0;
            checker_active = 0;
            test_complete = 0;
            commands_sent = 0;
            commands_received = 0;
            test_count = 0;
            pass_count = 0;
            fail_count = 0;
            
            // Clear queues
            input_queue.delete();
            expected_output_queue.delete();
            
            repeat(5) @(negedge clk_i); // Hold reset for 5 negative edges
            rst = 0;
            @(posedge clk_i);
            $display("Reset complete at time %0t", $time);
        end
    endtask
    
    // Task to start test execution
    task automatic start_test(input string test_name);
        begin
            current_test_name = test_name;
            $display("\n=== Starting %s at time %0t ===", test_name, $time);
            driver_active = 1;
            checker_active = 1;
            test_complete = 0;
        end
    endtask
    
    // Task to wait for test completion
    task automatic wait_for_test_complete();
        begin
            wait(expected_output_queue.size() == 0 && !outcmd_valid);
        end
    endtask
    
    // Main test sequence
    logic [DICE_CACHE_LINE_SIZE*8-1:0]  expected_write_data;
    int real_tid_base;

    // Parameterized variables for testbenches
    logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_temp = 'd1;
    logic [DICE_EBLOCK_ID_WIDTH-1:0] e_block_temp_2 = 'd3;
    logic [DICE_DATA_WIDTH-1:0] write_data_temp = 'd0;
    logic [DICE_DATA_WIDTH-1:0] write_data_temp2 = 'hDEADBEEF_00000000;
    logic [DICE_DATA_WIDTH-1:0] write_data_temp3 = 'h00000000_DEADBEEF;
    logic [DICE_DATA_WIDTH/8-1:0] write_mask_temp = 'h00;
    logic [DICE_ADDR_WIDTH-1:0] addr_data_temp = 'd0;
    logic [DICE_ADDR_WIDTH-1:0] addr_data_temp2 = 'hDEADBEEF_00000000;
    logic [DICE_ADDR_WIDTH-1:0] addr_data_temp3 = 'hDEEDBEEB_00000000;
    logic [DICE_MAX_REG_WIDTH-1:0] ld_dest_reg_temp = 'd10;
    logic [DICE_TID_BITMAP_WIDTH-1:0] bitmap_temp = 'hFF;
    


    initial begin
        $display("=== Starting Temporal Coalescing Unit Testbench ===\n");
        
        // Elaborate-time power-of-2 parameter check
   
        assert ((DICE_NUMBER_OF_MAX_COALESCED_COMMANDS > 0) &&
                ((DICE_NUMBER_OF_MAX_COALESCED_COMMANDS &
                  (DICE_NUMBER_OF_MAX_COALESCED_COMMANDS - 1)) == 0))
        else $fatal(1,
            "DICE_NUMBER_OF_MAX_COALESCED_COMMANDS (%0d) must be a power of 2.",
            DICE_NUMBER_OF_MAX_COALESCED_COMMANDS);



        reset_dut();
        
        // ============================================================
        // Test 1: Perfect Write coalescing
        // ============================================================
        // Setup input commands
        for(int i=0;i<128;i++) begin
            add_input_command(
                .block_id(e_block_temp), .tid(i), .write_enable(1'b1),
                .write_data(write_data_temp + i), .write_mask(write_data_temp),
                .address(addr_data_temp + (i)), .size(2'b00), .ld_dest_reg(ld_dest_reg_temp),
                .description($sformatf("Store TID %0d to 0x%h", i, 64'd0 + (i * 4)))
            );
        end

        // Setup expected outputs
        for(int i=0;i<16;i++)begin
            for(int j=0;j<8;j++)begin
                expected_write_data[j*8+:8]=(i*8+j);
            end
            real_tid_base=i*8;
            add_expected_output(
                .block_id(e_block_temp),.base_tid({real_tid_base[9:DICE_BASE_TID_ADDRESS_OFFSET],{DICE_BASE_TID_ADDRESS_OFFSET{1'b0}}}),.tid_bitmap(bitmap_temp),
                .write_enable(1'b1),.write_data(expected_write_data),.write_mask(write_mask_temp),
                .address(i<<3),.size(2'b00),.ld_dest_reg(ld_dest_reg_temp),
                .description("Expected perfect coalesced store output"),
                .check_tid_bitmap(1'b1),.check_write_data(1'b1),.check_write_mask(1'b1)
            );
        end

        
        
        start_test("Perfect Write Coalescing");
        wait_for_test_complete();



        // ============================================================
        // Test 2: Perfect Read coalescing
        // ============================================================
        // Setup input commands
        for(int i=0;i<128;i++)begin
            add_input_command(
                .block_id(e_block_temp),.tid(i+512),.write_enable(1'b0),
                .write_data(write_data_temp),.write_mask(write_mask_temp),
                .address(addr_data_temp2+i),.size(2'b00),.ld_dest_reg(ld_dest_reg_temp),
                .description($sformatf("Load TID %0d from 0x%h",i,64'hDEADBEEF_00000000+i))
            );
        end
        
        for(int i=0;i<16;i++)begin
            real_tid_base=i*8+512;
            add_expected_output(
                .block_id(e_block_temp),.base_tid({real_tid_base[9:DICE_BASE_TID_ADDRESS_OFFSET],{DICE_BASE_TID_ADDRESS_OFFSET{1'b0}}}),.tid_bitmap(bitmap_temp),
                .write_enable(1'b0),.write_data(write_data_temp),.write_mask(write_mask_temp),
                .address(addr_data_temp2+(i<<3)),.size(2'b00),.ld_dest_reg(ld_dest_reg_temp),
                .description("Expected perfect coalesced load output"),
                .check_tid_bitmap(1'b1),.check_write_data(1'b0),.check_write_mask(1'b0)
            );
        end
        start_test("Perfect Read Coalescing");
        wait_for_test_complete();


        // ============================================================
        // Test 3: Bad write coalescing
        // ============================================================
        // Setup input commands
        for(int i=0;i<128;i++) begin
            add_input_command(
                .block_id(e_block_temp_2), .tid(i), .write_enable(1'b1),
                .write_data(write_data_temp2*i), .write_mask(write_mask_temp),
                .address(addr_data_temp3 + (i*32)), .size(2'b10), .ld_dest_reg(ld_dest_reg_temp),
                .description($sformatf("Store TID %0d to 0x%h", i, 64'hDEEDBEEB_00000000 + (i*4) + (i*32)))
            );
        end
        
        for(int i=0;i<128;i++) begin

            add_expected_output(
                .block_id(e_block_temp_2), .base_tid({i[9:DICE_BASE_TID_ADDRESS_OFFSET],{DICE_BASE_TID_ADDRESS_OFFSET{1'b0}}}), 
                .tid_bitmap(1<<(i % DICE_NUMBER_OF_MAX_COALESCED_COMMANDS)), // Corrected shift logic for bitmap
                .write_enable(1'b1), .write_data(write_data_temp3*i), .write_mask(write_mask_temp),
                .address(addr_data_temp3+ (i<<5)), .size(2'b10), .ld_dest_reg(ld_dest_reg_temp),
                .description("Expected Bad write store output"),
                .check_tid_bitmap(1'b1), .check_write_data(1'b1), .check_write_mask(1'b1)
            );
        end
        start_test("Bad write Coalescing");
        wait_for_test_complete();


        // ============================================================
        // Test 4: Bad read coalescing
        // ============================================================
        // Setup input commands
        for(int i=0;i<128;i++) begin
            add_input_command(
                .block_id(e_block_temp_2), .tid(i), .write_enable(1'b0),
                .write_data(write_data_temp3*i), .write_mask(write_mask_temp),
                .address(addr_data_temp3 + (i*32)), .size(2'b10), .ld_dest_reg(ld_dest_reg_temp),
                .description($sformatf("load TID %0d to 0x%h", i, 64'hDEEDBEEB_00000000 + (i*4) + (i*32)))
            );
        end
        
        for(int i=0;i<128;i++) begin

            add_expected_output(
                .block_id(e_block_temp_2), .base_tid({i[9:DICE_BASE_TID_ADDRESS_OFFSET],{DICE_BASE_TID_ADDRESS_OFFSET{1'b0}}}), 
                .tid_bitmap(1<<(i % DICE_NUMBER_OF_MAX_COALESCED_COMMANDS)), // Corrected shift logic for bitmap
                .write_enable(1'b0), .write_data(write_data_temp3*i), .write_mask(write_mask_temp),
                .address(addr_data_temp3 + (i<<5)), .size(2'b10), .ld_dest_reg(ld_dest_reg_temp),
                .description("Expected Bad read output"),
                .check_tid_bitmap(1'b1), .check_write_data(1'b0), .check_write_mask(1'b0)
            );
        end
        start_test("Bad read Coalescing");
        wait_for_test_complete();
        
        
        
        // ============================================================
        // Final Results
        // ============================================================
        $display("\n=== Test Summary ===");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("Commands sent: %0d", commands_sent);
        $display("Commands received: %0d", commands_received);
        $display("Input queue final size: %0d", input_queue.size());
        $display("Expected queue final size: %0d", expected_output_queue.size());
        
        if (fail_count == 0 && input_queue.size() == 0 && expected_output_queue.size() == 0) begin
            $display("🎉 ALL TESTS PASSED!");
        end else begin
            $display("💥 %0d TESTS FAILED", fail_count);
            if (input_queue.size() > 0) $display("⚠️  %0d input commands not sent", input_queue.size());
            if (expected_output_queue.size() > 0) $display("⚠️  %0d expected outputs not received", expected_output_queue.size());
        end
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 100000);
        $display("❌ TIMEOUT: Test took too long");
        $display(" There are still %0d expected output commands left in the queue\n\n", expected_output_queue.size());
        $display("\n=== Test Summary ===");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("Commands sent: %0d", commands_sent);
        $display("Commands received: %0d", commands_received);
        $display("Input queue final size: %0d", input_queue.size());
        $display("Expected queue final size: %0d", expected_output_queue.size());
        $finish;
    end

    initial begin
    //dump fsdb
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars("+all");
    end
endmodule