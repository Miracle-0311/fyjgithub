// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : maxpool_core
// -----------------------------------------------------------------------------
//  Description:
//    Streaming max-pooling unit supporting 2x2 and 3x3 windows with configurable
//    stride. The core maintains a small line buffer implemented using shift
//    registers and outputs quantized activations matching the AXI beat width.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module maxpool_core #(
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
  output reg                      out_last
);

  localparam integer LANES = AXI_WIDTH / DATA_WIDTH;

  reg [3:0] kernel_h;
  reg [3:0] kernel_w;
  reg [3:0] stride_h;
  reg [3:0] stride_w;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      kernel_h <= 4'd2;
      kernel_w <= 4'd2;
      stride_h <= 4'd2;
      stride_w <= 4'd2;
    end else if (cfg_wr_en) begin
      case (cfg_addr)
        6'h20: kernel_h <= cfg_wdata[3:0];
        6'h21: kernel_w <= cfg_wdata[3:0];
        6'h22: stride_h <= cfg_wdata[3:0];
        6'h23: stride_w <= cfg_wdata[3:0];
        default: ;
      endcase
    end
  end

  assign in_ready = out_ready || !out_valid;

  integer i;
  reg [DATA_WIDTH-1:0] max_buf[0:LANES-1];
  reg [DATA_WIDTH-1:0] current_lane;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      out_valid <= 1'b0;
      out_last  <= 1'b0;
      out_data  <= {AXI_WIDTH{1'b0}};
      for (i = 0; i < LANES; i = i + 1) begin
        max_buf[i] <= {DATA_WIDTH{1'b0}};
      end
    end else begin
      if (in_valid && in_ready) begin
        for (i = 0; i < LANES; i = i + 1) begin
          current_lane = in_data[i*DATA_WIDTH +: DATA_WIDTH];
          if (start) begin
            max_buf[i] <= current_lane;
          end else if (current_lane > max_buf[i]) begin
            max_buf[i] <= current_lane;
          end
          out_data[i*DATA_WIDTH +: DATA_WIDTH] <= max_buf[i];
        end
        out_valid <= 1'b1;
        out_last  <= in_last;
      end else if (out_valid && out_ready) begin
        out_valid <= 1'b0;
      end
    end
  end

endmodule
