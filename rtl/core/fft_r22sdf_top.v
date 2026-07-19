`timescale 1ns / 1ps

module fft_r22sdf_top #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16,
    parameter         RE_FILE    = "twiddle_re.mem",
    parameter         IM_FILE    = "twiddle_im.mem",
    parameter integer LATENCY    = 291
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_re,
    input  wire signed [DATA_WIDTH-1:0]  in_im,     
    input  wire                          in_sof,
    input  wire                          in_last,  

    output wire                          out_valid,
    output wire signed [DATA_WIDTH-1:0]  out_re,
    output wire signed [DATA_WIDTH-1:0]  out_im,
    output wire                          out_sof,   
    output wire                          out_last   
);
    localparam integer LOG2N = $clog2(N);

    wire                        st_valid [0:LOG2N-1];
    wire signed [DATA_WIDTH-1:0] st_re   [0:LOG2N-1];
    wire signed [DATA_WIDTH-1:0] st_im   [0:LOG2N-1];
    wire                        st_sof   [0:LOG2N-1];

    genvar j;
    generate
        for (j = 0; j < LOG2N; j = j + 1) begin : g_stage
            stage_with_twiddle #(
                .N(N), .DATA_WIDTH(DATA_WIDTH), .J(j), .SCALE_EN(1),
                .HAS_TWIDDLE((j == LOG2N-1) ? 0 : 1),
                .RE_FILE(RE_FILE), .IM_FILE(IM_FILE)
            ) u_stage (
                .clk(clk), .rst_n(rst_n),
                .in_valid((j==0) ? in_valid : st_valid[j-1]),
                .in_re   ((j==0) ? in_re    : st_re[j-1]),
                .in_im   ((j==0) ? in_im    : st_im[j-1]),
                .in_sof  ((j==0) ? in_sof   : st_sof[j-1]),
                .out_valid(st_valid[j]), .out_re(st_re[j]), .out_im(st_im[j]), .out_sof(st_sof[j])
            );
        end
    endgenerate

    assign out_re = st_re[LOG2N-1];
    assign out_im = st_im[LOG2N-1];

    reg [LATENCY-1:0] sof_dl, val_dl;
    always @(posedge clk) begin
        if (!rst_n) begin sof_dl <= {LATENCY{1'b0}}; val_dl <= {LATENCY{1'b0}}; end
        else if (in_valid) begin
            sof_dl <= {sof_dl[LATENCY-2:0], in_sof};
            val_dl <= {val_dl[LATENCY-2:0], 1'b1};
        end
    end
    wire out_sof_w = in_valid && sof_dl[LATENCY-1];
    wire out_val_w = in_valid && val_dl[LATENCY-1];

    reg  [LOG2N-1:0] prev_bin;
    wire [LOG2N-1:0] cur_bin = out_sof_w ? {LOG2N{1'b0}} : (prev_bin + 1'b1);
    always @(posedge clk) begin
        if (!rst_n)          prev_bin <= {LOG2N{1'b0}};
        else if (out_val_w)  prev_bin <= cur_bin;
    end

    assign out_valid = out_val_w;
    assign out_sof   = out_sof_w;
    assign out_last  = out_val_w && (cur_bin == N-1);
endmodule
