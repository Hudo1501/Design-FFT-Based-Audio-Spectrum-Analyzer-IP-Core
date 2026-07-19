// =============================================================================
// tb_twiddle_rom.v
// -----------------------------------------------------------------------------
// Quet toan bo N/2 dia chi cua twiddle_rom.v, doi chieu tw_re/tw_im doc duoc
// voi file tw_exp_re.mem/tw_exp_im.mem SINH DOC LAP tu twiddle_q15() (khong
// phai chinh twiddle_re.mem/twiddle_im.mem ma ROM dang doc - de tranh kiem
// tra vong quanh khong y nghia). Kem 2 diem neo toan hoc chuan: W^0 va
// W^(N/4).
//
// Chay (Vivado): Add Sources file nay + twiddle_rom.v vao sim_1, dat 4 file
// .mem (twiddle_re/im.mem VA tw_exp_re/im.mem) cung thu muc lam viec sim,
// Set as Top, Run Simulation, go 'run -all'.
// Chay (Icarus):
//   iverilog -g2012 -o sim_tw tb_twiddle_rom.v twiddle_rom.v
//   vvp sim_tw
// =============================================================================
`timescale 1ns / 1ps

module tb_twiddle_rom;
    localparam integer N  = 256;
    localparam integer DW = 16;
    localparam integer AW = $clog2(N/2);

    reg clk = 0, en = 0;
    reg [AW-1:0] addr = 0;
    wire signed [DW-1:0] tw_re, tw_im;

    twiddle_rom #(.N(N), .DATA_WIDTH(DW),
                  .RE_FILE("twiddle_re.mem"), .IM_FILE("twiddle_im.mem")) dut (
        .clk(clk), .en(en), .addr(addr), .tw_re(tw_re), .tw_im(tw_im)
    );

    always #5 clk = ~clk;

    reg signed [DW-1:0] exp_re [0:N/2-1];
    reg signed [DW-1:0] exp_im [0:N/2-1];

    integer a;
    integer mism_re, mism_im;

    initial begin
        $readmemh("tw_exp_re.mem", exp_re);
        $readmemh("tw_exp_im.mem", exp_im);

        mism_re = 0; mism_im = 0;
        en = 0;
        repeat (3) @(posedge clk);

        for (a = 0; a < N/2; a = a + 1) begin
            addr <= a[AW-1:0];
            en   <= 1'b1;
            @(posedge clk);
            #1;
            if (tw_re !== exp_re[a]) begin
                mism_re = mism_re + 1;
                if (mism_re <= 5)
                    $display("[TB] MISMATCH tw_re @addr %0d: rtl=%0d exp=%0d", a, tw_re, exp_re[a]);
            end
            if (tw_im !== exp_im[a]) begin
                mism_im = mism_im + 1;
                if (mism_im <= 5)
                    $display("[TB] MISMATCH tw_im @addr %0d: rtl=%0d exp=%0d", a, tw_im, exp_im[a]);
            end
        end

        $display("[TB] Da quet %0d dia chi twiddle_rom", N/2);
        $display("[TB] Sai lech: tw_re=%0d  tw_im=%0d", mism_re, mism_im);

        // ---- diem neo toan hoc ----
        addr <= {AW{1'b0}}; en <= 1'b1; @(posedge clk); #1;
        if (tw_re === 16'h7fff && tw_im === 16'h0000)
            $display("[TB] Diem neo W^0 = 7fff/0000 -- OK");
        else
            $display("[TB] Diem neo W^0 SAI: tw_re=%h tw_im=%h (ky vong 7fff/0000)", tw_re, tw_im);

        addr <= (N/4); en <= 1'b1; @(posedge clk); #1;
        if (tw_re === 16'h0000 && tw_im === 16'h8000)
            $display("[TB] Diem neo W^(N/4) = 0000/8000 -- OK");
        else
            $display("[TB] Diem neo W^(N/4) SAI: tw_re=%h tw_im=%h (ky vong 0000/8000)", tw_re, tw_im);

        if (mism_re == 0 && mism_im == 0)
            $display("[TB] ====== PASS (twiddle_rom bit-exact voi twiddle_q15() doc lap) ======");
        else
            $display("[TB] ====== FAIL ======");

        $finish;
    end
endmodule
