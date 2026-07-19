// =============================================================================
// Module : magnitude_unit
// -----------------------------------------------------------------------------
// Tinh bien do pho |X[k]| tu cap so phuc (re,im) do loi FFT xuat ra, dung xap
// xi ALPHA-MAX-BETA-MIN (Lyons, "Understanding DSP") thay vi bo can bac hai
// dat tai nguyen:
//
//     |X[k]| ~ alpha*max(|re|,|im|) + beta*min(|re|,|im|)
//     alpha = 0.96043387, beta = 0.39782473  (he so toi uu sai so lon nhat)
//
// Dinh dang output: out_magnitude la UNSIGNED 16-bit (khac voi in_re/in_im
// la SIGNED Q1.15). Vi bien do luon khong am va co the vuot nhe qua 1.0 (do
// alpha+beta ~ 1.358 > 1), dung dinh dang UNSIGNED voi CUNG trong so LSB
// (32768 = 1.0) cho phep bieu dien toi ~2.0 ma khong can bao hoa trong da so
// truong hop thuc te (gia tri toi da ly thuyet la 44507, van nam trong pham
// vi unsigned 16-bit 0..65535).
//
// Vi tri bin (out_bin_idx) duoc TU SUY RA tu in_sof/in_last (dem tu 0 moi khi
// gap in_sof), giong cach lam trong window_unit.v -- module downstream
// (peak_detector.v, bin_ram_output.v) khong can tu dem lai. LUU Y: neu loi
// FFT xuat theo thu tu BIT-REVERSED (mac dinh cua kien truc R2^2SDF, xem
// spec), thi out_bin_idx o day cung la chi so theo THU TU DEN (arrival
// order = bit-reversed), KHONG PHAI chi so tan so tu nhien. Viec sap xep lai
// ve thu tu tu nhien (neu can) thuoc ve module bin_ram_output.v (chua trien
// khai trong ban nay).
//
// -----------------------------------------------------------------------------
// TUY CHON (ENABLE_LOG=1): xuat them out_mag_log2 = log2(magnitude thuc,
// KHONG phai gia tri nguyen raw) dang Q8.8 signed, dung ky thuat "leading-one
// detection + noi suy tuyen tinh phan thap phan" (log2(1+x) ~ x). Day la XAP
// XI cho muc dich HIEN THI (vd truc dB), KHONG chinh xac bit-exact nhu cac
// phep tinh so hoc khac trong du an -- sai so tuyet doi toi da khoang 0.09
// (don vi log2, tuong duong ~0.54 dB) da duoc kiem chung bang cach doi
// chieu voi math.log2 cua Python tren toan bo dai gia tri magnitude.
//
// Latency: 1 chu ky dong ho (toan bo pipeline: abs -> max/min -> nhan+cong ->
// lam tron/bao hoa -> (tuy chon) log2, deu to hop trong CUNG 1 tang, chi
// thanh ghi output la dong bo).
// =============================================================================

`timescale 1ns / 1ps

module magnitude_unit #(
    parameter integer NUM_BINS   = 128,   // so bin magnitude xuat ra (thuong = N/2)
    parameter integer DATA_WIDTH = 16,    // do rong Q1.15 cua re/im dau vao
    parameter integer ENABLE_LOG = 1      // 1 = co tinh them out_mag_log2 xap xi
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              in_valid,
    input  wire signed [DATA_WIDTH-1:0]      in_re,
    input  wire signed [DATA_WIDTH-1:0]      in_im,
    input  wire                              in_sof,   // bin dau tien cua frame
    input  wire                              in_last,  // bin cuoi cung cua frame

    output reg                               out_valid,
    output reg  [DATA_WIDTH-1:0]             out_magnitude,   // UNSIGNED
    output reg  [$clog2(NUM_BINS)-1:0]       out_bin_idx,
    output reg                               out_sof,
    output reg                               out_last,
    output reg  signed [15:0]                out_mag_log2     // Q8.8 signed (chi dung neu ENABLE_LOG=1)
);

    localparam integer BIN_ADDR_W = $clog2(NUM_BINS);

    // He so alpha/beta Q1.15 UNSIGNED (round(alpha*32768), round(beta*32768))
    localparam [DATA_WIDTH-1:0] ALPHA_Q15 = 16'd31471;  // 0.96043387
    localparam [DATA_WIDTH-1:0] BETA_Q15  = 16'd13036;  // 0.39782473

    // -------------------------------------------------------------------
    // Bo dem vi tri bin trong frame (dia chi/chi so), tu suy ra tu in_sof
    // (cung ky thuat voi window_unit.v)
    // -------------------------------------------------------------------
    reg [BIN_ADDR_W-1:0] prev_idx;
    wire [BIN_ADDR_W-1:0] cur_idx = in_sof ? {BIN_ADDR_W{1'b0}} : (prev_idx + 1'b1);

    always @(posedge clk) begin
        if (!rst_n)
            prev_idx <= {BIN_ADDR_W{1'b0}};
        else if (in_valid)
            prev_idx <= cur_idx;
    end

    // -------------------------------------------------------------------
    // |re|, |im| (UNSIGNED 16-bit, xu ly dung truong hop bien -32768)
    // -------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] abs_re = in_re[DATA_WIDTH-1] ? (~in_re + 1) : in_re;
    wire [DATA_WIDTH-1:0] abs_im = in_im[DATA_WIDTH-1] ? (~in_im + 1) : in_im;

    wire [DATA_WIDTH-1:0] mx = (abs_re > abs_im) ? abs_re : abs_im;
    wire [DATA_WIDTH-1:0] mn = (abs_re > abs_im) ? abs_im : abs_re;

    // -------------------------------------------------------------------
    // alpha*mx + beta*mn (UNSIGNED, khong can bit du phong nhu truong hop
    // signed truoc do vi day la nhan/cong toan UNSIGNED)
    // -------------------------------------------------------------------
    wire [2*DATA_WIDTH-1:0] prod_mx  = ALPHA_Q15 * mx;   // 32-bit, du du
    wire [2*DATA_WIDTH-1:0] prod_mn  = BETA_Q15  * mn;
    wire [2*DATA_WIDTH:0]   mag_full = prod_mx + prod_mn; // 33-bit, an toan

    localparam integer SHIFT = DATA_WIDTH - 1;  // 15, dua Q2.30 ve lai Q1.15-equivalent

    // Dich phai SHIFT bit voi round-half-to-even (UNSIGNED, khong co van de
    // dau am nhu ham signed truoc do, nhung van dung literal "1" cho thong
    // nhat/an toan)
    function automatic [DATA_WIDTH-1:0] round_sat_unsigned;
        input [2*DATA_WIDTH:0] full;
        reg   [2*DATA_WIDTH:0] shifted;
        reg   [SHIFT-2:0]      lower_bits;
        begin
            lower_bits = full[SHIFT-2:0];

            if (full[SHIFT-1] == 1'b0) begin
                shifted = full >> SHIFT;
            end else if (lower_bits != 0) begin
                shifted = (full >> SHIFT) + 1;
            end else begin
                if (full[SHIFT] == 1'b0)
                    shifted = full >> SHIFT;
                else
                    shifted = (full >> SHIFT) + 1;
            end

            // bao hoa phong ho (ly thuyet toi da ~44507, khong bao gio vuot
            // 65535, nhung van kiem tra cho chac chan/an toan)
            if (shifted > {DATA_WIDTH{1'b1}})
                round_sat_unsigned = {DATA_WIDTH{1'b1}};
            else
                round_sat_unsigned = shifted[DATA_WIDTH-1:0];
        end
    endfunction

    wire [DATA_WIDTH-1:0] mag_rounded = round_sat_unsigned(mag_full);

    // -------------------------------------------------------------------
    // (Tuy chon) log2(magnitude) xap xi: leading-one-detect + noi suy
    // tuyen tinh phan mantissa. Ket qua la Q8.8 signed, dung tren gia tri
    // magnitude THUC (da tru di 15 bit dich Q1.15). LUON duoc tinh (chi phi
    // logic thap) de tranh tham chieu hierarchical vao trong generate block
    // -- ENABLE_LOG chi con y nghia "downstream co nen dung out_mag_log2
    // hay khong", cong cu tong hop se tu loai bo logic thua neu that su
    // khong dung toi.
    // -------------------------------------------------------------------
    function automatic [4:0] find_msb_pos;
        input [DATA_WIDTH-1:0] val;
        integer k;
        reg found;
        begin
            find_msb_pos = 5'd0;
            found = 1'b0;
            for (k = DATA_WIDTH-1; k >= 0; k = k - 1) begin
                if (!found && val[k]) begin
                    find_msb_pos = k[4:0];
                    found = 1'b1;
                end
            end
        end
    endfunction

    wire [4:0] msb_pos = find_msb_pos(mag_rounded);

    // chuan hoa: dich trai de bit leading-one nam o vi tri DATA_WIDTH-1,
    // phan con lai (duoi bit leading-one) chinh la (mantissa-1) o dang
    // Q0.(DATA_WIDTH-1)
    wire [DATA_WIDTH-1:0] normalized = mag_rounded << (DATA_WIDTH-1 - msb_pos);

    // lay 8 bit cao nhat sau bit leading-one lam phan thap phan Q0.8
    wire [7:0] frac_q8 = normalized[DATA_WIDTH-2 -: 8];

    // phan nguyen thuc su cua log2: msb_pos - SHIFT (SHIFT=15, vi
    // mag_rounded dang o thang Q1.15-equivalent, gia tri "1.0 that" nam
    // o bit vi tri 15)
    wire signed [7:0] int_part = $signed({1'b0, msb_pos}) - SHIFT[7:0];

    wire signed [15:0] log2_q8_8 = (mag_rounded == 0)
                                    ? -16'sd32768  // sentinel cho log2(0) = -vo cung
                                    : ($signed({int_part, 8'd0}) + $signed({8'd0, frac_q8}));

    // -------------------------------------------------------------------
    // Thanh ghi output (1 chu ky latency)
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid     <= 1'b0;
            out_magnitude <= {DATA_WIDTH{1'b0}};
            out_bin_idx   <= {BIN_ADDR_W{1'b0}};
            out_sof       <= 1'b0;
            out_last      <= 1'b0;
            out_mag_log2  <= 16'sd0;
        end else begin
            out_valid     <= in_valid;
            out_magnitude <= mag_rounded;
            out_bin_idx   <= cur_idx;
            out_sof       <= in_valid && in_sof;
            out_last      <= in_valid && in_last;
            out_mag_log2  <= ENABLE_LOG ? log2_q8_8 : 16'sd0;
        end
    end

endmodule
