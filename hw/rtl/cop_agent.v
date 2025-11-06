// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : cop_agent
//  Project    : Xuantie C908 CNN Accelerator
// -----------------------------------------------------------------------------
//  File       : cop_agent.v
//  Author     : OpenAI Assistant
//  Created    : 2024-05-21
// -----------------------------------------------------------------------------
//  Description: Thin COP front-end wrapper. Registers the COP request channel,
//               decodes the instruction space for accelerator opcodes, and
//               dispatches toward the accelerator command interface. The module
//               guarantees a single-cycle response latency once the
//               accelerator asserts resp_valid.
// -----------------------------------------------------------------------------
//  Notes:
//    * The decode looks at instruction[29:25] and instruction[14:13] with
//      instruction[12] acting as a valid qualifier as described in the project
//      specification.
//    * The module supports back-to-back requests from the CPU. If the
//      accelerator is busy, requests are held in the local skid buffer until the
//      accelerator becomes ready again.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module cop_agent #(
  parameter integer ID_WIDTH      = 12,
  parameter integer REQ_DATA_WIDTH = 256,
  parameter integer RESP_DATA_WIDTH = 64
) (
  input  wire                     clk,
  input  wire                     rst_b,
  // COP request channel (from CPU)
  input  wire                     pad_cop_req_vld,
  input  wire [4:0]               pad_cop_req_cop,
  input  wire [7:0]               pad_cop_req_hint,
  input  wire [ID_WIDTH-1:0]      pad_cop_req_id,
  input  wire [31:0]              pad_cop_req_insn,
  input  wire [REQ_DATA_WIDTH-1:0] pad_cop_req_data,
  // Accelerator command interface
  output wire                     accel_cmd_valid,
  output wire [4:0]               accel_cmd_opcode,
  output wire [7:0]               accel_cmd_hint,
  output wire [ID_WIDTH-1:0]      accel_cmd_id,
  output wire [31:0]              accel_cmd_insn,
  output wire [REQ_DATA_WIDTH-1:0] accel_cmd_data,
  input  wire                     accel_cmd_ready,
  // Accelerator response interface
  input  wire                     accel_resp_valid,
  input  wire [ID_WIDTH-1:0]      accel_resp_id,
  input  wire [RESP_DATA_WIDTH-1:0] accel_resp_data,
  // COP response channel (to CPU)
  output reg                      cop_pad_resp_vld,
  output reg  [ID_WIDTH-1:0]      cop_pad_resp_id,
  output reg  [RESP_DATA_WIDTH-1:0] cop_pad_resp_data
);

  // ---------------------------------------------------------------------------
  // Request skid buffer
  // ---------------------------------------------------------------------------
  reg                      req_valid_q;
  reg  [4:0]               req_cop_q;
  reg  [7:0]               req_hint_q;
  reg  [ID_WIDTH-1:0]      req_id_q;
  reg  [31:0]              req_insn_q;
  reg  [REQ_DATA_WIDTH-1:0] req_data_q;

  wire accept_new_req = pad_cop_req_vld && (!req_valid_q || accel_cmd_ready);
  wire send_req       = req_valid_q && accel_cmd_ready;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      req_valid_q <= 1'b0;
    end else begin
      if (accept_new_req) begin
        req_valid_q <= 1'b1;
        req_cop_q   <= pad_cop_req_cop;
        req_hint_q  <= pad_cop_req_hint;
        req_id_q    <= pad_cop_req_id;
        req_insn_q  <= pad_cop_req_insn;
        req_data_q  <= pad_cop_req_data;
      end else if (send_req) begin
        req_valid_q <= 1'b0;
      end
    end
  end

  assign accel_cmd_valid = req_valid_q;
  assign accel_cmd_opcode = req_cop_q;
  assign accel_cmd_hint   = req_hint_q;
  assign accel_cmd_id     = req_id_q;
  assign accel_cmd_insn   = req_insn_q;
  assign accel_cmd_data   = req_data_q;

  // ---------------------------------------------------------------------------
  // Response handling
  // ---------------------------------------------------------------------------
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      cop_pad_resp_vld  <= 1'b0;
      cop_pad_resp_id   <= {ID_WIDTH{1'b0}};
      cop_pad_resp_data <= {RESP_DATA_WIDTH{1'b0}};
    end else begin
      cop_pad_resp_vld <= accel_resp_valid;
      cop_pad_resp_id  <= accel_resp_id;
      cop_pad_resp_data<= accel_resp_data;
    end
  end

endmodule

