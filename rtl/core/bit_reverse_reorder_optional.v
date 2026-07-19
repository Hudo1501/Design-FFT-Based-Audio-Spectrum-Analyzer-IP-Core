`timescale 1ns / 1ps

module bit_reverse_reorder #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          in_valid,
    input  wire signed [DATA_WIDTH-1:0]  in_re,
    input  wire signed [DATA_WIDTH-1:0]  in_im,
    input  wire                          in_sof,
    input  wire                          in_last,
    output reg                           out_valid,
    output reg  signed [DATA_WIDTH-1:0]  out_re,
    output reg  signed [DATA_WIDTH-1:0]  out_im,
    output reg  [$clog2(N)-1:0]          out_bin_idx,
    output reg                           out_sof,
    output reg                           out_last
);
    localparam integer LOG2N = $clog2(N);

    function [LOG2N-1:0] bitrev;
        input [LOG2N-1:0] x; integer b;
        begin for (b=0;b<LOG2N;b=b+1) bitrev[b]=x[LOG2N-1-b]; end
    endfunction

    reg signed [DATA_WIDTH-1:0] ram_re0 [0:N-1], ram_im0 [0:N-1];
    reg signed [DATA_WIDTH-1:0] ram_re1 [0:N-1], ram_im1 [0:N-1];

    reg              wr_sel;
    reg  [LOG2N-1:0] arr_idx;
    wire [LOG2N-1:0] arr_cur = in_sof ? {LOG2N{1'b0}} : (arr_idx + 1'b1);
    wire [LOG2N-1:0] wr_addr = bitrev(arr_cur);
    always @(posedge clk) begin
        if (!rst_n) arr_idx <= {LOG2N{1'b0}};
        else if (in_valid) begin
            arr_idx <= arr_cur;
            if (wr_sel==1'b0) begin ram_re0[wr_addr]<=in_re; ram_im0[wr_addr]<=in_im; end
            else              begin ram_re1[wr_addr]<=in_re; ram_im1[wr_addr]<=in_im; end
        end
    end

    reg              rd_active, rd_sel;
    reg  [LOG2N-1:0] rd_idx;
    reg  signed [DATA_WIDTH-1:0] rd_re, rd_im;
    reg              rd_active_d, rd_sof_d, rd_last_d;
    reg  [LOG2N-1:0] rd_idx_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_sel<=0; rd_active<=0; rd_sel<=0; rd_idx<=0;
            out_valid<=0; out_sof<=0; out_last<=0; out_bin_idx<=0; out_re<=0; out_im<=0;
            rd_active_d<=0; rd_sof_d<=0; rd_last_d<=0; rd_idx_d<=0;
        end else begin
            if (in_valid && in_last) begin
                rd_sel<=wr_sel; wr_sel<=~wr_sel; rd_active<=1'b1; rd_idx<=0;
            end else if (rd_active && (rd_idx==N-1)) begin
                rd_active<=1'b0;
            end else if (rd_active) begin
                rd_idx<=rd_idx+1'b1;
            end
            rd_active_d<=rd_active; rd_idx_d<=rd_idx;
            rd_sof_d <= rd_active && (rd_idx=={LOG2N{1'b0}});
            rd_last_d<= rd_active && (rd_idx==N-1);
            rd_re <= (rd_sel==1'b0) ? ram_re0[rd_idx] : ram_re1[rd_idx];
            rd_im <= (rd_sel==1'b0) ? ram_im0[rd_idx] : ram_im1[rd_idx];
            out_valid<=rd_active_d; out_re<=rd_re; out_im<=rd_im; out_bin_idx<=rd_idx_d;
            out_sof<=rd_sof_d; out_last<=rd_last_d;
        end
    end
endmodule
