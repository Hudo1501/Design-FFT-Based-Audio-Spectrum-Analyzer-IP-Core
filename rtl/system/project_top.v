// =============================================================================
// Module : project_top   (TICH HOP HE THONG — FFT Audio Spectrum Analyzer IP)
// -----------------------------------------------------------------------------
// Noi toan bo chuoi xu ly, san sang tong hop/mo phong tren Vivado:
//
//   AXI4-Stream audio in
//        │  (s_axis_tvalid/tdata/tready)
//        ▼
//   input_buffer_fsm   ── double-buffer ping-pong, gom N=256 mau/frame,
//        │  valid/sof/last   xuat 1 mau/chu ky (co the co 1 bubble giua cac frame)
//        ▼
//   window_unit        ── nhan cua so Hann (window_rom, Q1.15)
//        │  valid/sof/last
//        ▼
//   fft_r22sdf_top     ── FFT 256 diem R2SDF (in_im=0), xuat X[k] PHUC
//        │  valid/sof/last   THU TU BIT-REVERSED ; datapath valid-gated (chiu bubble)
//        ▼
//   magnitude_unit     ── |X[k]| = alpha*max+beta*min (UNSIGNED 16-bit) [+ log2 Q8.8]
//        │  valid/sof/last   van o thu tu bit-reversed
//        ├─────────────────────────────┐
//        ▼                             ▼
//   bin_ram_output               (magnitude bit-reversed -> peak trung gian khong dung)
//   (bit-reversed -> TU NHIEN,        
//    N/2=128 bin don bien)             
//        │  valid/sof/last/bin_idx      
//        ▼                             
//   peak_detector  ── tim bin co magnitude lon nhat MOI FRAME (bin TU NHIEN)
//        │
//        ▼  peak_valid / peak_magnitude / peak_bin_idx  (bin tan so that: f=bin*fs/N)
//
// LUU Y HOP DONG (streaming): loi FFT R2SDF da duoc VALID-GATED (them clock-enable
// = valid o twiddle_rom/complex_multiplier/stage_with_twiddle va delay-line framing),
// nen chiu duoc cac chu ky valid=0 (bubble) ma input_buffer_fsm chen giua cac frame.
// Tham so FFT_LATENCY (mac dinh 283 mau-valid) da do bang mo phong cycle-accurate;
// HAY chay tb_fft_r22sdf.v tren Vivado de xac nhan va chinh lai neu can (testbench
// tu do va in ra latency thuc te).
//
// Tat ca dung rst_n (active-low), Q1.15 signed cho du lieu phuc, magnitude UNSIGNED.
// =============================================================================
`timescale 1ns / 1ps

module project_top #(
    parameter integer N            = 256,
    parameter integer DATA_WIDTH   = 16,
    parameter integer FFT_LATENCY  = 291,               // mau-valid (do bang TB)
    parameter integer ENABLE_LOG   = 1,
    parameter         WINDOW_FILE  = "window_coeff.mem",
    parameter         TW_RE_FILE   = "twiddle_re.mem",
    parameter         TW_IM_FILE   = "twiddle_im.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // ---- AXI4-Stream slave: nguon audio 16-bit Q1.15 ----
    input  wire                          s_axis_tvalid,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    output wire                          s_axis_tready,

    // ---- Luong pho don bien (magnitude) theo THU TU TU NHIEN, N/2 bin ----
    output wire                          spec_valid,
    output wire [DATA_WIDTH-1:0]         spec_magnitude,   // UNSIGNED
    output wire [$clog2(N)-1:0]          spec_bin_idx,     // 0..N/2-1 (bin tan so tu nhien)
    output wire                          spec_sof,
    output wire                          spec_last,

    // ---- Dinh pho moi frame (bin tan so lon nhat) ----
    output wire                          peak_valid,
    output wire [DATA_WIDTH-1:0]         peak_magnitude,
    output wire [$clog2(N/2)-1:0]        peak_bin_idx      // bin TU NHIEN: f = bin*fs/N
);
    localparam integer HALF = N >> 1;   // 128

    // ---------------- 1) INPUT BUFFER (AXI-S -> frame stream) ----------------
    wire                        ib_valid, ib_sof, ib_last;
    wire signed [DATA_WIDTH-1:0] ib_data;
    // FFT luon san sang nhan (loi valid-gated): out_ready = 1
    input_buffer_fsm #(.N(N), .DATA_WIDTH(DATA_WIDTH)) u_ibuf (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tdata(s_axis_tdata), .s_axis_tready(s_axis_tready),
        .out_valid(ib_valid), .out_data(ib_data), .out_sof(ib_sof), .out_last(ib_last),
        .out_ready(1'b1)
    );

    // ---------------- 2) WINDOW (Hann) ----------------
    wire                        win_valid, win_sof, win_last;
    wire signed [DATA_WIDTH-1:0] win_data;
    window_unit #(.N(N), .DATA_WIDTH(DATA_WIDTH), .COEFF_FILE(WINDOW_FILE)) u_win (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ib_valid), .in_data(ib_data), .in_sof(ib_sof), .in_last(ib_last),
        .out_valid(win_valid), .out_data(win_data), .out_sof(win_sof), .out_last(win_last)
    );

    // ---------------- 3) FFT 256 diem (R2SDF) ----------------
    wire                        fft_valid, fft_sof, fft_last;
    wire signed [DATA_WIDTH-1:0] fft_re, fft_im;
    fft_r22sdf_top #(
        .N(N), .DATA_WIDTH(DATA_WIDTH),
        .RE_FILE(TW_RE_FILE), .IM_FILE(TW_IM_FILE), .LATENCY(FFT_LATENCY)
    ) u_fft (
        .clk(clk), .rst_n(rst_n),
        .in_valid(win_valid), .in_re(win_data), .in_im({DATA_WIDTH{1'b0}}),
        .in_sof(win_sof), .in_last(win_last),
        .out_valid(fft_valid), .out_re(fft_re), .out_im(fft_im),
        .out_sof(fft_sof), .out_last(fft_last)
    );

    // ---------------- 4) MAGNITUDE (|X[k]|, van bit-reversed) ----------------
    // NUM_BINS = N: xu ly toan bo 256 bin bit-reversed truoc khi sap xep.
    wire                        mag_valid, mag_sof, mag_last;
    wire [DATA_WIDTH-1:0]       mag_value;
    wire [$clog2(N)-1:0]        mag_bin_idx;
    wire signed [15:0]          mag_log2;
    magnitude_unit #(.NUM_BINS(N), .DATA_WIDTH(DATA_WIDTH), .ENABLE_LOG(ENABLE_LOG)) u_mag (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fft_valid), .in_re(fft_re), .in_im(fft_im),
        .in_sof(fft_sof), .in_last(fft_last),
        .out_valid(mag_valid), .out_magnitude(mag_value), .out_bin_idx(mag_bin_idx),
        .out_sof(mag_sof), .out_last(mag_last), .out_mag_log2(mag_log2)
    );

    // ---------------- 5) BIN RAM (bit-reversed -> tu nhien, N/2 don bien) ----
    wire                        br_valid, br_sof, br_last;
    wire [DATA_WIDTH-1:0]       br_value;
    wire [$clog2(N)-1:0]        br_bin_idx;
    bin_ram_output #(.N(N), .DATA_WIDTH(DATA_WIDTH)) u_bram (
        .clk(clk), .rst_n(rst_n),
        .in_valid(mag_valid), .in_magnitude(mag_value), .in_sof(mag_sof), .in_last(mag_last),
        .out_valid(br_valid), .out_magnitude(br_value), .out_bin_idx(br_bin_idx),
        .out_sof(br_sof), .out_last(br_last)
    );

    assign spec_valid     = br_valid;
    assign spec_magnitude = br_value;
    assign spec_bin_idx   = br_bin_idx;
    assign spec_sof       = br_sof;
    assign spec_last      = br_last;

    // ---------------- 6) PEAK DETECTOR (tren pho TU NHIEN don bien) ----------
    // peak_bin_idx la bin tan so that (0..N/2-1): f = peak_bin_idx * fs / N.
    peak_detector #(.NUM_BINS(HALF), .DATA_WIDTH(DATA_WIDTH)) u_peak (
        .clk(clk), .rst_n(rst_n),
        .in_valid(br_valid), .in_magnitude(br_value),
        .in_bin_idx(br_bin_idx[$clog2(HALF)-1:0]),
        .in_sof(br_sof), .in_last(br_last),
        .peak_valid(peak_valid), .peak_magnitude(peak_magnitude), .peak_bin_idx(peak_bin_idx)
    );

endmodule
