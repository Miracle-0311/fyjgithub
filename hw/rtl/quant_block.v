// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : quant_block
// -----------------------------------------------------------------------------
//  Description:
//    Applies per-channel affine quantization on INT32 accumulators to produce
//    INT8 outputs. Scales are represented as signed Q8.8 fixed-point values and
//    zero-point is 8-bit unsigned. The block consumes AXI-width chunks of
//    accumulators and outputs quantized bytes with rounding to nearest-even.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module quant_block #(
  parameter integer DATA_WIDTH = 8,
  parameter integer ACC_WIDTH  = 32,
  parameter integer AXI_WIDTH  = 128
) (
  input  wire                     clk,
  input  wire                     rst_b,
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
  output reg                      out_last
);

  localparam integer CHANNELS_PER_BEAT = AXI_WIDTH / DATA_WIDTH;

  reg signed [15:0] scale_lut [0:CHANNELS_PER_BEAT-1];
  reg        [7:0]  zp_lut    [0:CHANNELS_PER_BEAT-1];

  integer idx;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      for (idx = 0; idx < CHANNELS_PER_BEAT; idx = idx + 1) begin
        scale_lut[idx] <= 16'h0100; // scale=1.0
        zp_lut[idx]    <= 8'h80;
      end
    end else if (cfg_wr_en && cfg_addr[5:4] == 2'b01) begin
      scale_lut[cfg_addr[3:0]] <= cfg_wdata[15:0];
      zp_lut[cfg_addr[3:0]]    <= cfg_wdata[23:16];
    end
  end

  assign in_ready = out_ready || !out_valid;

  wire signed [ACC_WIDTH-1:0] in_acc [0:CHANNELS_PER_BEAT-1];
  reg  [DATA_WIDTH-1:0]       out_q  [0:CHANNELS_PER_BEAT-1];

  generate
    genvar gi;
    for (gi = 0; gi < CHANNELS_PER_BEAT; gi = gi + 1) begin : g_unpack
      assign in_acc[gi] = in_data[gi*ACC_WIDTH +: ACC_WIDTH];
    end
  endgenerate

  function [DATA_WIDTH-1:0] quantize;
    input signed [ACC_WIDTH-1:0] acc;
    input signed [15:0] scale;
    input [7:0] zp;
    reg signed [31:0] scaled;
    reg signed [31:0] rounded;
    begin
      scaled = acc * scale; // Q32 * Q8.8 -> Q40.8
      // rounding to nearest even
      rounded = (scaled + 16'sh0080) >>> 8;
      if (rounded[31]) begin
        if (rounded < -128) rounded = -128;
      end else if (rounded > 127) begin
        rounded = 127;
      end
      quantize = rounded[7:0] + zp;
    end
  endfunction

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      out_valid <= 1'b0;
      out_last  <= 1'b0;
      out_data  <= {AXI_WIDTH{1'b0}};
    end else begin
      if (in_valid && in_ready) begin
        for (idx = 0; idx < CHANNELS_PER_BEAT; idx = idx + 1) begin
          out_q[idx] <= quantize(in_acc[idx], scale_lut[idx], zp_lut[idx]);
          out_data[idx*DATA_WIDTH +: DATA_WIDTH] <= out_q[idx];
        end
        out_valid <= 1'b1;
        out_last  <= in_last;
      end else if (out_valid && out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end

endmodule

