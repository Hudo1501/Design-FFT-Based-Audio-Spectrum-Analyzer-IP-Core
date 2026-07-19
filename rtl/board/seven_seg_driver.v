// =============================================================================
// Module : seven_seg_driver   (quet 8 digit 7-doan, common anode -- Nexys A7)
// -----------------------------------------------------------------------------
// Hien thi 8 chu so HEX (32-bit value) tren 8 digit. Quet ~1kHz/digit.
// Nexys A7: cathode (CA..CG,DP) va anode (AN0..7) deu TICH CUC MUC THAP.
// =============================================================================
`timescale 1ns / 1ps

module seven_seg_driver #(
    parameter integer CLK_HZ  = 100_000_000,
    parameter integer SCAN_HZ = 800          // toc do quet moi digit
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] value,      // 8 chu so hex
    input  wire [7:0]  digit_en,   // 1 = bat digit tuong ung
    output reg  [6:0]  seg,        // {CG,CF,CE,CD,CC,CB,CA} tich cuc THAP
    output reg         dp,         // tich cuc THAP
    output reg  [7:0]  an          // tich cuc THAP
);
    localparam integer DIV = CLK_HZ/(SCAN_HZ*8);
    localparam integer CW  = $clog2(DIV);

    reg [CW-1:0] div_cnt;
    reg [2:0]    sel;
    always @(posedge clk) begin
        if (!rst_n) begin div_cnt<=0; sel<=0; end
        else if (div_cnt == DIV-1) begin div_cnt<=0; sel<=sel+1'b1; end
        else div_cnt <= div_cnt + 1'b1;
    end

    reg [3:0] nib;
    always @(*) begin
        case (sel)
            3'd0: nib = value[3:0];    3'd1: nib = value[7:4];
            3'd2: nib = value[11:8];   3'd3: nib = value[15:12];
            3'd4: nib = value[19:16];  3'd5: nib = value[23:20];
            3'd6: nib = value[27:24];  default: nib = value[31:28];
        endcase
    end

    // bang ma 7-doan (tich cuc THAP): bit0=CA ... bit6=CG
    always @(*) begin
        case (nib)
            4'h0: seg = 7'b1000000;  4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;  4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;  4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;  4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;  4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;  4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;  4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;  default: seg = 7'b0001110;  // F
        endcase
        dp = 1'b1;                       // tat dau cham
        an = ~(digit_en & (8'b1 << sel)); // chi bat digit dang quet (tich cuc thap)
    end
endmodule
