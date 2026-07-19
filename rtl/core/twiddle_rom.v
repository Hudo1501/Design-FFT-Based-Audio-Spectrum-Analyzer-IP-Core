// =============================================================================
// Module : twiddle_rom   (doc DONG BO, 1 chu ky latency)
// -----------------------------------------------------------------------------
// Luu N/2 he so twiddle W_N^k = exp(-2*pi*j*k/N), k=0..N/2-1, Q1.15, tach thanh
// 2 ROM re/im (nap tu twiddle_re.mem / twiddle_im.mem bang $readmemh, sinh boi
// gen_twiddle_rom.py). Doc DONG BO (thanh ghi output) => 1 chu ky latency; bao
// gio cung phai canh du lieu tuong ung (xem stage_with_twiddle.v — bai hoc bug
// "lech tre ROM vs du lieu" muc 4 tai lieu tien do).
// =============================================================================
`timescale 1ns / 1ps

module twiddle_rom #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter         RE_FILE    = "twiddle_re.mem",
    parameter         IM_FILE    = "twiddle_im.mem"
)(
    input  wire                          clk,
    input  wire                          en,     // clock-enable (=valid)
    input  wire [$clog2(N/2)-1:0]        addr,       // 0..N/2-1 (7-bit voi N=256)
    output reg  signed [DATA_WIDTH-1:0]  tw_re,
    output reg  signed [DATA_WIDTH-1:0]  tw_im
);
    reg signed [DATA_WIDTH-1:0] rom_re [0:N/2-1];
    reg signed [DATA_WIDTH-1:0] rom_im [0:N/2-1];

    initial begin
        $readmemh(RE_FILE, rom_re);
        $readmemh(IM_FILE, rom_im);
    end

    always @(posedge clk) begin
        if (en) begin
            tw_re <= rom_re[addr];
            tw_im <= rom_im[addr];
        end
    end
endmodule
