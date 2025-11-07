// ReLU activation with saturation back to DATAW bits.
module relu
#(
    parameter DATAW = 8
)(
    input             clk,
    input             rst_b,
    input             in_vld,
    input      [31:0] in_data,
    output reg        out_vld,
    output reg [DATAW-1:0] out_data
);

    reg        vld_stage;
    reg [31:0] data_stage;
    reg [31:0] relu_stage;
    reg [DATAW-1:0] sat_stage;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            vld_stage <= 1'b0;
            data_stage <= 32'h0;
        end else begin
            vld_stage <= in_vld;
            if (in_vld) begin
                data_stage <= in_data;
            end
        end
    end

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            out_vld <= 1'b0;
            out_data <= {DATAW{1'b0}};
            relu_stage <= 32'h0;
            sat_stage <= {DATAW{1'b0}};
        end else begin
            out_vld <= vld_stage;
            if (vld_stage) begin
                if (data_stage[31]) begin
                    relu_stage <= 32'h0;
                end else begin
                    relu_stage <= data_stage;
                end
                if (data_stage[31]) begin
                    sat_stage <= {DATAW{1'b0}};
                end else begin
                    if (|data_stage[31:DATAW]) begin
                        sat_stage <= {DATAW{1'b1}};
                    end else begin
                        sat_stage <= data_stage[DATAW-1:0];
                    end
                end
                out_data <= sat_stage;
            end
        end
    end
endmodule
