// =============================================================================
// Module : input_buffer_fsm
// -----------------------------------------------------------------------------
// Gom N mau lien tiep tu cong vao AXI4-Stream-style (s_axis_*) thanh 1 frame,
// dung ky thuat DOUBLE BUFFER (ping-pong): trong khi 1 buffer dang duoc DOC
// ra cho pipeline downstream (Window Unit / FFT core), buffer con lai dang
// duoc GHI cac mau moi vao -- cho phep throughput lien tuc 1 mau/chu ky,
// khong bi gian doan giua cac frame (dung yeu cau spec: "Throughput 1
// mau/chu ky, streaming").
//
// -----------------------------------------------------------------------------
// Cong vao: AXI4-Stream slave don gian (tvalid/tready), khong dung tkeep/tid.
// Cong ra: giao thuc valid/ready streaming noi bo, kem 2 co bao khung:
//   out_sof  = 1 tai mau DAU TIEN cua frame (n=0)
//   out_last = 1 tai mau CUOI CUNG cua frame (n=N-1)
// Day la 2 tin hieu framing then chot de Window Unit va FFT control FSM
// (chua trien khai) biet vi tri/ranh gioi frame ma khong can dem lai tu dau.
//
// -----------------------------------------------------------------------------
// BAO VE TRAN (overflow protection): neu buffer dich ghi (wr_buf) VAN con
// danh dau "day, chua duoc doc het" (buf_full[wr_buf]==1, tuc downstream doc
// cham hon toc do vao), s_axis_tready se ha xuong 0 de tam dung nhan mau moi
// -- tranh ghi de len du lieu chua duoc xu ly. Day la co che backpressure tu
// nhien, hoan toan an toan (khong mat du lieu, chi lam nguon phai cho).
//
// -----------------------------------------------------------------------------
// GIAO THUC OUTPUT: dung mo hinh "valid duy tri toi khi duoc chap nhan"
// chuan (out_valid=1 va out_data on dinh cho toi khi out_ready=1 xac nhan
// giao dich, KHONG tu y bo qua mau) -- tranh loi phoi hop valid/ready tinh
// vi da gap phai trong qua trinh phat trien twiddle_rom/complex_multiplier
// (do tron lan tin hieu dong bo va to hop khong dung cach).
// =============================================================================

`timescale 1ns / 1ps

module input_buffer_fsm #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // ---- AXI4-Stream slave: nguon audio vao ----
    input  wire                          s_axis_tvalid,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    output wire                          s_axis_tready,

    // ---- Streaming output: da gom thanh frame N mau ----
    output wire                          out_valid,
    output wire signed [DATA_WIDTH-1:0]  out_data,
    output wire                          out_sof,
    output wire                          out_last,
    input  wire                          out_ready   // backpressure tu downstream
);

    localparam integer ADDR_W = $clog2(N);

    // -------------------------------------------------------------------
    // 2 buffer ping-pong
    // -------------------------------------------------------------------
    reg signed [DATA_WIDTH-1:0] mem0 [0:N-1];
    reg signed [DATA_WIDTH-1:0] mem1 [0:N-1];

    // ---- Trang thai GHI ----
    reg               wr_buf;      // buffer dang duoc ghi: 0 hoac 1
    reg [ADDR_W-1:0]  wr_ptr;

    // ---- Trang thai DOC ----
    reg               rd_buf;      // buffer dang duoc doc: 0 hoac 1
    reg [ADDR_W-1:0]  rd_ptr;
    reg               rd_active;   // dang trong qua trinh doc 1 frame

    // ---- Co bao trang thai day/rong cua tung buffer ----
    reg buf0_full, buf1_full;

    wire wr_buf_is_full = (wr_buf == 1'b0) ? buf0_full : buf1_full;
    assign s_axis_tready = ~wr_buf_is_full;

    wire rd_buf_is_full  = (rd_buf == 1'b0) ? buf0_full : buf1_full;

    // -------------------------------------------------------------------
    // Output to hop: valid = dang doc, data = mau tai rd_ptr cua rd_buf.
    // Chi advance trang thai (rd_ptr, chuyen buffer...) khi giao dich thuc
    // su xay ra (out_valid && out_ready) -- xem always block ben duoi.
    // -------------------------------------------------------------------
    assign out_valid = rd_active;
    assign out_data  = (rd_buf == 1'b0) ? mem0[rd_ptr] : mem1[rd_ptr];
    assign out_sof   = rd_active && (rd_ptr == {ADDR_W{1'b0}});
    assign out_last  = rd_active && (rd_ptr == N-1);

    // -------------------------------------------------------------------
    // FSM chinh (1 always block duy nhat de tranh xung dot ghi/doc tren
    // buf0_full/buf1_full -- xem phan tich an toan trong tai lieu thiet ke)
    // -------------------------------------------------------------------
    integer wi; // bien vong lap khoi tao mem (chi dung trong initial/reset, mo phong)

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_buf    <= 1'b0;
            wr_ptr    <= {ADDR_W{1'b0}};
            rd_buf    <= 1'b0;
            rd_ptr    <= {ADDR_W{1'b0}};
            rd_active <= 1'b0;
            buf0_full <= 1'b0;
            buf1_full <= 1'b0;
        end else begin
            // ---- GHI: nhan mau moi neu con cho (tready) ----
            if (s_axis_tvalid && s_axis_tready) begin
                if (wr_buf == 1'b0)
                    mem0[wr_ptr] <= s_axis_tdata;
                else
                    mem1[wr_ptr] <= s_axis_tdata;

                if (wr_ptr == N-1) begin
                    wr_ptr <= {ADDR_W{1'b0}};
                    if (wr_buf == 1'b0)
                        buf0_full <= 1'b1;
                    else
                        buf1_full <= 1'b1;
                    wr_buf <= ~wr_buf;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end

            // ---- DOC: khoi dong khi buffer muc tieu da day ----
            if (!rd_active) begin
                if (rd_buf_is_full) begin
                    rd_active <= 1'b1;
                    rd_ptr    <= {ADDR_W{1'b0}};
                end
            end else if (out_ready) begin
                // giao dich thanh cong (out_valid=1 vi rd_active=1, out_ready=1)
                if (rd_ptr == N-1) begin
                    rd_ptr <= {ADDR_W{1'b0}};
                    if (rd_buf == 1'b0)
                        buf0_full <= 1'b0;
                    else
                        buf1_full <= 1'b0;
                    rd_buf    <= ~rd_buf;
                    rd_active <= 1'b0;
                end else begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
            end
            // out_ready == 0: giu nguyen rd_ptr/rd_active -> out_data (to hop
            // tu mem[rd_buf][rd_ptr]) tu dong giu nguyen gia tri, dung ngu
            // nghia "valid duy tri cho den khi duoc chap nhan"
        end
    end

endmodule
