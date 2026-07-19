
`timescale 1ns / 1ps

module fft_analyzer_ip #(
    parameter integer N           = 256,
    parameter integer DATA_WIDTH  = 16,
    parameter integer FFT_LATENCY = 291,
    parameter integer ENABLE_LOG  = 1,
    parameter         WINDOW_FILE  = "window_coeff.mem",
    parameter         TW_RE_FILE   = "twiddle_re.mem",
    parameter         TW_IM_FILE   = "twiddle_im.mem"
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    // AXI-S slave: audio in
    input  wire                          s_axis_tvalid,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    output wire                          s_axis_tready,
    // AXI-S master: pho don bien (natural order)
    output wire                          m_axis_tvalid,
    output wire [DATA_WIDTH-1:0]         m_axis_tdata,     // magnitude UNSIGNED
    output wire                          m_axis_tlast,    
    output wire [0:0]                    m_axis_tuser,     
    input  wire                          m_axis_tready,
    // Peak Spectrum + State
    output wire                          peak_valid,
    output wire [DATA_WIDTH-1:0]         peak_magnitude,
    output wire [$clog2(N/2)-1:0]        peak_bin_idx,
    output wire                          busy,
    output wire                          core_en,
    output wire [31:0]                   frame_count
);
    // slave IF 
    wire                         iv, irdy;
    wire signed [DATA_WIDTH-1:0] idat;
    axi_stream_slave_if #(.DATA_WIDTH(DATA_WIDTH)) u_slv (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tdata(s_axis_tdata), .s_axis_tready(s_axis_tready),
        .m_valid(iv), .m_data(idat), .m_ready(irdy)
    );

    // loi tich hop
    wire                    sv, ssof, slast;
    wire [DATA_WIDTH-1:0]   smag;
    wire [$clog2(N)-1:0]    sbin;
    project_top #(
        .N(N), .DATA_WIDTH(DATA_WIDTH), .FFT_LATENCY(FFT_LATENCY), .ENABLE_LOG(ENABLE_LOG),
        .WINDOW_FILE(WINDOW_FILE), .TW_RE_FILE(TW_RE_FILE), .TW_IM_FILE(TW_IM_FILE)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tvalid(iv), .s_axis_tdata(idat), .s_axis_tready(irdy),
        .spec_valid(sv), .spec_magnitude(smag), .spec_bin_idx(sbin), .spec_sof(ssof), .spec_last(slast),
        .peak_valid(peak_valid), .peak_magnitude(peak_magnitude), .peak_bin_idx(peak_bin_idx)
    );

    // master IF
    wire spec_ready_unused;
    axi_stream_master_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(1)) u_mst (
        .clk(clk), .rst_n(rst_n),
        .in_valid(sv), .in_data(smag), .in_sof(ssof), .in_last(slast), .in_ready(spec_ready_unused),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tdata(m_axis_tdata),
        .m_axis_tlast(m_axis_tlast), .m_axis_tuser(m_axis_tuser), .m_axis_tready(m_axis_tready)
    );

    // control/status
    fft_control_fsm #(.CNT_WIDTH(32)) u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start), .frame_tick(peak_valid),
        .core_en(core_en), .busy(busy), .frame_done(), .frame_count(frame_count)
    );
endmodule
