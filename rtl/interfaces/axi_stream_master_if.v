// =============================================================================
// Module : axi_stream_master_if   (giao dien AXI4-Stream MASTER — skid buffer)
// -----------------------------------------------------------------------------
// Lop bien AXI4-Stream phia RA cua IP: nhan luong pho da dong khung (in_valid/
// in_data/in_sof/in_last + in_ready) va xuat beat AXI-S master:
//   m_axis_tvalid/tdata/tready, tlast = in_last (het frame),
//   tuser[0] = in_sof (dau frame). SKID BUFFER 1 muc cho backpressure (tready).
// rst_n active-low.
// =============================================================================
`timescale 1ns / 1ps

module axi_stream_master_if #(
    parameter integer DATA_WIDTH = 16,
    parameter integer USER_WIDTH = 1
)(
    input  wire                          clk,
    input  wire                          rst_n,
    // ---- Handshake noi bo (upstream) ----
    input  wire                          in_valid,
    input  wire [DATA_WIDTH-1:0]         in_data,   // magnitude UNSIGNED
    input  wire                          in_sof,
    input  wire                          in_last,
    output wire                          in_ready,
    // ---- AXI4-Stream master ----
    output wire                          m_axis_tvalid,
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,
    output wire                          m_axis_tlast,
    output wire [USER_WIDTH-1:0]         m_axis_tuser,
    input  wire                          m_axis_tready
);
    reg                    valid_r, skid_valid;
    reg [DATA_WIDTH-1:0]   data_r,  data_skid;
    reg                    last_r,  last_skid;
    reg [USER_WIDTH-1:0]   user_r,  user_skid;

    assign in_ready      = ~skid_valid;
    assign m_axis_tvalid = valid_r;
    assign m_axis_tdata  = data_r;
    assign m_axis_tlast  = last_r;
    assign m_axis_tuser  = user_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r<=1'b0; skid_valid<=1'b0; data_r<=0; data_skid<=0;
            last_r<=1'b0; last_skid<=1'b0; user_r<=0; user_skid<=0;
        end else begin
            if (m_axis_tready || !valid_r) begin
                if (skid_valid) begin
                    data_r<=data_skid; last_r<=last_skid; user_r<=user_skid;
                    valid_r<=1'b1; skid_valid<=1'b0;
                end else begin
                    data_r<=in_data; last_r<=in_last; user_r<=in_sof;    // tu dong zero-extend len USER_WIDTH
                    valid_r<=in_valid;
                end
            end else if (in_valid && in_ready) begin
                data_skid<=in_data; last_skid<=in_last; user_skid<=in_sof;
                skid_valid<=1'b1;
            end
        end
    end
endmodule
