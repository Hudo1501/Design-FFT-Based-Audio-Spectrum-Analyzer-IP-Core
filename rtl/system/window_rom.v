// =============================================================================
// Module : window_rom
// -----------------------------------------------------------------------------
// ROM luu he so cua so (window coefficient) w[n], n = 0..N-1, dinh dang Q1.15
// 16-bit signed. Noi dung sinh boi gen_window_coeff.py, nap qua $readmemh.
//
// LUA CHON THIET KE: doc KET HOP (asynchronous/combinational read), khac voi
// twiddle_rom.v (doc dong bo, 1 chu ky latency). Ly do: kich thuoc ROM nay
// (N=256 x 16-bit = 512 byte) van du nho de tong hop hieu qua thanh LUTRAM
// (distributed RAM) doc khong dong bo tren FPGA hien dai, va cach nay giup
// don gian hoa dang ke logic canh (align) du lieu trong window_unit.v -- bai
// hoc rut ra tu qua trinh phat trien twiddle_rom.v/complex_multiplier.v, noi
// viec quen canh tre 1 chu ky giua ROM va du lieu da gay loi tich hop. Neu
// sau nay muon ep ROM nay thanh BRAM (vd de tiet kiem LUT khi N lon hon),
// can chuyen sang doc dong bo va them thanh ghi tre du lieu tuong tu cach
// twiddle_rom.v + complex_multiplier.v da lam.
// =============================================================================

`timescale 1ns / 1ps

module window_rom #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter         COEFF_FILE = "window_coeff.mem"
)(
    input  wire [$clog2(N)-1:0]         addr,
    output wire signed [DATA_WIDTH-1:0] coeff
);

    reg signed [DATA_WIDTH-1:0] rom [0:N-1];

    initial begin
        $readmemh(COEFF_FILE, rom);
    end

    assign coeff = rom[addr];

endmodule
