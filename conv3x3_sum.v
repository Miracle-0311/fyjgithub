// 3x3 convolution sum over multiple channels with two-stage pipeline.
module conv3x3_sum
#(
    parameter DATAW = 8,
    parameter IFM_CH = 8,
    parameter K = 3
)(
    input                             clk,
    input                             rst_b,
    input                             in_vld,
    input      [3:0]                  in_ch_cfg,
    input      [DATAW*IFM_CH*K*K-1:0] win_data,
    input      [DATAW*IFM_CH*K*K-1:0] weight_data,
    output reg                        out_vld,
    output reg [31:0]                 out_sum
);

    localparam TOTAL = IFM_CH*K*K;

    reg [DATAW-1:0] win_stage [0:TOTAL-1];
    reg [DATAW-1:0] weight_stage [0:TOTAL-1];
    reg [3:0]       ch_stage0;
    reg             vld_stage0;

    reg [31:0] mult_stage [0:TOTAL-1];
    reg [3:0]  ch_stage1;
    reg        vld_stage1;

    reg [31:0] sum_temp;

    integer i;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            vld_stage0 <= 1'b0;
            ch_stage0 <= 4'h0;
            for (i = 0; i < TOTAL; i = i + 1) begin
                win_stage[i] <= {DATAW{1'b0}};
                weight_stage[i] <= {DATAW{1'b0}};
            end
        end else begin
            vld_stage0 <= in_vld;
            ch_stage0 <= in_ch_cfg;
            if (in_vld) begin
                for (i = 0; i < TOTAL; i = i + 1) begin
                    win_stage[i] <= win_data[i*DATAW +: DATAW];
                    weight_stage[i] <= weight_data[i*DATAW +: DATAW];
                end
            end
        end
    end

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            vld_stage1 <= 1'b0;
            ch_stage1 <= 4'h0;
            for (i = 0; i < TOTAL; i = i + 1) begin
                mult_stage[i] <= 32'h0;
            end
        end else begin
            vld_stage1 <= vld_stage0;
            ch_stage1 <= ch_stage0;
            if (vld_stage0) begin
                for (i = 0; i < TOTAL; i = i + 1) begin
                    if (i < ch_stage0 * K * K) begin
                        mult_stage[i] <= $signed({1'b0,weight_stage[i]}) * $signed({1'b0,win_stage[i]});
                    end else begin
                        mult_stage[i] <= 32'h0;
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            out_vld <= 1'b0;
            out_sum <= 32'h0;
        end else begin
            out_vld <= vld_stage1;
            if (vld_stage1) begin
                sum_temp = 32'h0;
                for (i = 0; i < TOTAL; i = i + 1) begin
                    sum_temp = sum_temp + mult_stage[i];
                end
                out_sum <= sum_temp;
            end
        end
    end
endmodule
