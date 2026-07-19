// =============================================================================
// tb_magnitude_unit.v
// -----------------------------------------------------------------------------
// Kiem chung magnitude_unit.v: dua 2013 cap (re,im) (13 diem bien + 2000 ngau
// nhien Q1.15) qua DUT, doi chieu out_magnitude (alpha-max-beta-min) VA
// out_mag_log2 (log2 xap xi) voi mo hinh Python dich tung buoc tu chinh RTL
// (gen_magnitude_vectors.py). Kiem BIT-EXACT ca 2 gia tri (khong chi
// magnitude) vi thuat toan log2 xap xi la TAT DINH.
//
// Chay (Vivado): giong het quy trinh da lam voi tb_fft_r22sdf.v -- Add
// Sources file nay + magnitude_unit.v vao sim_1, dat cac file .mem cung thu
// muc lam viec, Set as Top, Run Simulation, go 'run -all'.
// Chay (Icarus):
//   iverilog -g2012 -o sim_mag tb_magnitude_unit.v magnitude_unit.v
//   vvp sim_mag
// =============================================================================
`timescale 1ns / 1ps

module tb_magnitude_unit;
    localparam integer DW       = 16;
    localparam integer NUM_BINS = 128;
    localparam integer TOTAL    = 2013;   // phai khop so dong trong cac file .mem

    reg clk = 0, rst_n = 0, in_valid = 0, in_sof = 0, in_last = 0;
    reg signed [DW-1:0] in_re = 0, in_im = 0;

    wire out_valid, out_sof, out_last;
    wire [DW-1:0] out_magnitude;
    wire [$clog2(NUM_BINS)-1:0] out_bin_idx;
    wire signed [15:0] out_mag_log2;

    magnitude_unit #(.NUM_BINS(NUM_BINS), .DATA_WIDTH(DW), .ENABLE_LOG(1)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_re(in_re), .in_im(in_im),
        .in_sof(in_sof), .in_last(in_last),
        .out_valid(out_valid), .out_magnitude(out_magnitude), .out_bin_idx(out_bin_idx),
        .out_sof(out_sof), .out_last(out_last), .out_mag_log2(out_mag_log2)
    );

    always #5 clk = ~clk;

    reg signed [DW-1:0] vin_re    [0:TOTAL-1];
    reg signed [DW-1:0] vin_im    [0:TOTAL-1];
    reg        [DW-1:0] vexp_mag  [0:TOTAL-1];
    reg signed [DW-1:0] vexp_log2 [0:TOTAL-1];

    integer t;
    integer mism_mag, mism_log2;

    initial begin
        $readmemh("mag_in_re.mem",    vin_re);
        $readmemh("mag_in_im.mem",    vin_im);
        $readmemh("mag_exp_mag.mem",  vexp_mag);
        $readmemh("mag_exp_log2.mem", vexp_log2);

        mism_mag = 0; mism_log2 = 0;

        rst_n = 0; in_valid = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (t = 0; t < TOTAL; t = t + 1) begin
            in_re    <= vin_re[t];
            in_im    <= vin_im[t];
            in_sof   <= (t % NUM_BINS == 0) ? 1'b1 : 1'b0;
            in_last  <= (t % NUM_BINS == NUM_BINS-1) ? 1'b1 : 1'b0;
            in_valid <= 1'b1;
            @(posedge clk);
            #1;

            if (out_magnitude !== vexp_mag[t]) begin
                mism_mag = mism_mag + 1;
                if (mism_mag <= 8)
                    $display("[TB] MISMATCH magnitude @vec %0d (re=%0d im=%0d): rtl=%0d exp=%0d",
                              t, vin_re[t], vin_im[t], out_magnitude, vexp_mag[t]);
            end
            if (out_mag_log2 !== vexp_log2[t]) begin
                mism_log2 = mism_log2 + 1;
                if (mism_log2 <= 8)
                    $display("[TB] MISMATCH log2 @vec %0d (re=%0d im=%0d): rtl=%0d exp=%0d",
                              t, vin_re[t], vin_im[t], out_mag_log2, vexp_log2[t]);
            end
        end

        $display("[TB] Da kiem %0d cap (re,im)", TOTAL);
        $display("[TB] Sai lech: magnitude=%0d  log2=%0d", mism_mag, mism_log2);

        if (mism_mag == 0 && mism_log2 == 0)
            $display("[TB] ====== PASS (magnitude_unit bit-exact ca alpha-max-beta-min lan log2 xap xi) ======");
        else
            $display("[TB] ====== FAIL ======");

        $finish;
    end
endmodule
