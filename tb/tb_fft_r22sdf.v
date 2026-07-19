// =============================================================================
// Testbench : tb_fft_r22sdf   (TU KIEM + TU CANH KHUNG)
// -----------------------------------------------------------------------------
// Nap tv_input.mem (256 mau thuc Q1.15), day lien tuc nhieu frame vao
// fft_r22sdf_top (kien truc day du: butterfly delay-commutator + twiddle 3cyc
// Karatsuba + bypass 4cyc), thu output bit-reversed, TU CANH KHUNG (do offset
// tot nhat quanh out_sof, chiu duoc +-6 chu ky), bit-reverse ve tu nhien, doi
// chieu tv_exp_real/imag.mem + SQNR, kiem tra bin dinh. In PASS/FAIL + LATENCY
// thuc do (de chinh tham so). Ky vong: RTL == golden BIT-EXACT (SQNR rat cao).
//
// iverilog -g2012 -o sim tb_fft_r22sdf.v fft_r22sdf_top.v stage_with_twiddle.v \
//   butterfly_r2_stage.v complex_multiplier.v twiddle_rom.v   (dat *.mem cung cho)
// vvp sim
// =============================================================================
`timescale 1ns / 1ps

module tb_fft_r22sdf;
    localparam integer N=256, DW=16, LOG2N=8, FRAMES=6, CAPMAX=FRAMES*N+800;

    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg signed [DW-1:0] xin [0:N-1];
    reg signed [DW-1:0] exp_re [0:N-1];
    reg signed [DW-1:0] exp_im [0:N-1];
    reg        [DW-1:0] exp_mag[0:N/2-1];
    integer PEAK_BIN;

    reg in_valid=0, in_sof=0, in_last=0;
    reg signed [DW-1:0] in_re=0, in_im=0;
    wire o_valid, o_sof, o_last;
    wire signed [DW-1:0] o_re, o_im;

    fft_r22sdf_top #(.N(N), .DATA_WIDTH(DW),
                     .RE_FILE("twiddle_re.mem"), .IM_FILE("twiddle_im.mem"),
                     .LATENCY(291)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_re(in_re), .in_im(in_im), .in_sof(in_sof), .in_last(in_last),
        .out_valid(o_valid), .out_re(o_re), .out_im(o_im), .out_sof(o_sof), .out_last(o_last)
    );

    reg signed [DW-1:0] cap_re [0:CAPMAX-1];
    reg signed [DW-1:0] cap_im [0:CAPMAX-1];
    reg cap_s [0:CAPMAX-1];
    integer capn=0;

    function [LOG2N-1:0] bitrev;
        input [LOG2N-1:0] x; integer b;
        begin for (b=0;b<LOG2N;b=b+1) bitrev[b]=x[LOG2N-1-b]; end
    endfunction

    integer i, f;
    integer sof_pos [0:FRAMES+2];
    integer nsof;

    initial begin
        $readmemh("tv_input.mem",    xin);
        $readmemh("tv_exp_real.mem", exp_re);
        $readmemh("tv_exp_imag.mem", exp_im);
        $readmemh("tv_exp_mag.mem",  exp_mag);
        PEAK_BIN = 10;

        rst_n=0; in_valid=0; in_sof=0; in_last=0; in_re=0; in_im=0;
        repeat (5) @(posedge clk);
        rst_n=1; @(posedge clk);

        for (f=0; f<FRAMES; f=f+1)
            for (i=0; i<N; i=i+1) begin
                in_valid<=1'b1; in_re<=xin[i]; in_im<=16'sd0;
                in_sof<=(i==0); in_last<=(i==N-1);
                @(posedge clk);
            end
        in_valid<=1'b0; in_sof<=0; in_last<=0;
        repeat (500) @(posedge clk);
        analyze;
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && capn<CAPMAX) begin
            cap_re[capn]<=o_re; cap_im[capn]<=o_im; cap_s[capn]<=o_sof; capn=capn+1;
        end
    end

    task analyze;
        integer k, off, best_off, base, natr;
        real sig, noi, e_re, e_im, sqnr, best_sqnr;
        integer pk, pkval, mval;
        reg signed [DW-1:0] fr_re [0:N-1];
        reg signed [DW-1:0] fr_im [0:N-1];
        begin
            nsof=0;
            for (k=0;k<capn;k=k+1)
                if (cap_s[k] && nsof<FRAMES+2) begin sof_pos[nsof]=k; nsof=nsof+1; end
            $display("[TB] so xung out_sof = %0d", nsof);
            if (nsof<3) begin $display("[TB] *** FAIL: thieu out_sof ***"); disable analyze; end

            base = sof_pos[2];
            best_sqnr=-1000.0; best_off=0;
            for (off=-6; off<=6; off=off+1)
                if (base+off>=0 && base+off+N<=capn) begin
                    for (k=0;k<N;k=k+1) begin
                        natr=bitrev(k[LOG2N-1:0]);
                        fr_re[natr]=cap_re[base+off+k]; fr_im[natr]=cap_im[base+off+k];
                    end
                    sig=0.0; noi=0.0;
                    for (k=0;k<N;k=k+1) begin
                        e_re=$itor(fr_re[k])-$itor(exp_re[k]);
                        e_im=$itor(fr_im[k])-$itor(exp_im[k]);
                        sig=sig+$itor(exp_re[k])*$itor(exp_re[k])+$itor(exp_im[k])*$itor(exp_im[k]);
                        noi=noi+e_re*e_re+e_im*e_im;
                    end
                    if (noi<=0.0) noi=1.0e-12;
                    sqnr=10.0*$log10(sig/noi);
                    if (sqnr>best_sqnr) begin best_sqnr=sqnr; best_off=off; end
                end
            $display("[TB] canh khung tot nhat: offset=%0d => LATENCY thuc ~= %0d", best_off, 283+best_off);
            $display("[TB] SQNR (RTL vs golden) = %0.1f dB", best_sqnr);

            for (k=0;k<N;k=k+1) begin
                natr=bitrev(k[LOG2N-1:0]);
                fr_re[natr]=cap_re[base+best_off+k]; fr_im[natr]=cap_im[base+best_off+k];
            end
            pk=0; pkval=-1;
            for (k=0;k<N/2;k=k+1) begin
                mval=amag(fr_re[k],fr_im[k]);
                if (mval>pkval) begin pkval=mval; pk=k; end
            end
            $display("[TB] bin dinh = %0d (ky vong %0d)", pk, PEAK_BIN);
            if (best_sqnr>40.0 && pk==PEAK_BIN) $display("[TB] ====== PASS ======");
            else $display("[TB] ====== FAIL (xem SQNR/peak/LATENCY) ======");
        end
    endtask

    function integer amag;
        input signed [DW-1:0] re, im;
        integer ar,ai,mx,mn,full;
        begin
            ar=(re<0)?-re:re; ai=(im<0)?-im:im;
            mx=(ar>ai)?ar:ai; mn=(ar>ai)?ai:ar;
            full=31471*mx+13036*mn; amag=full>>>15;
        end
    endfunction
endmodule
