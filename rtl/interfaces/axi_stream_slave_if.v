// =============================================================================
// Module : axi_stream_slave_if   (giao dien AXI4-Stream SLAVE — skid buffer)
// -----------------------------------------------------------------------------
// Lop bien AXI4-Stream phia VAO cua IP: nhan beat AXI-S (tvalid/tdata/tready) va
// chuyen thanh handshake noi bo don gian (m_valid/m_data + m_ready). Dung SKID
// BUFFER 1 muc de: (1) cach ly timing (dang ky bien), (2) tuan thu AXI (tready co
// the ha xuong ma KHONG mat du lieu), (3) thong luong day (1 beat/chu ky).
// Dat truoc input_buffer_fsm. rst_n active-low.
// =============================================================================
`timescale 1ns / 1ps

module axi_stream_slave_if #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,
    // ---- AXI4-Stream slave ----
    input  wire                          s_axis_tvalid,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    output wire                          s_axis_tready,
    // ---- Handshake noi bo (downstream) ----
    output wire                          m_valid,
    output wire signed [DATA_WIDTH-1:0]  m_data,
    input  wire                          m_ready
);
    reg                          valid_r, skid_valid;
    reg signed [DATA_WIDTH-1:0]  data_r,  data_skid;

    assign s_axis_tready = ~skid_valid;      // con cho khi skid trong
    assign m_valid       = valid_r;
    assign m_data        = data_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r <= 1'b0; skid_valid <= 1'b0; data_r <= 0; data_skid <= 0;
        end else begin
            if (m_ready || !valid_r) begin
                // o ra dang trong -> nap tu skid neu co, khong thi nap tu AXI
                if (skid_valid) begin
                    data_r <= data_skid; valid_r <= 1'b1; skid_valid <= 1'b0;
                end else begin
                    data_r <= s_axis_tdata; valid_r <= s_axis_tvalid;
                end
            end else if (s_axis_tvalid && s_axis_tready) begin
                // o ra ket, giu beat den vao skid (khong mat du lieu)
                data_skid <= s_axis_tdata; skid_valid <= 1'b1;
            end
        end
    end
endmodule
