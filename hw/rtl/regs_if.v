// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : regs_if
// -----------------------------------------------------------------------------
//  Description:
//    CSR bridge for commands received from cop_agent. Parses the COP instruction
//    encoding and exposes a simple register file for firmware debugging. The
//    block presents job control signals to the accelerator top.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module regs_if #(
  parameter integer ADDR_WIDTH = 6,
  parameter integer DATA_WIDTH = 64,
  parameter integer ID_WIDTH   = 12
) (
  input  wire                       clk,
  input  wire                       rst_b,
  input  wire                       cmd_valid,
  output reg                        cmd_ready,
  input  wire [4:0]                 cmd_opcode,
  input  wire [7:0]                 cmd_hint,
  input  wire [ID_WIDTH-1:0]        cmd_id,
  input  wire [31:0]                cmd_insn,
  input  wire [255:0]               cmd_data,
  output reg                        csr_wr_en,
  output reg  [ADDR_WIDTH-1:0]      csr_addr,
  output reg  [DATA_WIDTH-1:0]      csr_wdata,
  output reg  [DATA_WIDTH-1:0]      csr_rdata,
  output reg                        csr_ack,
  output reg                        job_start,
  output reg  [2:0]                 job_sel,
  output reg  [ID_WIDTH-1:0]        job_id
);

  localparam [4:0] FUNCT5_CONV = 5'b00101;
  localparam [4:0] FUNCT5_POOL = 5'b00110;
  localparam [4:0] FUNCT5_ACT  = 5'b00111;

  wire [4:0] funct5 = cmd_insn[29:25];
  wire [1:0] funct2 = cmd_insn[14:13];
  wire       validb = cmd_insn[12];

  typedef enum logic [1:0] {
    S_IDLE  = 2'd0,
    S_RESP  = 2'd1
  } state_t;

  state_t state_q, state_d;
  reg [2:0] job_sel_d;
  reg [ID_WIDTH-1:0] job_id_d;
  reg job_start_d;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      state_q   <= S_IDLE;
      cmd_ready <= 1'b1;
      csr_wr_en <= 1'b0;
      csr_addr  <= {ADDR_WIDTH{1'b0}};
      csr_wdata <= {DATA_WIDTH{1'b0}};
      csr_rdata <= {DATA_WIDTH{1'b0}};
      csr_ack   <= 1'b0;
      job_start <= 1'b0;
      job_sel   <= 3'b000;
      job_id    <= {ID_WIDTH{1'b0}};
    end else begin
      state_q   <= state_d;
      job_sel   <= job_sel_d;
      job_id    <= job_id_d;
      job_start <= job_start_d;
      csr_wr_en <= 1'b0;
      csr_ack   <= 1'b0;
      cmd_ready <= (state_d == S_IDLE);
      if (job_start_d) begin
        csr_wr_en <= 1'b1;
        csr_addr  <= cmd_data[ADDR_WIDTH-1:0];
        csr_wdata <= cmd_data[DATA_WIDTH-1:0];
      end
      if (state_d == S_RESP) begin
        csr_ack <= 1'b1;
      end
    end
  end

  always @(*) begin
    state_d     = state_q;
    job_sel_d   = job_sel;
    job_id_d    = job_id;
    job_start_d = 1'b0;

    case (state_q)
      S_IDLE: begin
        if (cmd_valid) begin
          if (validb) begin
            unique case ({funct5, funct2})
              {FUNCT5_CONV, 2'b00}: begin
                job_sel_d   = 3'b001;
                job_id_d    = cmd_id;
                job_start_d = 1'b1;
                state_d     = S_RESP;
              end
              {FUNCT5_POOL, 2'b00}: begin
                job_sel_d   = 3'b010;
                job_id_d    = cmd_id;
                job_start_d = 1'b1;
                state_d     = S_RESP;
              end
              {FUNCT5_ACT, 2'b00}: begin
                job_sel_d   = 3'b100;
                job_id_d    = cmd_id;
                job_start_d = 1'b1;
                state_d     = S_RESP;
              end
              default: begin
                state_d = S_RESP;
              end
            endcase
          end else begin
            state_d = S_RESP;
          end
        end
      end
      S_RESP: begin
        if (!cmd_valid) begin
          state_d = S_IDLE;
        end
      end
      default: state_d = S_IDLE;
    endcase
  end

endmodule
