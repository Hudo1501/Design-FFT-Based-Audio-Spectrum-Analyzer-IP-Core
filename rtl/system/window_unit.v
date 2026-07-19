// =============================================================================
// Module : window_unit
// -----------------------------------------------------------------------------
// Nhan tin hieu vao voi he so cua so (x[n] . w[n]) truoc khi dua vao loi FFT,
// nham giam ro pho (spectral leakage). He so w[n] lay tu window_rom.v (doc
// ket hop, cung dia chi voi vi tri mau hien tai trong frame).
//
// Vi tri trong frame (dia chi ROM) duoc tu suy ra tu tin hieu in_sof (bao hieu
// mau dau tien cua frame) do input_buffer_fsm.v cung cap -- module nay KHONG
// can biet truoc N tu ben ngoai ngoai tham so, chi can dem tu 0 moi khi thay
// in_sof va tang dan cho cac mau tiep theo trong cung frame.
//
// Dinh dang so: in_data va coeff deu la Q1.15 16-bit. Tich Q1.15 x Q1.15 cho
// dung 32-bit (2*DATA_WIDTH, KHONG can them bit du phong vi tich cua 2 so
// N-bit luon vua khop 2N bit, khac voi truong hop cong/tru truoc do). Ket qua
// duoc dua ve lai Q1.15 bang dich phai 15 bit kem CONVERGENT ROUNDING
// (round-half-to-even) + SATURATE, cung cach lam voi complex_multiplier.v.
//
// Latency: 1 chu ky dong ho (ROM + nhan la to hop, chi thanh ghi output la
// dong bo). Tin hieu valid/sof/last di kem duoc tre 1 chu ky tuong ung.
// =============================================================================

`timescale 1ns / 1ps

module window_unit #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter         COEFF_FILE = "window_coeff.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_data,
    input  wire                          in_sof,   // mau dau tien cua frame (n=0)
    input  wire                          in_last,  // mau cuoi cung cua frame (n=N-1)

    output reg                           out_valid,
    output reg  signed [DATA_WIDTH-1:0]  out_data,
    output reg                           out_sof,
    output reg                           out_last
);

    localparam integer ADDR_W = $clog2(N);

    // -------------------------------------------------------------------
    // Bo dem vi tri trong frame (dia chi ROM), tu suy ra tu in_sof
    // -------------------------------------------------------------------
    reg [ADDR_W-1:0] prev_pos;

    // vi tri cua mau HIEN TAI dang o cong in_data (to hop, dua tren prev_pos
    // da luu tu chu ky truoc va co in_sof hay khong)
    wire [ADDR_W-1:0] cur_pos = in_sof ? {ADDR_W{1'b0}} : (prev_pos + 1'b1);

    always @(posedge clk) begin
        if (!rst_n) begin
            prev_pos <= {ADDR_W{1'b0}};
        end else if (in_valid) begin
            prev_pos <= cur_pos;
        end
    end

    // -------------------------------------------------------------------
    // Doc he so cua so (to hop) va nhan
    // -------------------------------------------------------------------
    wire signed [DATA_WIDTH-1:0] coeff;

    window_rom #(
        .N          (N),
        .DATA_WIDTH (DATA_WIDTH),
        .COEFF_FILE (COEFF_FILE)
    ) u_window_rom (
        .addr  (cur_pos),
        .coeff (coeff)
    );

    wire signed [2*DATA_WIDTH-1:0] product = $signed(in_data) * $signed(coeff);

    localparam integer SHIFT = DATA_WIDTH - 1;  // 15, dua Q2.30 ve lai Q1.15

    localparam signed [DATA_WIDTH:0] SAT_MAX =  (1 <<< (DATA_WIDTH-1)) - 1;
    localparam signed [DATA_WIDTH:0] SAT_MIN = -(1 <<< (DATA_WIDTH-1));

    // Dich phai SHIFT bit voi CONVERGENT ROUNDING (round-half-to-even) roi
    // bao hoa. LUU Y: dung literal "1" (signed mac dinh), KHONG dung 1'b1 --
    // 1'b1 la hang so UNSIGNED 1-bit, se ep phep cong thanh unsigned va lam
    // sai gia tri am (bug da phat hien va sua trong butterfly_r2_stage.v /
    // complex_multiplier.v qua qua trinh mo phong kiem chung).
    function automatic signed [DATA_WIDTH-1:0] round_sat_shift;
        input signed [2*DATA_WIDTH-1:0] full;
        reg   signed [2*DATA_WIDTH-1:0] shifted;
        reg   [SHIFT-2:0]               lower_bits;
        begin
            lower_bits = full[SHIFT-2:0];

            if (full[SHIFT-1] == 1'b0) begin
                shifted = full >>> SHIFT;
            end else if (lower_bits != 0) begin
                shifted = (full >>> SHIFT) + 1;
            end else begin
                if (full[SHIFT] == 1'b0)
                    shifted = full >>> SHIFT;
                else
                    shifted = (full >>> SHIFT) + 1;
            end

            if (shifted > SAT_MAX)
                round_sat_shift = SAT_MAX[DATA_WIDTH-1:0];
            else if (shifted < SAT_MIN)
                round_sat_shift = SAT_MIN[DATA_WIDTH-1:0];
            else
                round_sat_shift = shifted[DATA_WIDTH-1:0];
        end
    endfunction

    // -------------------------------------------------------------------
    // Thanh ghi output (1 chu ky latency), tre valid/sof/last tuong ung
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= {DATA_WIDTH{1'b0}};
            out_sof   <= 1'b0;
            out_last  <= 1'b0;
        end else begin
            out_valid <= in_valid;
            out_data  <= round_sat_shift(product);
            out_sof   <= in_valid && in_sof;
            out_last  <= in_valid && in_last;
        end
    end

endmodule
