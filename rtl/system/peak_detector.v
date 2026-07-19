// =============================================================================
// Module : peak_detector
// -----------------------------------------------------------------------------
// Mo rong tu y tuong "Magnitude_Comparator" da co: quet toan bo NUM_BINS gia
// tri magnitude cua 1 frame (dua vao boi magnitude_unit.v) va tim ra bin co
// nang luong (magnitude) LON NHAT -- chinh la peak_frequency cua pho, mot
// trong 2 cong phu tuy chon duoc de cap trong spec (bang 1.3, muc Output).
//
// Cach hoat dong: duy tri 1 thanh ghi "running_max" + "running_idx", so sanh
// voi tung mau magnitude den (dat lai ve mau dau tien khi gap in_sof). Khi
// gap in_last (bin cuoi cung cua frame), SAU KHI da cap nhat so sanh cho
// chinh mau do, ket qua duoc CHOT ra ngoai (peak_valid=1, 1 xung duy nhat)
// o CHU KY KE TIEP -- vi running_max/running_idx la thanh ghi dong bo, gia
// tri da bao gom dong gop cua mau cuoi cung chi thuc su on dinh tu chu ky
// sau khi in_last duoc xu ly.
//
// LUU Y VE CHI SO BIN: peak_bin_idx tra ve dung "ngon ngu" chi so bin nhu
// magnitude_unit.v cung cap qua in_bin_idx -- neu loi FFT xuat theo thu tu
// bit-reversed (mac dinh cua kien truc R2^2SDF), peak_bin_idx o day CUNG la
// chi so theo thu tu bit-reversed, CHUA phai chi so tan so tu nhien. Muon
// doi ve tan so Hz thuc can: freq_hz = bit_reverse(peak_bin_idx, log2(N)) *
// fs / N -- phep bit-reverse nay co the thuc hien o tang tich hop top-level
// hoac trong bin_ram_output.v (chua trien khai trong ban nay).
// =============================================================================

`timescale 1ns / 1ps

module peak_detector #(
    parameter integer NUM_BINS   = 128,
    parameter integer DATA_WIDTH = 16     // do rong magnitude (UNSIGNED, khop magnitude_unit.v)
)(
    input  wire                          clk,
    input  wire                          rst_n,

    input  wire                          in_valid,
    input  wire [DATA_WIDTH-1:0]         in_magnitude,   // UNSIGNED, tu magnitude_unit.v
    input  wire [$clog2(NUM_BINS)-1:0]   in_bin_idx,
    input  wire                          in_sof,
    input  wire                          in_last,

    output reg                           peak_valid,     // 1 xung duy nhat khi frame hoan tat
    output reg  [DATA_WIDTH-1:0]         peak_magnitude,
    output reg  [$clog2(NUM_BINS)-1:0]   peak_bin_idx
);

    localparam integer BIN_ADDR_W = $clog2(NUM_BINS);

    reg [DATA_WIDTH-1:0]  running_max;
    reg [BIN_ADDR_W-1:0]  running_idx;
    reg                   frame_done_pending; // co bao: frame vua ket thuc chu ky truoc, chot output ngay bay gio

    always @(posedge clk) begin
        if (!rst_n) begin
            running_max        <= {DATA_WIDTH{1'b0}};
            running_idx        <= {BIN_ADDR_W{1'b0}};
            frame_done_pending <= 1'b0;

            peak_valid          <= 1'b0;
            peak_magnitude       <= {DATA_WIDTH{1'b0}};
            peak_bin_idx         <= {BIN_ADDR_W{1'b0}};
        end else begin
            // mac dinh: khong co xung moi, tru khi frame_done_pending kich hoat ben duoi
            peak_valid <= 1'b0;

            if (in_valid) begin
                if (in_sof) begin
                    // mau dau tien cua frame moi: khoi tao lai running_max
                    // truc tiep bang chinh gia tri nay (khong so sanh voi
                    // max cu, vi max cu thuoc frame TRUOC)
                    running_max <= in_magnitude;
                    running_idx <= in_bin_idx;
                end else if (in_magnitude > running_max) begin
                    running_max <= in_magnitude;
                    running_idx <= in_bin_idx;
                end

                if (in_last) begin
                    // frame vua xu ly xong mau cuoi cung (co the CHINH mau
                    // nay la max moi, da duoc cap nhat o nhanh tren trong
                    // CUNG chu ky nay) -- bao hieu chot ket qua o chu ky SAU
                    frame_done_pending <= 1'b1;
                end
            end

            if (frame_done_pending) begin
                peak_valid     <= 1'b1;
                peak_magnitude <= running_max;  // da on dinh, bao gom ca mau cuoi
                peak_bin_idx   <= running_idx;
                frame_done_pending <= 1'b0;
            end
        end
    end

endmodule
