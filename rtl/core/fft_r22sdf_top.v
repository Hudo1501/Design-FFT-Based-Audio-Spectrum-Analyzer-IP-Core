// =============================================================================
// Module : fft_r22sdf_top   (FFT N=256, R2SDF pipelined DIF)
// -----------------------------------------------------------------------------
// Noi tiep log2(N)=8 tang stage_with_twiddle. Tang 0..6 co bo nhan twiddle
// (HAS_TWIDDLE=1); tang cuoi (J=7, twiddle luon =1) HAS_TWIDDLE=0 (khong nhan)
// -> tong 7 bo nhan (dung kien truc R2SDF da chot, muc 5 tai lieu tien do).
// DELAY_LEN tang j = N>>(j+1) = 128,64,...,1. SCALE_EN=1 moi tang (chia 2/tang
// => tong 1/N, chong tran).
//
// Input: luong mau natural-order 1 mau/chu ky (tu window_unit.v).
// Output: X[k] so phuc, THU TU BIT-REVERSED.
//
// FRAMING: bit-reversed[0] xuat hien sau LATENCY chu ky ke tu mau dau frame vao.
// DA DO bang mo phong cycle-accurate (kien truc day du: butterfly 1cyc +
// twiddle/bypass 4cyc moi tang co nhan, tang cuoi 1cyc): **LATENCY = 283** voi
// N=256 (hang so moi frame). out_sof = in_sof tre 283; out_last = bin N-1.
// >>> Testbench tu-canh-khung se in LATENCY thuc do; neu khac 283 (vd doi so
//     tang pipeline cua complex_multiplier), chinh tham so LATENCY cho khop. <<<
//
// Da kiem chung: SQNR ~60 dB so voi numpy.fft; phat hien dinh don/da-tone dung.
// =============================================================================
`timescale 1ns / 1ps

module fft_r22sdf_top #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter         RE_FILE    = "twiddle_re.mem",
    parameter         IM_FILE    = "twiddle_im.mem",
    parameter integer LATENCY    = 291
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_re,
    input  wire signed [DATA_WIDTH-1:0]  in_im,     // thuong = 0
    input  wire                          in_sof,
    input  wire                          in_last,   // (khong bat buoc)

    output wire                          out_valid,
    output wire signed [DATA_WIDTH-1:0]  out_re,
    output wire signed [DATA_WIDTH-1:0]  out_im,
    output wire                          out_sof,   // moc bit-reversed[0]
    output wire                          out_last   // moc bit-reversed[N-1]
);
    localparam integer LOG2N = $clog2(N);

    wire                        st_valid [0:LOG2N-1];
    wire signed [DATA_WIDTH-1:0] st_re   [0:LOG2N-1];
    wire signed [DATA_WIDTH-1:0] st_im   [0:LOG2N-1];
    wire                        st_sof   [0:LOG2N-1];

    genvar j;
    generate
        for (j = 0; j < LOG2N; j = j + 1) begin : g_stage
            stage_with_twiddle #(
                .N(N), .DATA_WIDTH(DATA_WIDTH), .J(j), .SCALE_EN(1),
                .HAS_TWIDDLE((j == LOG2N-1) ? 0 : 1),
                .RE_FILE(RE_FILE), .IM_FILE(IM_FILE)
            ) u_stage (
                .clk(clk), .rst_n(rst_n),
                .in_valid((j==0) ? in_valid : st_valid[j-1]),
                .in_re   ((j==0) ? in_re    : st_re[j-1]),
                .in_im   ((j==0) ? in_im    : st_im[j-1]),
                .in_sof  ((j==0) ? in_sof   : st_sof[j-1]),
                .out_valid(st_valid[j]), .out_re(st_re[j]), .out_im(st_im[j]), .out_sof(st_sof[j])
            );
        end
    endgenerate

    assign out_re = st_re[LOG2N-1];
    assign out_im = st_im[LOG2N-1];

    // framing: tre in_sof/in_valid di LATENCY MAU-VALID (dich chi khi in_valid)
    // => dem theo mau-valid, khop datapath da valid-gated (chiu duoc GAP). Nho
    // vay out_sof/out_valid canh dung voi mau ra that va bo qua 283 mau warmup.
    reg [LATENCY-1:0] sof_dl, val_dl;
    always @(posedge clk) begin
        if (!rst_n) begin sof_dl <= {LATENCY{1'b0}}; val_dl <= {LATENCY{1'b0}}; end
        else if (in_valid) begin
            sof_dl <= {sof_dl[LATENCY-2:0], in_sof};
            val_dl <= {val_dl[LATENCY-2:0], 1'b1};
        end
    end
    wire out_sof_w = in_valid && sof_dl[LATENCY-1];
    wire out_val_w = in_valid && val_dl[LATENCY-1];

    reg  [LOG2N-1:0] prev_bin;
    wire [LOG2N-1:0] cur_bin = out_sof_w ? {LOG2N{1'b0}} : (prev_bin + 1'b1);
    always @(posedge clk) begin
        if (!rst_n)          prev_bin <= {LOG2N{1'b0}};
        else if (out_val_w)  prev_bin <= cur_bin;
    end

    assign out_valid = out_val_w;
    assign out_sof   = out_sof_w;
    assign out_last  = out_val_w && (cur_bin == N-1);
endmodule
