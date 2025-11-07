// Three-row line buffer for streaming pixels, supports stride 1/2.
module line_buffer_3row
#(
    parameter DATAW = 8,
    parameter IFM_CH = 8,
    parameter WIDTH_MAX = 64
)(
    input                     clk,
    input                     rst_b,
    input                     in_vld,
    input      [DATAW*IFM_CH-1:0] in_data,
    input      [15:0]         cfg_width,
    input      [3:0]          cfg_stride,
    output reg                win_vld,
    output reg [DATAW*IFM_CH*9-1:0] win_data
);

    localparam TOTAL_CH = DATAW*IFM_CH;
    reg [DATAW*IFM_CH-1:0] row0 [0:WIDTH_MAX-1];
    reg [DATAW*IFM_CH-1:0] row1 [0:WIDTH_MAX-1];
    reg [DATAW*IFM_CH-1:0] row2 [0:WIDTH_MAX-1];

    reg [15:0] wr_ptr;
    reg [15:0] rd_ptr;
    reg [1:0]  row_count;

    integer i;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            wr_ptr <= 16'h0;
            rd_ptr <= 16'h0;
            row_count <= 2'h0;
            win_vld <= 1'b0;
            for (i = 0; i < WIDTH_MAX; i = i + 1) begin
                row0[i] <= {TOTAL_CH{1'b0}};
                row1[i] <= {TOTAL_CH{1'b0}};
                row2[i] <= {TOTAL_CH{1'b0}};
            end
        end else begin
            if (in_vld) begin
                row2[wr_ptr] <= row1[wr_ptr];
                row1[wr_ptr] <= row0[wr_ptr];
                row0[wr_ptr] <= in_data;
                if (wr_ptr == cfg_width - 1) begin
                    wr_ptr <= 16'h0;
                    if (row_count != 2'h3) begin
                        row_count <= row_count + 1'b1;
                    end
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
            if (row_count >= 2'h2) begin
                win_vld <= 1'b1;
                win_data <= {
                    row2[rd_ptr], row2[rd_ptr + 1], row2[rd_ptr + 2],
                    row1[rd_ptr], row1[rd_ptr + 1], row1[rd_ptr + 2],
                    row0[rd_ptr], row0[rd_ptr + 1], row0[rd_ptr + 2]
                };
                if (cfg_stride == 4'd2) begin
                    rd_ptr <= rd_ptr + 2;
                end else begin
                    rd_ptr <= rd_ptr + 1;
                end
                if (rd_ptr >= cfg_width - 3) begin
                    rd_ptr <= 16'h0;
                    win_vld <= 1'b0;
                end
            end else begin
                win_vld <= 1'b0;
            end
        end
    end
endmodule
