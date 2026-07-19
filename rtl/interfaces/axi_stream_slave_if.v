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

    assign s_axis_tready = ~skid_valid;   
    assign m_valid       = valid_r;
    assign m_data        = data_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r <= 1'b0; skid_valid <= 1'b0; data_r <= 0; data_skid <= 0;
        end else begin
            if (m_ready || !valid_r) begin
                if (skid_valid) begin
                    data_r <= data_skid; valid_r <= 1'b1; skid_valid <= 1'b0;
                end else begin
                    data_r <= s_axis_tdata; valid_r <= s_axis_tvalid;
                end
            end else if (s_axis_tvalid && s_axis_tready) begin
                data_skid <= s_axis_tdata; skid_valid <= 1'b1;
            end
        end
    end
endmodule
