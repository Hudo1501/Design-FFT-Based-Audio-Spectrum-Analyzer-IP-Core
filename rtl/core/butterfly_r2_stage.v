// =============================================================================
// Module : butterfly_r2_stage   (radix-2 DIF SDF "delay commutator")
// -----------------------------------------------------------------------------
// 1 tang butterfly SDF co DELAY LINE ben trong (DELAY_LEN = N/2^(J+1)). Dung
// chung cho 8 tang. Xuat them sel_o/cnt_o de stage_with_twiddle.v dia chi hoa
// twiddle.
//
// PHA (theo vi tri mau trong frame p = cnt_cur, reset boi in_sof):
//   sel = p[LOG2N-1-J]:
//     sel=0 (LOAD/passthrough): out = delay_out (chinh la 'diff' tre tu khoi
//                               truoc, se duoc NHAN twiddle o tren); day input
//                               vao delay line.
//     sel=1 (COMPUTE/butterfly): out = (delay_out + in)   [scaled ÷2 neu
//                               SCALE_EN]; day (delay_out - in) [÷2] vao delay.
//   cnt_o = vi tri trong nua khoi (p mod DELAY_LEN) -> lam co so dia chi twiddle.
//
// *** BUG DA SUA (muc 5 tai lieu tien do) ***
// sel_o/cnt_o duoc DANG KY (thanh ghi) de canh DUNG CHU KY voi out_re/out_im.
// out_re/out_im la ket qua tinh tu sel/cnt cua mau HIEN TAI roi qua 1 thanh ghi;
// neu de sel_o/cnt_o = wire noi thang toi thanh ghi cnt/sel (da advance cho mau
// KE TIEP) thi nhan (sel_o) se di truoc du lieu (out) 1 chu ky -> stream doi pha
// sum<->diff cham 1 chu ky, sai le W_N^1. Dang ky sel_o/cnt_o bang chinh gia tri
// sel/cnt dung de tinh out => nhan & du lieu ra CUNG chu ky. (Logic cnt/sel noi
// bo GIU NGUYEN — da kiem chung FFT-4.)
//
// Latency tang nay = 1 chu ky. Da kiem chung mo phong cycle-accurate: 8 tang +
// twiddle -> SQNR ~60 dB, output bit-reversed.
// =============================================================================
`timescale 1ns / 1ps

module butterfly_r2_stage #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter integer J          = 0,          // chi so tang 0..log2(N)-1
    parameter integer SCALE_EN   = 1           // 1: chia 2 + round; 0: saturate
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_re,
    input  wire signed [DATA_WIDTH-1:0]  in_im,
    input  wire                          in_sof,

    output reg                           out_valid,
    output reg  signed [DATA_WIDTH-1:0]  out_re,
    output reg  signed [DATA_WIDTH-1:0]  out_im,
    output reg                           out_sof,
    output reg                           sel_o,     // pha (canh voi out_*): 1=sum,0=diff
    output reg  [$clog2(N)-1:0]          cnt_o      // vi tri trong nua khoi (canh voi out_*)
);
    localparam integer LOG2N     = $clog2(N);          // 8
    localparam integer DELAY_LEN = N >> (J + 1);       // do sau delay line
    localparam integer ADDR_W    = LOG2N;              // 8
    localparam integer SEL_BIT   = (LOG2N - 1) - J;    // 7 - J
    localparam [ADDR_W-1:0] INHALF_MASK = DELAY_LEN - 1;

    // bo dem vi tri trong frame
    reg  [ADDR_W-1:0] cnt;
    wire [ADDR_W-1:0] cnt_cur = in_sof ? {ADDR_W{1'b0}} : (cnt + 1'b1);
    wire              sel      = cnt_cur[SEL_BIT];
    wire [ADDR_W-1:0] inhalf   = cnt_cur & INHALF_MASK;

    // delay line
    reg signed [DATA_WIDTH-1:0] dl_re [0:DELAY_LEN-1];
    reg signed [DATA_WIDTH-1:0] dl_im [0:DELAY_LEN-1];
    wire signed [DATA_WIDTH-1:0] d_re = dl_re[0];
    wire signed [DATA_WIDTH-1:0] d_im = dl_im[0];

    // butterfly (cong/tru mo rong 1 bit) + scaling ÷2 (round-half-even) hoac sat
    wire signed [DATA_WIDTH:0] s_re = $signed({d_re[DATA_WIDTH-1],d_re}) + $signed({in_re[DATA_WIDTH-1],in_re});
    wire signed [DATA_WIDTH:0] s_im = $signed({d_im[DATA_WIDTH-1],d_im}) + $signed({in_im[DATA_WIDTH-1],in_im});
    wire signed [DATA_WIDTH:0] f_re = $signed({d_re[DATA_WIDTH-1],d_re}) - $signed({in_re[DATA_WIDTH-1],in_re});
    wire signed [DATA_WIDTH:0] f_im = $signed({d_im[DATA_WIDTH-1],d_im}) - $signed({in_im[DATA_WIDTH-1],in_im});

    function automatic signed [DATA_WIDTH-1:0] scale_or_sat;
        input signed [DATA_WIDTH:0] full;    // DW+1 bit
        reg   signed [DATA_WIDTH:0] q;
        begin
            if (SCALE_EN) begin              // chia 2, round-half-to-even
                if (full[0] == 1'b0)         q = full >>> 1;
                else if (full[1] == 1'b0)    q = full >>> 1;
                else                         q = (full >>> 1) + 1;   // signed 1
                scale_or_sat = q[DATA_WIDTH-1:0];
            end else begin                   // saturate ve DW bit
                if (full > $signed({1'b0,{(DATA_WIDTH-1){1'b1}}}))
                    scale_or_sat = {1'b0,{(DATA_WIDTH-1){1'b1}}};
                else if (full < $signed({1'b1,{(DATA_WIDTH-1){1'b0}}}))
                    scale_or_sat = {1'b1,{(DATA_WIDTH-1){1'b0}}};
                else
                    scale_or_sat = full[DATA_WIDTH-1:0];
            end
        end
    endfunction

    wire signed [DATA_WIDTH-1:0] sum_re  = scale_or_sat(s_re);
    wire signed [DATA_WIDTH-1:0] sum_im  = scale_or_sat(s_im);
    wire signed [DATA_WIDTH-1:0] diff_re = scale_or_sat(f_re);
    wire signed [DATA_WIDTH-1:0] diff_im = scale_or_sat(f_im);

    // dau ra & 'to_delay' theo pha
    wire signed [DATA_WIDTH-1:0] o_re_n = sel ? sum_re  : d_re;
    wire signed [DATA_WIDTH-1:0] o_im_n = sel ? sum_im  : d_im;
    wire signed [DATA_WIDTH-1:0] to_re  = sel ? diff_re : in_re;
    wire signed [DATA_WIDTH-1:0] to_im  = sel ? diff_im : in_im;

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            cnt<={ADDR_W{1'b0}}; out_valid<=1'b0; out_re<=0; out_im<=0;
            out_sof<=1'b0; sel_o<=1'b0; cnt_o<={ADDR_W{1'b0}};
            for (i=0;i<DELAY_LEN;i=i+1) begin dl_re[i]<=0; dl_im[i]<=0; end
        end else begin
            out_valid <= in_valid;
            out_sof   <= in_valid && in_sof;
            if (in_valid) begin
                cnt    <= cnt_cur;
                out_re <= o_re_n;
                out_im <= o_im_n;
                sel_o  <= sel;       // *** dang ky -> canh voi out_* (bug fix) ***
                cnt_o  <= inhalf;    // ***
                for (i=0;i<DELAY_LEN-1;i=i+1) begin
                    dl_re[i]<=dl_re[i+1]; dl_im[i]<=dl_im[i+1];
                end
                dl_re[DELAY_LEN-1]<=to_re; dl_im[DELAY_LEN-1]<=to_im;
            end
        end
    end
endmodule
