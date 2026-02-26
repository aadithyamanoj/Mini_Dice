module naive_dispatcher #(
    parameter TOTAL_TID = 512
)(
    input logic clk,
    input logic rst_n,
    input logic enable,
    input logic clr,
    input logic [$clog2(TOTAL_TID)-1:0] max_tid,
    output logic done,
    output logic [$clog2(TOTAL_TID)-1:0] dispatch_tid,
    input logic [$clog2(TOTAL_TID)-1:0] ntid_x,
    input logic [$clog2(TOTAL_TID)-1:0] ntid_y,
    input logic [$clog2(TOTAL_TID)-1:0] ntid_z,
    output logic [$clog2(TOTAL_TID)-1:0] tid_x,
    output logic [$clog2(TOTAL_TID)-1:0] tid_y,
    output logic [$clog2(TOTAL_TID)-1:0] tid_z,
    output logic tid_valid
);  

    enum {IDLE, DISPATCH, DONE} state, state_next;

    //state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= state_next;
        end
    end

    always_comb begin
        if (!rst_n || clr) begin
            state_next = IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (enable) begin
                        state_next = DISPATCH;
                    end else begin
                        state_next = IDLE;
                    end
                end
                DISPATCH: begin
                    if (dispatch_tid == max_tid) begin
                        state_next = DONE;
                    end else begin
                        state_next = DISPATCH;
                    end
                end
                DONE: begin
                    if(clr) begin
                        state_next = IDLE;
                    end else begin
                        state_next = DONE;
                    end
                end
                default: state_next = IDLE;
            endcase
        end
    end

    assign done = (state == DONE);
    assign tid_valid = (state == DISPATCH);
    //dispatch tid counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dispatch_tid <= '0;
        end else if (clr) begin
            dispatch_tid <= '0;
        end else if (state == IDLE) begin
            dispatch_tid <= '0;
        end else if (state == DISPATCH) begin
            if(enable) begin
                dispatch_tid <= dispatch_tid + 1;
            end else begin
                dispatch_tid <= dispatch_tid;
            end
        end else if (state == DONE) begin
            dispatch_tid <= '0;
        end
    end



    assign tid_x = dispatch_tid % (ntid_x+1);
    assign tid_y = (dispatch_tid / (ntid_x+1)) % (ntid_y+1);
    assign tid_z = (dispatch_tid / ((ntid_x+1) * (ntid_y+1))) % (ntid_z+1);
endmodule