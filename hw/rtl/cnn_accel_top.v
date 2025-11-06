// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : cnn_accel_top
//  Project    : Xuantie C908 CNN Accelerator
// -----------------------------------------------------------------------------
//  Description:
//    Top level block for the CNN accelerator. Implements command decoding,
//    CSR bank, and control FSM that sequences the compute pipeline. AXI DMA
//    masters provide data movement, and sub-cores perform convolution,
//    pooling, activation, and quantization. All interfaces use ready/valid
//    semantics to simplify integration and timing closure.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module cnn_accel_top #(
  parameter integer ID_WIDTH = 12,
  parameter integer ADDR_WIDTH = 48,
  parameter integer AXI_DATA_WIDTH = 128,
  parameter integer CMD_DATA_WIDTH = 256,
  parameter integer RESP_DATA_WIDTH = 64,
  parameter integer MAX_CHANNELS = 64,
  parameter integer TILE_SIZE = 256,
  parameter integer USE_IM2COL = 0
) (
  input  wire                        clk,
  input  wire                        rst_b,
  // command channel from cop_agent
  input  wire                        cmd_valid,
  output wire                        cmd_ready,
  input  wire [4:0]                  cmd_opcode,
  input  wire [7:0]                  cmd_hint,
  input  wire [ID_WIDTH-1:0]         cmd_id,
  input  wire [31:0]                 cmd_insn,
  input  wire [CMD_DATA_WIDTH-1:0]   cmd_data,
  // response channel to cop_agent
  output reg                         resp_valid,
  output reg  [ID_WIDTH-1:0]         resp_id,
  output reg  [RESP_DATA_WIDTH-1:0]  resp_data,
  input  wire                        resp_ready,
  // AXI master interface for DMA reads and writes
  output wire [ADDR_WIDTH-1:0]       m_axi_araddr,
  output wire [7:0]                  m_axi_arlen,
  output wire [2:0]                  m_axi_arsize,
  output wire [1:0]                  m_axi_arburst,
  output wire                        m_axi_arvalid,
  input  wire                        m_axi_arready,
  input  wire [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
  input  wire                        m_axi_rlast,
  input  wire                        m_axi_rvalid,
  output wire                        m_axi_rready,

  output wire [ADDR_WIDTH-1:0]       m_axi_awaddr,
  output wire [7:0]                  m_axi_awlen,
  output wire [2:0]                  m_axi_awsize,
  output wire [1:0]                  m_axi_awburst,
  output wire                        m_axi_awvalid,
  input  wire                        m_axi_awready,
  output wire [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
  output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
  output wire                        m_axi_wlast,
  output wire                        m_axi_wvalid,
  input  wire                        m_axi_wready,
  input  wire [1:0]                  m_axi_bresp,
  input  wire                        m_axi_bvalid,
  output wire                        m_axi_bready
);

  localparam OPCODE_CONV  = 3'b000;
  localparam OPCODE_POOL  = 3'b001;
  localparam OPCODE_ACT   = 3'b010;

  // ---------------------------------------------------------------------------
  // CSR window - registers describing the current job
  // ---------------------------------------------------------------------------
  localparam CSR_ADDR_WIDTH = 6;
  localparam CSR_DATA_WIDTH = 64;

  wire                     csr_wr_en;
  wire [CSR_ADDR_WIDTH-1:0]csr_addr;
  wire [CSR_DATA_WIDTH-1:0]csr_wdata;
  wire [CSR_DATA_WIDTH-1:0]csr_rdata;

  regs_if #(
    .ADDR_WIDTH (CSR_ADDR_WIDTH),
    .DATA_WIDTH (CSR_DATA_WIDTH)
  ) u_regs_if (
    .clk       (clk),
    .rst_b     (rst_b),
    .cmd_valid (cmd_valid),
    .cmd_ready (cmd_ready),
    .cmd_opcode(cmd_opcode),
    .cmd_hint  (cmd_hint),
    .cmd_id    (cmd_id),
    .cmd_insn  (cmd_insn),
    .cmd_data  (cmd_data),
    .csr_wr_en (csr_wr_en),
    .csr_addr  (csr_addr),
    .csr_wdata (csr_wdata),
    .csr_rdata (csr_rdata),
    .csr_ack   (),
    .job_start (job_start),
    .job_sel   (job_sel),
    .job_id    (job_id)
  );

  // job_select = {conv, pool, act}
  reg [2:0] job_sel_q;
  reg [ID_WIDTH-1:0] job_id_q;
  reg job_active_q;
  reg job_done_q;

  wire job_start;
  wire [2:0] job_sel;
  wire [ID_WIDTH-1:0] job_id;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      job_sel_q    <= 3'b000;
      job_id_q     <= {ID_WIDTH{1'b0}};
      job_active_q <= 1'b0;
      job_done_q   <= 1'b0;
    end else begin
      job_done_q <= 1'b0;
      if (job_start) begin
        job_sel_q    <= job_sel;
        job_id_q     <= job_id;
        job_active_q <= 1'b1;
      end else if (job_complete) begin
        job_active_q <= 1'b0;
        job_done_q   <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Data path modules
  // ---------------------------------------------------------------------------
  wire                     dma_rd_valid;
  wire                     dma_busy;
  wire                     dma_done;
  wire                     dma_rd_ready;
  wire [AXI_DATA_WIDTH-1:0]dma_rd_data;
  wire                     dma_rd_last;

  wire                     dma_wr_valid;
  wire                     dma_wr_ready;
  wire [AXI_DATA_WIDTH-1:0]dma_wr_data;
  wire                     dma_wr_last;

  axi_dma #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (AXI_DATA_WIDTH),
    .OUTSTANDING_RD (4)
  ) u_axi_dma (
    .clk           (clk),
    .rst_b         (rst_b),
    // configuration from CSRs
    .csr_wr_en     (csr_wr_en),
    .csr_addr      (csr_addr),
    .csr_wdata     (csr_wdata),
    .csr_rdata     (),
    .start         (job_start),
    .busy          (dma_busy),
    .done          (dma_done),
    // streaming interface to compute engines
    .rd_valid      (dma_rd_valid),
    .rd_ready      (dma_rd_ready),
    .rd_data       (dma_rd_data),
    .rd_last       (dma_rd_last),
    .wr_valid      (dma_wr_valid),
    .wr_ready      (dma_wr_ready),
    .wr_data       (dma_wr_data),
    .wr_last       (dma_wr_last),
    // AXI master
    .m_axi_araddr  (m_axi_araddr),
    .m_axi_arlen   (m_axi_arlen),
    .m_axi_arsize  (m_axi_arsize),
    .m_axi_arburst (m_axi_arburst),
    .m_axi_arvalid (m_axi_arvalid),
    .m_axi_arready (m_axi_arready),
    .m_axi_rdata   (m_axi_rdata),
    .m_axi_rlast   (m_axi_rlast),
    .m_axi_rvalid  (m_axi_rvalid),
    .m_axi_rready  (m_axi_rready),
    .m_axi_awaddr  (m_axi_awaddr),
    .m_axi_awlen   (m_axi_awlen),
    .m_axi_awsize  (m_axi_awsize),
    .m_axi_awburst (m_axi_awburst),
    .m_axi_awvalid (m_axi_awvalid),
    .m_axi_awready (m_axi_awready),
    .m_axi_wdata   (m_axi_wdata),
    .m_axi_wstrb   (m_axi_wstrb),
    .m_axi_wlast   (m_axi_wlast),
    .m_axi_wvalid  (m_axi_wvalid),
    .m_axi_wready  (m_axi_wready),
    .m_axi_bresp   (m_axi_bresp),
    .m_axi_bvalid  (m_axi_bvalid),
    .m_axi_bready  (m_axi_bready)
  );

  // Convolution core
  wire                    conv_valid;
  wire                    conv_ready;
  wire [AXI_DATA_WIDTH-1:0] conv_data;
  wire                    conv_last;

  wire                    conv_busy;
  wire                    conv_done;

  conv2d_core #(
    .DATA_WIDTH    (8),
    .ACC_WIDTH     (32),
    .ARRAY_M       (16),
    .ARRAY_N       (16),
    .USE_IM2COL    (USE_IM2COL)
  ) u_conv2d_core (
    .clk           (clk),
    .rst_b         (rst_b),
    .start         (job_start && job_sel[OPCODE_CONV]),
    .cfg_addr      (csr_addr),
    .cfg_wdata     (csr_wdata),
    .cfg_wr_en     (csr_wr_en),
    .in_valid      (dma_rd_valid),
    .in_ready      (dma_rd_ready),
    .in_data       (dma_rd_data),
    .in_last       (dma_rd_last),
    .out_valid     (conv_valid),
    .out_ready     (conv_ready),
    .out_data      (conv_data),
    .out_last      (conv_last),
    .busy          (conv_busy),
    .done          (conv_done)
  );

  // Quantization block
  wire                    quant_valid;
  wire                    quant_ready;
  wire [AXI_DATA_WIDTH-1:0] quant_data;
  wire                    quant_last;

  quant_block #(
    .DATA_WIDTH (8),
    .ACC_WIDTH  (32),
    .AXI_WIDTH  (AXI_DATA_WIDTH)
  ) u_quant_block (
    .clk       (clk),
    .rst_b     (rst_b),
    .cfg_wr_en (csr_wr_en),
    .cfg_addr  (csr_addr),
    .cfg_wdata (csr_wdata),
    .in_valid  (conv_valid),
    .in_ready  (conv_ready),
    .in_data   (conv_data),
    .in_last   (conv_last),
    .out_valid (quant_valid),
    .out_ready (quant_ready),
    .out_data  (quant_data),
    .out_last  (quant_last)
  );

  // Max pooling core
  wire                    pool_valid;
  wire                    pool_ready;
  wire [AXI_DATA_WIDTH-1:0] pool_data;
  wire                    pool_last;

  maxpool_core #(
    .DATA_WIDTH (8),
    .AXI_WIDTH  (AXI_DATA_WIDTH)
  ) u_maxpool_core (
    .clk       (clk),
    .rst_b     (rst_b),
    .start     (job_start && job_sel[OPCODE_POOL]),
    .cfg_wr_en (csr_wr_en),
    .cfg_addr  (csr_addr),
    .cfg_wdata (csr_wdata),
    .in_valid  (quant_valid),
    .in_ready  (quant_ready),
    .in_data   (quant_data),
    .in_last   (quant_last),
    .out_valid (pool_valid),
    .out_ready (pool_ready),
    .out_data  (pool_data),
    .out_last  (pool_last)
  );

  // Activation core
  wire                    act_valid;
  wire [AXI_DATA_WIDTH-1:0] act_data;
  wire                    act_last;

  wire                    act_done;

  act_core #(
    .DATA_WIDTH (8),
    .AXI_WIDTH  (AXI_DATA_WIDTH)
  ) u_act_core (
    .clk        (clk),
    .rst_b      (rst_b),
    .start      (job_start && job_sel[OPCODE_ACT]),
    .cfg_wr_en  (csr_wr_en),
    .cfg_addr   (csr_addr),
    .cfg_wdata  (csr_wdata),
    .in_valid   (pool_valid),
    .in_ready   (pool_ready),
    .in_data    (pool_data),
    .in_last    (pool_last),
    .out_valid  (act_valid),
    .out_ready  (dma_wr_ready),
    .out_data   (act_data),
    .out_last   (act_last),
    .done       (act_done)
  );

  assign dma_wr_valid = act_valid;
  assign dma_wr_data  = act_data;
  assign dma_wr_last  = act_last;

  // ---------------------------------------------------------------------------
  // Job completion tracking
  // ---------------------------------------------------------------------------
  wire job_complete = (job_sel_q[OPCODE_CONV] && conv_done) |
                      (job_sel_q[OPCODE_POOL] && pool_done) |
                      (job_sel_q[OPCODE_ACT]  && act_done);

  // Done flags from individual engines
  wire pool_done;
  wire act_done;

  assign pool_done = pool_last && pool_valid && pool_ready;
  assign act_done  = act_last  && act_valid  && dma_wr_ready;

  // Response generation
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      resp_valid <= 1'b0;
      resp_id    <= {ID_WIDTH{1'b0}};
      resp_data  <= {RESP_DATA_WIDTH{1'b0}};
    end else begin
      if (resp_ready) begin
        resp_valid <= 1'b0;
      end
      if (job_done_q) begin
        resp_valid <= 1'b1;
        resp_id    <= job_id_q;
        resp_data  <= {RESP_DATA_WIDTH{1'b0}};
      end
    end
  end

endmodule

