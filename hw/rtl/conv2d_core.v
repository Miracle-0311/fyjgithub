// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : conv2d_core
// -----------------------------------------------------------------------------
//  Description:
//    Parameterizable INT8 convolution core featuring an MxN systolic MAC array
//    with optional im2col front-end. The module consumes AXI-width chunks of
//    activations and weights and produces accumulated INT32 outputs. The
//    implementation is intentionally abstracted but follows the ready/valid
//    protocol to integrate cleanly with the DMA and downstream blocks.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module conv2d_core #(
  parameter integer DATA_WIDTH = 8,
  parameter integer ACC_WIDTH  = 32,
  parameter integer ARRAY_M    = 16,
  parameter integer ARRAY_N    = 16,
  parameter integer AXI_WIDTH  = 128,
  parameter integer USE_IM2COL = 0
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
  output reg                      busy,
  output reg                      done
);

  localparam integer VEC_PER_BEAT = AXI_WIDTH / (DATA_WIDTH * ARRAY_N);
  localparam integer NUM_MAC = ARRAY_M * ARRAY_N;

  // Configuration registers (subset used in behavioural model)
  reg [15:0] ifm_height;
  reg [15:0] ifm_width;
  reg [15:0] ofm_channels;
  reg [15:0] kernel_size;
  reg [7:0]  stride;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      ifm_height  <= 16'd0;
      ifm_width   <= 16'd0;
      ofm_channels<= 16'd0;
      kernel_size <= 16'd3;
      stride      <= 8'd1;
    end else if (cfg_wr_en) begin
      case (cfg_addr)
        6'h10: ifm_height   <= cfg_wdata[15:0];
        6'h11: ifm_width    <= cfg_wdata[15:0];
        6'h12: ofm_channels <= cfg_wdata[15:0];
        6'h13: kernel_size  <= cfg_wdata[7:0];
        6'h14: stride       <= cfg_wdata[7:0];
        default: ;
      endcase
    end
  end

  reg active_q;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      active_q <= 1'b0;
      busy     <= 1'b0;
      done     <= 1'b0;
    end else begin
      done <= 1'b0;
      if (start) begin
        active_q <= 1'b1;
        busy     <= 1'b1;
      end else if (active_q && in_valid && in_ready && in_last) begin
        active_q <= 1'b0;
        busy     <= 1'b0;
        done     <= 1'b1;
      end
    end
  end

  assign in_ready = out_ready || !out_valid;

  // Simple behavioural model: pass-through with ReLU-style accumulation stub
  reg [AXI_WIDTH-1:0] accum_data;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      out_valid <= 1'b0;
      out_data  <= {AXI_WIDTH{1'b0}};
      out_last  <= 1'b0;
      accum_data<= {AXI_WIDTH{1'b0}};
    end else begin
      if (in_valid && in_ready) begin
        accum_data <= in_data; // placeholder for systolic array output
        out_data   <= accum_data;
        out_last   <= in_last;
        out_valid  <= 1'b1;
      end else if (out_valid && out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end

endmodule

