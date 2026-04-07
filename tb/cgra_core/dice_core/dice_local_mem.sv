module dice_local_mem
  import dice_pkg::*;
#(
    parameter int SIZE      = (1 << 26),
    parameter int TAG_WIDTH = DICE_ADDR_WIDTH,
    parameter int WORD_SIZE = DICE_MEM_DATA_WIDTH / 8
) (
    input logic clk,
    input logic reset,
    dice_mem_bus_if.slave mem_bus_if
);

  localparam int WORD_WIDTH = WORD_SIZE * 8;
  localparam int NUM_WORDS  = SIZE / WORD_SIZE;

  logic [WORD_WIDTH-1:0] ram [0:NUM_WORDS-1];
  logic                  rsp_valid_q;
  logic [WORD_WIDTH-1:0] rsp_data_q;
  logic [TAG_WIDTH-1:0]  rsp_tag_q;

  wire rsp_handshake = mem_bus_if.rsp_valid && mem_bus_if.rsp_ready;
  wire req_handshake = mem_bus_if.req_valid && mem_bus_if.req_ready;

  assign mem_bus_if.req_ready        = !rsp_valid_q || rsp_handshake;
  assign mem_bus_if.rsp_valid        = rsp_valid_q;
  assign mem_bus_if.rsp_data.data    = rsp_data_q;
  assign mem_bus_if.rsp_data.tag.uuid = rsp_tag_q;

  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      rsp_valid_q <= 1'b0;
      rsp_data_q  <= '0;
      rsp_tag_q   <= '0;
    end else begin
      if (rsp_handshake) begin
        rsp_valid_q <= 1'b0;
      end

      if (req_handshake) begin
        if (mem_bus_if.req_data.rw) begin
          for (int i = 0; i < WORD_SIZE; i++) begin
            if (mem_bus_if.req_data.byteen[i]) begin
              ram[mem_bus_if.req_data.addr][i*8 +: 8] <= mem_bus_if.req_data.data[i*8 +: 8];
            end
          end
        end else begin
          rsp_valid_q <= 1'b1;
          rsp_data_q  <= ram[mem_bus_if.req_data.addr];
          rsp_tag_q   <= mem_bus_if.req_data.tag.uuid;
        end
      end
    end
  end

endmodule
