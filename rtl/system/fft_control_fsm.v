// =============================================================================
// Module : fft_control_fsm   (dieu khien & trang thai TONG)
// -----------------------------------------------------------------------------
// Datapath la SELF-TIMED (moi tang co bo dem rieng reset boi sof), nen khoi nay
// KHONG dieu khien tung tang ma dong vai tro CONTROL/STATUS tong:
//   - IDLE -> RUN khi 'start'; RUN -> IDLE khi '~start'.
//   - core_en: cho phep pipeline chay (co the noi toi 'en'/soft-reset neu muon).
//   - dem so frame da hoan tat (frame_tick = 1 xung/ frame, vd noi toi peak_valid
//     hoac spec_last), phat frame_done + frame_count.
//   - busy: dang xu ly.
// rst_n active-low.
// =============================================================================
`timescale 1ns / 1ps

module fft_control_fsm #(
    parameter integer CNT_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,        // muc: chay khi cao
    input  wire                    frame_tick,   // 1 xung khi 1 frame ra xong
    output reg                     core_en,      // cho phep loi chay
    output reg                     busy,
    output reg                     frame_done,   // 1 xung / frame
    output reg  [CNT_WIDTH-1:0]    frame_count
);
    localparam IDLE = 1'b0, RUN = 1'b1;
    reg state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state<=IDLE; core_en<=1'b0; busy<=1'b0;
            frame_done<=1'b0; frame_count<={CNT_WIDTH{1'b0}};
        end else begin
            frame_done <= 1'b0;                      // mac dinh 0 (xung 1 chu ky)
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
