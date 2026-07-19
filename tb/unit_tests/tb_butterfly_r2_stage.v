// =============================================================================
// tb_butterfly_r2_stage.v
// -----------------------------------------------------------------------------
// Kiem chung RIENG butterfly_r2_stage.v (cach ly khoi twiddle_rom/complex_
// multiplier o tang sau) doi voi mo hinh Python "thuan butterfly" suy ra tu
// class _Stage trong golden_model_fft.py (gen_butterfly_vectors.py).
//
// Kiem CA gia tri (out_re/out_im) LAN thoi diem (sel_o/cnt_o) - day chinh la
// diem ma bug lich su "sel_o/cnt_o di truoc du lieu 1 chu ky" da xay ra (xem
// comment "BUG DA SUA" trong butterfly_r2_stage.v). Neu bug tai xuat hien duoi
// dang khac, testbench nay se bao FAIL rieng cho cot sel_o/cnt_o, giup khoanh
// vung ngay lap tuc.
//
// Chay (Vivado): Add Sources file nay + butterfly_r2_stage.v vao sim_1, dat
// cac file .mem cung thu muc lam viec sim, Set as Top, Run Simulation, go
// 'run -all' trong Tcl Console.
// Chay (Icarus, kiem nhanh ngoai Vivado):
//   iverilog -g2012 -o sim_bf tb_butterfly_r2_stage.v butterfly_r2_stage.v
//   vvp sim_bf
// =============================================================================
`timescale 1ns / 1ps

module tb_butterfly_r2_stage;
    localparam integer N     = 256;
    localparam integer DW    = 16;
    localparam integer J     = 0;
    localparam integer FRAMES= 4;
    localparam integer TOTAL = N * FRAMES;
    localparam integer AW    = $clog2(N);

    reg clk = 0, rst_n = 0, in_valid = 0, in_sof = 0;
    reg signed [DW-1:0] in_re = 0, in_im = 0;

    wire out_valid, out_sof, sel_o;
    wire signed [DW-1:0] out_re, out_im;
    wire [AW-1:0] cnt_o;

    butterfly_r2_stage #(.N(N), .DATA_WIDTH(DW), .J(J), .SCALE_EN(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_re(in_re), .in_im(in_im), .in_sof(in_sof),
        .out_valid(out_valid), .out_re(out_re), .out_im(out_im), .out_sof(out_sof),
        .sel_o(sel_o), .cnt_o(cnt_o)
    );

    always #5 clk = ~clk;

    reg signed [DW-1:0] vin_re  [0:TOTAL-1];
    reg signed [DW-1:0] vin_im  [0:TOTAL-1];
    reg signed [DW-1:0] vexp_re [0:TOTAL-1];
    reg signed [DW-1:0] vexp_im [0:TOTAL-1];
    reg                 vexp_sel[0:TOTAL-1];
    reg [AW-1:0]        vexp_cnt[0:TOTAL-1];

    integer t;
    integer mism_re, mism_im, mism_sel, mism_cnt;

    initial begin
        $readmemh("bf_in_re.mem",   vin_re);
        $readmemh("bf_in_im.mem",   vin_im);
        $readmemh("bf_exp_re.mem",  vexp_re);
        $readmemh("bf_exp_im.mem",  vexp_im);
        $readmemh("bf_exp_sel.mem", vexp_sel);
        $readmemh("bf_exp_cnt.mem", vexp_cnt);

        mism_re = 0; mism_im = 0; mism_sel = 0; mism_cnt = 0;

        rst_n = 0; in_valid = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (t = 0; t < TOTAL; t = t + 1) begin
            in_re    <= vin_re[t];
            in_im    <= vin_im[t];
            in_sof   <= (t % N == 0) ? 1'b1 : 1'b0;
            in_valid <= 1'b1;
            @(posedge clk);
            #1;

            if (out_re !== vexp_re[t]) begin
                mism_re = mism_re + 1;
                if (mism_re <= 5)
                    $display("[TB] MISMATCH out_re @cycle %0d: rtl=%0d exp=%0d", t, out_re, vexp_re[t]);
            end
            if (out_im !== vexp_im[t]) mism_im = mism_im + 1;

            if (sel_o !== vexp_sel[t]) begin
                mism_sel = mism_sel + 1;
                if (mism_sel <= 5)
                    $display("[TB] MISMATCH sel_o @cycle %0d: rtl=%0d exp=%0d  (dung day de nghi bug sel_o/cnt_o le pha)",
                              t, sel_o, vexp_sel[t]);
            end
            if (cnt_o !== vexp_cnt[t]) mism_cnt = mism_cnt + 1;
        end

        $display("[TB] Da kiem %0d chu ky (N=%0d, J=%0d, DELAY_LEN=%0d, %0d khung)", TOTAL, N, J, N>>(J+1), FRAMES);
        $display("[TB] Sai lech: out_re=%0d  out_im=%0d  sel_o=%0d  cnt_o=%0d", mism_re, mism_im, mism_sel, mism_cnt);

        if (mism_re == 0 && mism_im == 0 && mism_sel == 0 && mism_cnt == 0)
            $display("[TB] ====== PASS (butterfly_r2_stage bit-exact, sel_o/cnt_o dung chu ky) ======");
        else
            $display("[TB] ====== FAIL (xem chi tiet mismatch o tren) ======");

        $finish;
    end
endmodule
