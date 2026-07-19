// =============================================================================
// Module : nexys_a7_top   (WRAPPER BOARD — Nexys A7-100T / A7-50T)
// -----------------------------------------------------------------------------
// Noi toan bo IP len board that:
//
//   SW0=0 : nguon = TONE NOI BO (tv_input.mem, dinh o bin 10) -> SELF-TEST
//   SW0=1 : nguon = MIC PDM tren board (qua pdm_pcm_frontend)
//
//        nguon -> fft_analyzer_ip (AXI-S) -> peak_bin_idx / peak_magnitude
//
//   7-SEGMENT : hien thi  [peak_magnitude(4 hex)][--][peak_bin(2 hex)]
//               digit 1-0 = peak_bin_idx (hex, 0..7F)
//               digit 7-4 = peak_magnitude (hex)
//   LED[15]   : busy
//   LED[14]   : peak_valid (nhap nhay moi frame)
//   LED[6:0]  : peak_bin_idx (nhi phan) -- KIEM NHANH: tone noi bo => 0001010 (=10)
//
// *** KIEM TRA DAU TIEN KHI NAP BOARD: dat SW0=0 (tone noi bo).
//     7-seg 2 digit phai hien "0A" (=10) va LED[3],LED[1] sang (10 = 0001010).
//     Neu dung => TOAN BO chuoi FFT chay dung tren silicon that.
//     Sau do moi bat SW0=1 de thu mic. ***
//
// LUU Y: fs cua nhanh mic ~= 48.83kHz (bo chia so nguyen), khong dung 48.000kHz
// => nhan tan so f = bin * fs/N lech ~1.7%. Dung MMCM neu can chinh xac.
// =============================================================================
`timescale 1ns / 1ps

module nexys_a7_top #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter integer FFT_LATENCY= 291
)(
    input  wire        clk,          // 100 MHz onboard
    input  wire        cpu_resetn,   // nut CPU RESET (tich cuc THAP)
    input  wire [1:0]  sw,           // SW0: chon nguon ; SW1: (du phong)
    // mic PDM tren board
    output wire        m_clk,
    input  wire        m_data,
    output wire        m_lrsel,
    // hien thi
    output wire [6:0]  seg,
    output wire        dp,
    output wire [7:0]  an,
    output wire [15:0] led
);
    // ---------------- reset + dong bo hoa switch ----------------
    wire rst_n = cpu_resetn;          // nut da la tich cuc thap
    wire sw0_s;
    sync_2ff u_sync_sw0 (.clk(clk), .rst_n(rst_n), .async_in(sw[0]), .sync_out(sw0_s));

    // ---------------- nguon 1: TONE NOI BO (self-test) ----------------
    wire                        tone_valid;
    wire signed [DATA_WIDTH-1:0] tone_data;
    tone_player #(.N(N), .DATA_WIDTH(DATA_WIDTH), .CLK_PER_SAMPLE(2083),
                  .TONE_FILE("tv_input.mem")) u_tone (
        .clk(clk), .rst_n(rst_n), .en(~sw0_s),
        .out_valid(tone_valid), .out_data(tone_data)
    );

    // ---------------- nguon 2: MIC PDM ----------------
    assign m_lrsel = 1'b0;            // chon kenh trai (mic don)
    wire                        mic_valid;
    wire signed [DATA_WIDTH-1:0] mic_data;
    pdm_pcm_frontend #(.DATA_WIDTH(DATA_WIDTH), .PDM_DIV_HALF(16)) u_pdm (
        .clk(clk), .rst_n(rst_n),
        .pdm_sclk(m_clk), .pdm_data(m_data),
        .pcm_valid(mic_valid), .pcm_data(mic_data)
    );

    // ---------------- MUX nguon ----------------
    wire                        src_valid = sw0_s ? mic_valid : tone_valid;
    wire signed [DATA_WIDTH-1:0] src_data  = sw0_s ? mic_data  : tone_data;

    // ---------------- IP phan tich pho ----------------
    wire                    s_tready;
    wire                    m_tvalid, m_tlast;
    wire [DATA_WIDTH-1:0]   m_tdata;
    wire [0:0]              m_tuser;
    wire                    pk_valid, busy_w, coren_w;
    wire [DATA_WIDTH-1:0]   pk_mag;
    wire [$clog2(N/2)-1:0]  pk_bin;
    wire [31:0]             fcount;

    fft_analyzer_ip #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .FFT_LATENCY(FFT_LATENCY)
    ) u_ip (
        .clk(clk), .rst_n(rst_n), .start(1'b1),
        .s_axis_tvalid(src_valid), .s_axis_tdata(src_data), .s_axis_tready(s_tready),
        .m_axis_tvalid(m_tvalid), .m_axis_tdata(m_tdata), .m_axis_tlast(m_tlast),
        .m_axis_tuser(m_tuser), .m_axis_tready(1'b1),        // luon san sang
        .peak_valid(pk_valid), .peak_magnitude(pk_mag), .peak_bin_idx(pk_bin),
        .busy(busy_w), .core_en(coren_w), .frame_count(fcount)
    );

    // ---------------- bam giu peak de hien thi ----------------
    reg [DATA_WIDTH-1:0]  pk_mag_hold;
    reg [7:0]             pk_bin_hold;
    reg                   pk_blink;
    always @(posedge clk) begin
        if (!rst_n) begin
            pk_mag_hold <= 0; pk_bin_hold <= 0; pk_blink <= 1'b0;
        end else if (pk_valid) begin
            pk_mag_hold <= pk_mag;
            pk_bin_hold <= {{(8-$clog2(N/2)){1'b0}}, pk_bin};
            pk_blink    <= ~pk_blink;
        end
    end

    // ---------------- 7-segment ----------------
    // digit[7:4] = magnitude(hex) ; digit[3:2] = tat ; digit[1:0] = bin(hex)
    wire [31:0] disp_val = {pk_mag_hold, 8'h00, pk_bin_hold};
    seven_seg_driver #(.CLK_HZ(100_000_000)) u_7seg (
        .clk(clk), .rst_n(rst_n),
        .value(disp_val), .digit_en(8'b1111_0011),   // tat 2 digit giua
        .seg(seg), .dp(dp), .an(an)
    );

    // ---------------- LED ----------------
    assign led[6:0]   = pk_bin_hold[6:0];   // bin dinh (nhi phan) -- tone noi bo => 0001010
    assign led[13:7]  = 7'b0;
    assign led[14]    = pk_blink;           // nhap nhay moi frame
    assign led[15]    = busy_w;
endmodule
