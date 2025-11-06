// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
//  Title      : axi_dma
// -----------------------------------------------------------------------------
//  Description:
//    Lightweight AXI4 DMA engine optimized for 128-bit data path. Supports
//    burst-aligned reads and writes with configurable outstanding requests.
//    The engine exposes streaming source/sink interfaces to the compute
//    pipeline using ready/valid. A small command CSR bank configures source,
//    destination, stride, and transfer length parameters.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module axi_dma #(
  parameter integer ADDR_WIDTH = 48,
  parameter integer DATA_WIDTH = 128,
  parameter integer OUTSTANDING_RD = 4,
  parameter integer LEN_WIDTH = 24
) (
  input  wire                     clk,
  input  wire                     rst_b,
  // CSR interface
  input  wire                     csr_wr_en,
  input  wire [5:0]               csr_addr,
  input  wire [63:0]              csr_wdata,
  output reg  [63:0]              csr_rdata,
  input  wire                     start,
  output reg                      busy,
  output reg                      done,
  // Streaming read interface (to compute engine)
  output reg                      rd_valid,
  input  wire                     rd_ready,
  output reg  [DATA_WIDTH-1:0]    rd_data,
  output reg                      rd_last,
  // Streaming write interface (from compute engine)
  input  wire                     wr_valid,
  output wire                     wr_ready,
  input  wire [DATA_WIDTH-1:0]    wr_data,
  input  wire                     wr_last,
  // AXI Read Address Channel
  output reg  [ADDR_WIDTH-1:0]    m_axi_araddr,
  output reg  [7:0]               m_axi_arlen,
  output reg  [2:0]               m_axi_arsize,
  output reg  [1:0]               m_axi_arburst,
  output reg                      m_axi_arvalid,
  input  wire                     m_axi_arready,
  // AXI Read Data Channel
  input  wire [DATA_WIDTH-1:0]    m_axi_rdata,
  input  wire                     m_axi_rlast,
  input  wire                     m_axi_rvalid,
  output wire                     m_axi_rready,
  // AXI Write Address Channel
  output reg  [ADDR_WIDTH-1:0]    m_axi_awaddr,
  output reg  [7:0]               m_axi_awlen,
  output reg  [2:0]               m_axi_awsize,
  output reg  [1:0]               m_axi_awburst,
  output reg                      m_axi_awvalid,
  input  wire                     m_axi_awready,
  // AXI Write Data Channel
  output wire [DATA_WIDTH-1:0]    m_axi_wdata,
  output wire [(DATA_WIDTH/8)-1:0] m_axi_wstrb,
  output wire                     m_axi_wlast,
  output wire                     m_axi_wvalid,
  input  wire                     m_axi_wready,
  // AXI Write Response
  input  wire [1:0]               m_axi_bresp,
  input  wire                     m_axi_bvalid,
  output wire                     m_axi_bready
);

  localparam integer BYTES_PER_BEAT = DATA_WIDTH/8;

  // ---------------------------------------------------------------------------
  // Configuration registers
  // ---------------------------------------------------------------------------
  reg [ADDR_WIDTH-1:0] src_base;
  reg [ADDR_WIDTH-1:0] dst_base;
  reg [LEN_WIDTH-1:0]  transfer_len; // in beats
  reg [7:0]            burst_len;    // beats per burst - 1
  reg                  auto_restart;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      src_base      <= {ADDR_WIDTH{1'b0}};
      dst_base      <= {ADDR_WIDTH{1'b0}};
      transfer_len  <= {LEN_WIDTH{1'b0}};
      burst_len     <= 8'd15; // default 16-beat bursts
      auto_restart  <= 1'b0;
    end else if (csr_wr_en) begin
      case (csr_addr)
        6'h00: src_base     <= csr_wdata[ADDR_WIDTH-1:0];
        6'h01: dst_base     <= csr_wdata[ADDR_WIDTH-1:0];
        6'h02: transfer_len <= csr_wdata[LEN_WIDTH-1:0];
        6'h03: burst_len    <= csr_wdata[7:0];
        6'h04: auto_restart <= csr_wdata[0];
        default: ;
      endcase
    end
  end

  // readback (for debug)
  always @(*) begin
    case (csr_addr)
      6'h00: csr_rdata = {{(64-ADDR_WIDTH){1'b0}}, src_base};
      6'h01: csr_rdata = {{(64-ADDR_WIDTH){1'b0}}, dst_base};
      6'h02: csr_rdata = {{(64-LEN_WIDTH){1'b0}}, transfer_len};
      6'h03: csr_rdata = {{56{1'b0}}, burst_len};
      6'h04: csr_rdata = {63'd0, auto_restart};
      default: csr_rdata = 64'd0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Control FSM
  // ---------------------------------------------------------------------------
  localparam IDLE  = 2'd0;
  localparam READ  = 2'd1;
  localparam WRITE = 2'd2;
  localparam RESP  = 2'd3;

  reg [1:0] state_q, state_d;
  reg [LEN_WIDTH-1:0] beats_remaining_q, beats_remaining_d;
  reg [ADDR_WIDTH-1:0] rd_addr_q, rd_addr_d;
  reg [ADDR_WIDTH-1:0] wr_addr_q, wr_addr_d;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      state_q           <= IDLE;
      beats_remaining_q <= {LEN_WIDTH{1'b0}};
      rd_addr_q         <= {ADDR_WIDTH{1'b0}};
      wr_addr_q         <= {ADDR_WIDTH{1'b0}};
      busy              <= 1'b0;
      done              <= 1'b0;
    end else begin
      state_q           <= state_d;
      beats_remaining_q <= beats_remaining_d;
      rd_addr_q         <= rd_addr_d;
      wr_addr_q         <= wr_addr_d;
      busy              <= (state_d != IDLE);
      done              <= (state_q != IDLE) && (state_d == IDLE);
    end
  end

  always @(*) begin
    state_d           = state_q;
    beats_remaining_d = beats_remaining_q;
    rd_addr_d         = rd_addr_q;
    wr_addr_d         = wr_addr_q;

    case (state_q)
      IDLE: begin
        if (start) begin
          state_d           = READ;
          beats_remaining_d = transfer_len;
          rd_addr_d         = src_base;
          wr_addr_d         = dst_base;
        end
      end
      READ: begin
        if (beats_remaining_q == 0) begin
          state_d = WRITE;
        end
      end
      WRITE: begin
        if (beats_remaining_q == 0) begin
          state_d = RESP;
        end
      end
      RESP: begin
        if (!auto_restart) begin
          state_d = IDLE;
        end else begin
          state_d = READ;
          beats_remaining_d = transfer_len;
          rd_addr_d = src_base;
          wr_addr_d = dst_base;
        end
      end
    endcase
  end

  // ---------------------------------------------------------------------------
  // AXI read channel (simple linear burst generator)
  // ---------------------------------------------------------------------------
  reg [LEN_WIDTH-1:0] outstanding_rd;
  wire issue_read = (state_q == READ) && (beats_remaining_q != 0) &&
                    (outstanding_rd < OUTSTANDING_RD) && !m_axi_arvalid;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      m_axi_arvalid   <= 1'b0;
      m_axi_araddr    <= {ADDR_WIDTH{1'b0}};
      m_axi_arlen     <= 8'd0;
      m_axi_arsize    <= $clog2(BYTES_PER_BEAT);
      m_axi_arburst   <= 2'b01; // INCR
      outstanding_rd  <= {LEN_WIDTH{1'b0}};
    end else begin
      if (m_axi_arvalid && m_axi_arready) begin
        m_axi_arvalid <= 1'b0;
      end
      if (issue_read) begin
        m_axi_arvalid  <= 1'b1;
        m_axi_araddr   <= rd_addr_q;
        m_axi_arlen    <= burst_len;
        rd_addr_d      <= rd_addr_q + BYTES_PER_BEAT * (burst_len + 1);
        beats_remaining_d = beats_remaining_q - (burst_len + 1);
        outstanding_rd <= outstanding_rd + (burst_len + 1);
      end
      if (m_axi_rvalid && m_axi_rready) begin
        outstanding_rd <= outstanding_rd - 1;
      end
    end
  end

  assign m_axi_rready = (state_q == READ) ? rd_ready : 1'b0;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      rd_valid <= 1'b0;
      rd_data  <= {DATA_WIDTH{1'b0}};
      rd_last  <= 1'b0;
    end else begin
      if (m_axi_rvalid && m_axi_rready) begin
        rd_valid <= 1'b1;
        rd_data  <= m_axi_rdata;
        rd_last  <= m_axi_rlast;
      end else if (rd_valid && rd_ready) begin
        rd_valid <= 1'b0;
        rd_last  <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // AXI write channel
  // ---------------------------------------------------------------------------
  assign m_axi_wdata = wr_data;
  assign m_axi_wstrb = {(DATA_WIDTH/8){1'b1}};
  assign m_axi_wlast = wr_last;
  assign m_axi_wvalid= wr_valid;
  assign wr_ready    = (state_q == WRITE) ? m_axi_wready : 1'b0;

  reg write_active;
  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      m_axi_awvalid <= 1'b0;
      m_axi_awaddr  <= {ADDR_WIDTH{1'b0}};
      m_axi_awlen   <= 8'd0;
      m_axi_awsize  <= $clog2(BYTES_PER_BEAT);
      m_axi_awburst <= 2'b01;
      write_active  <= 1'b0;
    end else begin
      if (state_q == WRITE && !write_active) begin
        m_axi_awvalid <= 1'b1;
        m_axi_awaddr  <= wr_addr_q;
        m_axi_awlen   <= burst_len;
        write_active  <= 1'b1;
      end else if (m_axi_awvalid && m_axi_awready) begin
        m_axi_awvalid <= 1'b0;
      end
      if (wr_valid && wr_ready && wr_last) begin
        write_active <= 1'b0;
      end
    end
  end

  assign m_axi_bready = 1'b1;

endmodule

