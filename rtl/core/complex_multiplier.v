`timescale 1ns / 1ps

module complex_multiplier #(
    parameter integer DW = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  en,      // clock-enable (=valid)
    input  wire signed [DW-1:0]  ar,
    input  wire signed [DW-1:0]  ai,
    input  wire signed [DW-1:0]  br,
    input  wire signed [DW-1:0]  bi,
    output reg  signed [DW-1:0]  pr,
    output reg  signed [DW-1:0]  pi
);
    localparam integer SHIFT = DW - 1;    // 15

    // Tang 1: cac tong (17-bit) + tre toan hang can dung o tang 2 
    reg signed [DW:0]   s1, s2, s3;       // ar+ai, bi-br, br+bi
    reg signed [DW-1:0] br1, ar1, ai1;
    always @(posedge clk) begin
        if (!rst_n) begin
            s1<=0; s2<=0; s3<=0; br1<=0; ar1<=0; ai1<=0;
        end else if (en) begin
            s1  <= $signed({ar[DW-1],ar}) + $signed({ai[DW-1],ai});
            s2  <= $signed({bi[DW-1],bi}) - $signed({br[DW-1],br});
            s3  <= $signed({br[DW-1],br}) + $signed({bi[DW-1],bi});
            br1 <= br; ar1 <= ar; ai1 <= ai;
        end
    end

    // Tang 2: 3 phep nhan (33-bit)
    reg signed [2*DW:0] k1, k2, k3;  
    always @(posedge clk) begin
        if (!rst_n) begin k1<=0; k2<=0; k3<=0; end
        else if (en) begin
            k1 <= br1 * s1;
            k2 <= ar1 * s2;
            k3 <= ai1 * s3;
        end
    end

    // Tang 3: cong/tru (34-bit) + round-half-even + saturate ----
    wire signed [2*DW+1:0] pr_full = $signed({k1[2*DW],k1}) - $signed({k3[2*DW],k3});
    wire signed [2*DW+1:0] pi_full = $signed({k1[2*DW],k1}) + $signed({k2[2*DW],k2});

    localparam signed [DW:0] SAT_MAX =  (1 <<< (DW-1)) - 1;
    localparam signed [DW:0] SAT_MIN = -(1 <<< (DW-1));

    function automatic signed [DW-1:0] round_sat_shift;
        input signed [2*DW+1:0] full;
        reg   signed [2*DW+1:0] shifted;
        reg          [SHIFT-2:0] lower_bits;
        begin
            lower_bits = full[SHIFT-2:0];
            if (full[SHIFT-1] == 1'b0)      shifted = full >>> SHIFT;
            else if (lower_bits != 0)       shifted = (full >>> SHIFT) + 1;  // signed 1
            else if (full[SHIFT] == 1'b0)   shifted = full >>> SHIFT;
            else                            shifted = (full >>> SHIFT) + 1;
            if (shifted > SAT_MAX)          round_sat_shift = SAT_MAX[DW-1:0];
            else if (shifted < SAT_MIN)     round_sat_shift = SAT_MIN[DW-1:0];
            else                            round_sat_shift = shifted[DW-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin pr<=0; pi<=0; end
        else if (en) begin
            pr <= round_sat_shift(pr_full);
            pi <= round_sat_shift(pi_full);
        end
    end
endmodule
