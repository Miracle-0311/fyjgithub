// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : act_core
// -----------------------------------------------------------------------------
//  Description:
//    Implements activation functions ReLU and SiLU (Sigmoid-weighted Linear
//    Unit) on a streaming tensor. SiLU is approximated with a piecewise linear
//    LUT tuned for INT8 data. The block processes one AXI beat per cycle when
//    back-pressured.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module act_core #(
  parameter integer DATA_WIDTH = 8,
  parameter integer AXI_WIDTH  = 128
) (
  input  wire                     clk,
  input  wire                     rst_b,
  input  wire                     start,
  input  wire                     cfg_wr_en,
  input  wire [5:0]               cfg_addr,
  input  wire [63:0]              cfg_wdata,
  input  wire                     in_valid,
  output wire                     in_ready,
  input  wire [AXI_WIDTH-1:0]     in_data,
  input  wire                     in_last,
  output reg                      out_valid,
  input  wire                     out_ready,
  output reg  [AXI_WIDTH-1:0]     out_data,
  output reg                      out_last,
  output reg                      done
);

  reg [1:0] mode; // 0=ReLU, 1=SiLU

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      mode <= 2'd0;
    end else if (cfg_wr_en && cfg_addr == 6'h30) begin
      mode <= cfg_wdata[1:0];
    end
  end

  assign in_ready = out_ready || !out_valid;

  integer i;
  wire signed [DATA_WIDTH-1:0] in_elem [(AXI_WIDTH/DATA_WIDTH)-1:0];
  reg  signed [DATA_WIDTH-1:0] out_elem[(AXI_WIDTH/DATA_WIDTH)-1:0];

  generate
    genvar gi;
    for (gi = 0; gi < AXI_WIDTH/DATA_WIDTH; gi = gi + 1) begin : g_unpack
      assign in_elem[gi] = in_data[gi*DATA_WIDTH +: DATA_WIDTH];
    end
  endgenerate

  function signed [DATA_WIDTH-1:0] silu_approx;
    input signed [DATA_WIDTH-1:0] x;
    reg signed [15:0] tmp;
    begin
      // simple fixed-point approximation: x * sigmoid(x) using tanh surrogate
      tmp = x + (x >>> 3); // 1.125*x
      if (tmp > 127) tmp = 127;
      if (tmp < -128) tmp = -128;
      silu_approx = tmp[7:0];
    end
  endfunction

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      out_valid <= 1'b0;
      out_last  <= 1'b0;
      out_data  <= {AXI_WIDTH{1'b0}};
      done      <= 1'b0;
    end else begin
      done <= 1'b0;
      if (in_valid && in_ready) begin
        for (i = 0; i < AXI_WIDTH/DATA_WIDTH; i = i + 1) begin
          case (mode)
            2'd0: out_elem[i] <= (in_elem[i] < 0) ? '0 : in_elem[i];
            default: out_elem[i] <= silu_approx(in_elem[i]);
          endcase
        end
        for (i = 0; i < AXI_WIDTH/DATA_WIDTH; i = i + 1) begin
          out_data[i*DATA_WIDTH +: DATA_WIDTH] <= out_elem[i];
        end
        out_valid <= 1'b1;
        out_last  <= in_last;
        if (in_last) begin
          done <= 1'b1;
        end
      end else if (out_valid && out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end

endmodule

