// =============================================================================
// Module : stage_with_twiddle   (1 tang FFT hoan chinh)
// -----------------------------------------------------------------------------
// Ghep: butterfly_r2_stage + twiddle_rom (dong bo,1cyc) + complex_multiplier
// (3cyc) + duong BYPASS delay-matched 4 chu ky cho nhanh 'sum'. MUX chon
// nhan/bypass theo sel_o DA TRE 4 chu ky (canh dung voi ket qua nhan).
//
// So do tre (tinh tu dau ra butterfly, cycle T):
//   nhanh NHAN : out -> [tre 1 canh ROM] -> complex_multiplier(3) => T+4
//                twiddle_rom.addr = cnt_o<<J (ROM dong bo, tw san sang T+1)
//   nhanh BYPASS: out -> [4 thanh ghi]                          => T+4
//   MUX @ T+4  : sel_d4 ? bypass(sum) : mul(diff)   (sel_o tre 4)
//   sof/valid   : theo nhanh bypass (tre 4) => canh voi du lieu ra
//
// HAS_TWIDDLE=0 (tang cuoi, twiddle luon = 1): bo toan bo nhanh nhan, dau ra =
// butterfly truc tiep (tang chi 1 chu ky) -- dung R2SDF (7 bo nhan, tru tang cuoi).
// =============================================================================
`timescale 1ns / 1ps

module stage_with_twiddle #(
    parameter integer N           = 256,
    parameter integer DATA_WIDTH  = 16,
    parameter integer J           = 0,
    parameter integer SCALE_EN    = 1,
    parameter integer HAS_TWIDDLE = 1,
    parameter         RE_FILE     = "twiddle_re.mem",
    parameter         IM_FILE     = "twiddle_im.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_re,
    input  wire signed [DATA_WIDTH-1:0]  in_im,
    input  wire                          in_sof,

    output wire                          out_valid,
    output wire signed [DATA_WIDTH-1:0]  out_re,
    output wire signed [DATA_WIDTH-1:0]  out_im,
    output wire                          out_sof
);
    localparam integer LOG2N  = $clog2(N);
    localparam integer ADDR_W = LOG2N;
    localparam integer TW_AW  = $clog2(N/2);   // 7

    // ---------------- butterfly (delay-commutator) ----------------
    wire                        bf_valid, bf_sof, bf_sel;
    wire signed [DATA_WIDTH-1:0] bf_re, bf_im;
    wire [ADDR_W-1:0]           bf_cnt;

    butterfly_r2_stage #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .J(J), .SCALE_EN(SCALE_EN)
    ) u_bf (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_re(in_re), .in_im(in_im), .in_sof(in_sof),
        .out_valid(bf_valid), .out_re(bf_re), .out_im(bf_im), .out_sof(bf_sof),
        .sel_o(bf_sel), .cnt_o(bf_cnt)
    );

    generate
    if (HAS_TWIDDLE == 0) begin : g_notw
        // tang cuoi: dua thang butterfly ra
        assign out_valid = bf_valid;
        assign out_re    = bf_re;
        assign out_im    = bf_im;
        assign out_sof   = bf_sof;
    end else begin : g_tw
        // *** GATE toan bo nhanh twiddle bang bf_valid (=en) => chiu duoc GAP
        //     (bubble valid=0 tu input_buffer_fsm giua cac frame). Moi thanh ghi
        //     chi dich khi co MAU THAT; latency = 4 MAU-VALID (khong phai 4 clk).
        //     Da kiem chung mo phong co gap: SQNR ~60 dB, latency 283 mau-valid. ***
        wire en = bf_valid;

        // ---- nhanh NHAN ----
        wire [TW_AW-1:0] tw_addr = (bf_cnt << J);      // (cnt_o * 2^J), < N/2
        wire signed [DATA_WIDTH-1:0] tw_re, tw_im;
        twiddle_rom #(.N(N), .DATA_WIDTH(DATA_WIDTH), .RE_FILE(RE_FILE), .IM_FILE(IM_FILE)) u_rom (
            .clk(clk), .en(en), .addr(tw_addr), .tw_re(tw_re), .tw_im(tw_im)
        );
        // du lieu tre 1 MAU-VALID canh ROM
        reg signed [DATA_WIDTH-1:0] bf_re_d1, bf_im_d1;
        always @(posedge clk) begin
            if (!rst_n)   begin bf_re_d1<=0; bf_im_d1<=0; end
            else if (en)  begin bf_re_d1<=bf_re; bf_im_d1<=bf_im; end
        end
        wire signed [DATA_WIDTH-1:0] mul_re, mul_im;
        complex_multiplier #(.DW(DATA_WIDTH)) u_cmul (
            .clk(clk), .rst_n(rst_n), .en(en),
            .ar(bf_re_d1), .ai(bf_im_d1), .br(tw_re), .bi(tw_im),
            .pr(mul_re),   .pi(mul_im)
        );  // 3 MAU-VALID => mul_re/mul_im tuong ung bf_* tai (T-4 mau-valid)

        // ---- nhanh BYPASS 4 MAU-VALID (data + sel + sof), gated boi en ----
        reg signed [DATA_WIDTH-1:0] byp_re [0:3];
        reg signed [DATA_WIDTH-1:0] byp_im [0:3];
        reg [3:0] byp_sel, byp_sof;
        integer i;
        always @(posedge clk) begin
            if (!rst_n) begin
                for (i=0;i<4;i=i+1) begin byp_re[i]<=0; byp_im[i]<=0; end
                byp_sel<=0; byp_sof<=0;
            end else if (en) begin
                byp_re[0]<=bf_re;  byp_im[0]<=bf_im;
                byp_re[1]<=byp_re[0]; byp_im[1]<=byp_im[0];
                byp_re[2]<=byp_re[1]; byp_im[2]<=byp_im[1];
                byp_re[3]<=byp_re[2]; byp_im[3]<=byp_im[2];
                byp_sel<={byp_sel[2:0], bf_sel};
                byp_sof<={byp_sof[2:0], bf_sof};
            end
        end
        wire sel_d4 = byp_sel[3];
        // MUX: sel_d4=1 (sum/compute) -> bypass ; else (diff/load) -> nhan.
        // out_valid = bf_valid (mau that hien tai); data/sof = 4 mau-valid truoc
        // (canh nhau). Khung cuoi do fft_r22sdf_top tao lai bang tre 283 mau-valid,
        // nen doi lech pha valid noi bo la vo hai.
        assign out_re    = sel_d4 ? byp_re[3] : mul_re;
        assign out_im    = sel_d4 ? byp_im[3] : mul_im;
        assign out_valid = bf_valid;
        assign out_sof   = byp_sof[3];
    end
    endgenerate
endmodule
