`timescale 1ns / 1ps

module fft_control_fsm #(
    parameter integer CNT_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,        
    input  wire                    frame_tick,   
    output reg                     core_en,      
    output reg                     busy,
    output reg                     frame_done, 
    output reg  [CNT_WIDTH-1:0]    frame_count
);
    localparam IDLE = 1'b0, RUN = 1'b1;
    reg state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; core_en<=1'b0; busy<=1'b0;
            frame_done<=1'b0; frame_count<={CNT_WIDTH{1'b0}};
        end else begin
            frame_done <= 1'b0;                     
            case (state)
                IDLE: begin
                    core_en <= 1'b0; busy <= 1'b0;
                    if (start) begin state<=RUN; core_en<=1'b1; busy<=1'b1; end
                end
                RUN: begin
                    core_en <= 1'b1; busy <= 1'b1;
                    if (frame_tick) begin
                        frame_done  <= 1'b1;
                        frame_count <= frame_count + 1'b1;
                    end
                    if (!start) begin state<=IDLE; core_en<=1'b0; busy<=1'b0; end
                end
            endcase
        end
    end
endmodule
