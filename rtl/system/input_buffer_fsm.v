`timescale 1ns / 1ps

module input_buffer_fsm #(
    parameter integer N          = 256,
    parameter integer DATA_WIDTH = 16
)(
    input  wire                          clk,
    input  wire                          rst_n,

    //AXI4-Stream slave: audio in
    input  wire                          s_axis_tvalid,
    input  wire signed [DATA_WIDTH-1:0]  s_axis_tdata,
    output wire                          s_axis_tready,

    //Streaming output: gom thanh frame N mau
    output wire                          out_valid,
    output wire signed [DATA_WIDTH-1:0]  out_data,
    output wire                          out_sof,
    output wire                          out_last,
    input  wire                          out_ready 
);

    localparam integer ADDR_W = $clog2(N);

    reg signed [DATA_WIDTH-1:0] mem0 [0:N-1];
    reg signed [DATA_WIDTH-1:0] mem1 [0:N-1];

    // Trang thai GHI 
    reg               wr_buf;      
    reg [ADDR_W-1:0]  wr_ptr;

    // Trang thai DOC
    reg               rd_buf; 
    reg [ADDR_W-1:0]  rd_ptr;
    reg               rd_active; 

    reg buf0_full, buf1_full;

    wire wr_buf_is_full = (wr_buf == 1'b0) ? buf0_full : buf1_full;
    assign s_axis_tready = ~wr_buf_is_full;

    wire rd_buf_is_full  = (rd_buf == 1'b0) ? buf0_full : buf1_full;


    assign out_valid = rd_active;
    assign out_data  = (rd_buf == 1'b0) ? mem0[rd_ptr] : mem1[rd_ptr];
    assign out_sof   = rd_active && (rd_ptr == {ADDR_W{1'b0}});
    assign out_last  = rd_active && (rd_ptr == N-1);

 
    integer wi; 

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

            if (!rd_active) begin
                if (rd_buf_is_full) begin
                    rd_active <= 1'b1;
                    rd_ptr    <= {ADDR_W{1'b0}};
                end
            end else if (out_ready) begin
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
        end
    end

endmodule
