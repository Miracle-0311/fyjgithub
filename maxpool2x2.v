// 2x2 max pooling with stride 2.
module maxpool2x2
#(
    parameter DATAW = 8
)(
    input                 clk,
    input                 rst_b,
    input                 in_vld,
    input      [DATAW-1:0] in_data,
    input      [15:0]     cfg_out_width,
    output reg            out_vld,
    output reg [DATAW-1:0] out_data
);

    reg [DATAW-1:0] row_buf [0:255];
    reg [15:0]      wr_ptr;
    reg [15:0]      rd_ptr;
    reg [DATAW-1:0] max_temp;
    reg             toggle_row;
    reg [DATAW-1:0] prev_row_val;
    reg             have_prev;

    integer i;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            wr_ptr <= 16'h0;
            rd_ptr <= 16'h0;
            toggle_row <= 1'b0;
            out_vld <= 1'b0;
            out_data <= {DATAW{1'b0}};
            for (i = 0; i < 256; i = i + 1) begin
                row_buf[i] <= {DATAW{1'b0}};
            end
            have_prev <= 1'b0;
            prev_row_val <= {DATAW{1'b0}};
            max_temp <= {DATAW{1'b0}};
        end else begin
            if (in_vld) begin
                if (!toggle_row) begin
                    row_buf[wr_ptr] <= in_data;
                    if (wr_ptr == cfg_out_width * 2 - 1) begin
                        wr_ptr <= 16'h0;
                        toggle_row <= 1'b1;
                    end else begin
                        wr_ptr <= wr_ptr + 1'b1;
                    end
                    out_vld <= 1'b0;
                end else begin
                    prev_row_val <= row_buf[rd_ptr];
                    if (in_data > row_buf[rd_ptr]) begin
                        max_temp <= in_data;
                    end else begin
                        max_temp <= row_buf[rd_ptr];
                    end
                    if (!have_prev) begin
                        have_prev <= 1'b1;
                        out_vld <= 1'b0;
                    end else begin
                        if (max_temp > prev_row_val) begin
                            out_data <= max_temp;
                        end else begin
                            out_data <= prev_row_val;
                        end
                        out_vld <= 1'b1;
                        have_prev <= 1'b0;
                    end
                    if (rd_ptr == cfg_out_width * 2 - 1) begin
                        rd_ptr <= 16'h0;
                        toggle_row <= 1'b0;
                    end else begin
                        rd_ptr <= rd_ptr + 1'b1;
                    end
                end
            end else begin
                out_vld <= 1'b0;
            end
        end
    end
endmodule
