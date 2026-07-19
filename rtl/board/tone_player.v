// =============================================================================
// Module : tone_player   (phat lai vector thu tu ROM, dung toc do fs)
// -----------------------------------------------------------------------------
// Doc tv_input.mem (256 mau Q1.15, tin hieu 2-tone dinh o bin 10 & 37 -- CHINH
// LA vector vang da dung trong tb_fft_r22sdf) va phat lien tuc, LAP VONG, voi
// 1 xung out_valid moi CLK_PER_SAMPLE chu ky => mo phong nguon audio fs.
//
// Muc dich: SELF-TEST tren board that -- neu chuoi FFT dung, peak_bin_idx phai
// = 10. Cho phep kiem toan he thong tren board MA KHONG can mic/codec.
// Cung la cach kiem tra VALID-GATING that su hoat dong (valid rat thua: 1 mau
// moi ~2000 chu ky).
// =============================================================================
`timescale 1ns / 1ps

module tone_player #(
    parameter integer N               = 256,
    parameter integer DATA_WIDTH      = 16,
    parameter integer CLK_PER_SAMPLE  = 2083,   // 100MHz/48kHz ~= 2083
    parameter         TONE_FILE       = "tv_input.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          en,
    output reg                           out_valid,
    output reg  signed [DATA_WIDTH-1:0]  out_data
);
    localparam integer AW = $clog2(N);
    localparam integer CW = $clog2(CLK_PER_SAMPLE);

    reg signed [DATA_WIDTH-1:0] rom [0:N-1];
    initial $readmemh(TONE_FILE, rom);

    reg [CW-1:0] div;
    reg [AW-1:0] addr;

    always @(posedge clk) begin
        if (!rst_n) begin
            div <= 0; addr <= 0; out_valid <= 1'b0; out_data <= 0;
        end else if (!en) begin
            div <= 0; out_valid <= 1'b0;
        end else begin
            if (div == CLK_PER_SAMPLE-1) begin
                div       <= 0;
                out_valid <= 1'b1;
                out_data  <= rom[addr];
                addr      <= addr + 1'b1;     // tu quay vong khi tran (N la luy thua 2)
            end else begin
                div       <= div + 1'b1;
                out_valid <= 1'b0;
            end
        end
    end
endmodule
