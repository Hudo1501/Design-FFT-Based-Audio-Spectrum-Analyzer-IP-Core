// =============================================================================
// Module : pynq_z2_top   (WRAPPER BOARD — PYNQ-Z2, Zynq XC7Z020)
// -----------------------------------------------------------------------------
// KHAC BIET SO VOI NEXYS A7 (quan trong):
//   * PYNQ-Z2 KHONG co mic PDM tren board (no dung codec ADAU1761 qua I2S --
//     can driver I2S + cau hinh I2C, NGOAI pham vi). => wrapper nay dung
//     TONE NOI BO (tv_input.mem) lam nguon => SELF-TEST toan chuoi tren silicon.
//   * PYNQ-Z2 KHONG co 7-segment. Chi co 4 LED + 2 RGB LED + 2 switch + 4 nut.
//     => hien thi peak_bin_idx (7 bit) theo 2 nua, chon bang SW0.
//   * Clock onboard = 125 MHz (KHONG phai 100 MHz).
//
// HIEN THI:
//   SW0=0 : led[3:0] = peak_bin_idx[3:0]  (nua THAP)
//   SW0=1 : led[3:0] = {1'b0, peak_bin_idx[6:4]} (nua CAO)
//   RGB LED: xanh = busy ; nhap nhay do = peak_valid moi frame
//
// *** KIEM TRA KHI NAP BOARD: tone noi bo co dinh o bin 10 = 0b0001010.
//     SW0=0 -> led[3:0] phai la 1010 (LED3=1, LED2=0, LED1=1, LED0=0)
//     SW0=1 -> led[3:0] phai la 0000
//     Neu dung => toan bo chuoi FFT chay dung tren phan cung that. ***
//
// LUU Y CLOCK: thiet ke chay THANG o 125 MHz. Neu timing KHONG dong (WNS<0),
// co 2 lua chon: (a) them Clocking Wizard/MMCM tao 100 MHz tu 125 MHz, hoac
// (b) chen them tang thanh ghi trong butterfly/magnitude. Xem README_BOARD.md.
// (CLK_PER_SAMPLE=2604 = 125MHz/48kHz.)
// =============================================================================
`timescale 1ns / 1ps

module pynq_z2_top #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter integer FFT_LATENCY= 291
)(
    input  wire        clk,        // 125 MHz onboard
    input  wire [1:0]  sw,         // SW0: chon nua hien thi
    input  wire [3:0]  btn,        // btn[0] = reset (tich cuc CAO)
    output wire [3:0]  led,
    output wire [2:0]  led4_rgb,   // RGB LED 4 (R,G,B)
    output wire [2:0]  led5_rgb    // RGB LED 5
);
    // ---------------- reset: btn[0] tich cuc CAO -> rst_n tich cuc thap ----------------
    wire btn0_s, sw0_s;
    wire rst_n_pre = ~btn[0];
    reg  [7:0] rst_cnt = 8'h00;      // giu reset vai chu ky sau power-up
    reg        rst_n_r = 1'b0;
    always @(posedge clk) begin
        if (!rst_n_pre) begin rst_cnt <= 8'h00; rst_n_r <= 1'b0; end
        else if (rst_cnt != 8'hFF) begin rst_cnt <= rst_cnt + 1'b1; rst_n_r <= 1'b0; end
        else rst_n_r <= 1'b1;
    end
    wire rst_n = rst_n_r;

    sync_2ff u_sync_sw0 (.clk(clk), .rst_n(rst_n), .async_in(sw[0]), .sync_out(sw0_s));

    // ---------------- nguon: TONE NOI BO (125MHz/48kHz = 2604) ----------------
    wire                         tone_valid;
    wire signed [DATA_WIDTH-1:0] tone_data;
    tone_player #(.N(N), .DATA_WIDTH(DATA_WIDTH), .CLK_PER_SAMPLE(2604),
                  .TONE_FILE("tv_input.mem")) u_tone (
        .clk(clk), .rst_n(rst_n), .en(1'b1),
        .out_valid(tone_valid), .out_data(tone_data)
    );

    // ---------------- IP phan tich pho ----------------
    wire                    s_tready, m_tvalid, m_tlast;
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
        .s_axis_tvalid(tone_valid), .s_axis_tdata(tone_data), .s_axis_tready(s_tready),
        .m_axis_tvalid(m_tvalid), .m_axis_tdata(m_tdata), .m_axis_tlast(m_tlast),
        .m_axis_tuser(m_tuser), .m_axis_tready(1'b1),
        .peak_valid(pk_valid), .peak_magnitude(pk_mag), .peak_bin_idx(pk_bin),
        .busy(busy_w), .core_en(coren_w), .frame_count(fcount)
    );

    // ---------------- bam giu peak + nhap nhay ----------------
    reg [6:0] pk_bin_hold;
    reg       pk_blink;
    always @(posedge clk) begin
        if (!rst_n) begin pk_bin_hold <= 7'd0; pk_blink <= 1'b0; end
        else if (pk_valid) begin
            pk_bin_hold <= pk_bin;
            pk_blink    <= ~pk_blink;
        end
    end

    // ---------------- hien thi tren 4 LED (chon nua bang SW0) ----------------
    assign led = sw0_s ? {1'b0, pk_bin_hold[6:4]}   // nua CAO
                       : pk_bin_hold[3:0];          // nua THAP (tone -> 1010)

    assign led4_rgb = {1'b0, busy_w, 1'b0};      // xanh la = busy
    assign led5_rgb = {pk_blink, 1'b0, 1'b0};    // do nhap nhay moi frame
endmodule
