// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps

module tb_cnn_accel;
  localparam CLK_PERIOD = 5ns;
  localparam MEM_DEPTH  = 1<<12;

  bit clk;
  bit rst_b;

  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  initial begin
    rst_b = 0;
    repeat (10) @(posedge clk);
    rst_b = 1;
  end

  // COP request/response wires
  logic                     pad_cop_req_vld;
  logic [4:0]               pad_cop_req_cop;
  logic [7:0]               pad_cop_req_hint;
  logic [11:0]              pad_cop_req_id;
  logic [31:0]              pad_cop_req_insn;
  logic [255:0]             pad_cop_req_data;
  logic                     cop_pad_resp_vld;
  logic [11:0]              cop_pad_resp_id;
  logic [63:0]              cop_pad_resp_data;

  // cop_agent to accelerator
  wire cmd_valid;
  wire cmd_ready;
  wire [4:0] cmd_opcode;
  wire [7:0] cmd_hint;
  wire [11:0] cmd_id;
  wire [31:0] cmd_insn;
  wire [255:0] cmd_data;
  wire resp_valid;
  wire [11:0] resp_id;
  wire [63:0] resp_data;

  cop_agent u_cop_agent (
    .clk                (clk),
    .rst_b              (rst_b),
    .pad_cop_req_vld    (pad_cop_req_vld),
    .pad_cop_req_cop    (pad_cop_req_cop),
    .pad_cop_req_hint   (pad_cop_req_hint),
    .pad_cop_req_id     (pad_cop_req_id),
    .pad_cop_req_insn   (pad_cop_req_insn),
    .pad_cop_req_data   (pad_cop_req_data),
    .accel_cmd_valid    (cmd_valid),
    .accel_cmd_opcode   (cmd_opcode),
    .accel_cmd_hint     (cmd_hint),
    .accel_cmd_id       (cmd_id),
    .accel_cmd_insn     (cmd_insn),
    .accel_cmd_data     (cmd_data),
    .accel_cmd_ready    (cmd_ready),
    .accel_resp_valid   (resp_valid),
    .accel_resp_id      (resp_id),
    .accel_resp_data    (resp_data),
    .cop_pad_resp_vld   (cop_pad_resp_vld),
    .cop_pad_resp_id    (cop_pad_resp_id),
    .cop_pad_resp_data  (cop_pad_resp_data)
  );

  // AXI master wires
  wire [47:0] m_axi_araddr;
  wire [7:0]  m_axi_arlen;
  wire [2:0]  m_axi_arsize;
  wire [1:0]  m_axi_arburst;
  wire        m_axi_arvalid;
  logic       m_axi_arready;
  logic [127:0] m_axi_rdata;
  logic        m_axi_rlast;
  logic        m_axi_rvalid;
  wire         m_axi_rready;

  wire [47:0] m_axi_awaddr;
  wire [7:0]  m_axi_awlen;
  wire [2:0]  m_axi_awsize;
  wire [1:0]  m_axi_awburst;
  wire        m_axi_awvalid;
  logic       m_axi_awready;
  wire [127:0] m_axi_wdata;
  wire [15:0]  m_axi_wstrb;
  wire         m_axi_wlast;
  wire         m_axi_wvalid;
  logic        m_axi_wready;
  logic [1:0]  m_axi_bresp;
  logic        m_axi_bvalid;
  wire         m_axi_bready;

  cnn_accel_top u_cnn_accel (
    .clk              (clk),
    .rst_b            (rst_b),
    .cmd_valid        (cmd_valid),
    .cmd_ready        (cmd_ready),
    .cmd_opcode       (cmd_opcode),
    .cmd_hint         (cmd_hint),
    .cmd_id           (cmd_id),
    .cmd_insn         (cmd_insn),
    .cmd_data         (cmd_data),
    .resp_valid       (resp_valid),
    .resp_id          (resp_id),
    .resp_data        (resp_data),
    .resp_ready       (1'b1),
    .m_axi_araddr     (m_axi_araddr),
    .m_axi_arlen      (m_axi_arlen),
    .m_axi_arsize     (m_axi_arsize),
    .m_axi_arburst    (m_axi_arburst),
    .m_axi_arvalid    (m_axi_arvalid),
    .m_axi_arready    (m_axi_arready),
    .m_axi_rdata      (m_axi_rdata),
    .m_axi_rlast      (m_axi_rlast),
    .m_axi_rvalid     (m_axi_rvalid),
    .m_axi_rready     (m_axi_rready),
    .m_axi_awaddr     (m_axi_awaddr),
    .m_axi_awlen      (m_axi_awlen),
    .m_axi_awsize     (m_axi_awsize),
    .m_axi_awburst    (m_axi_awburst),
    .m_axi_awvalid    (m_axi_awvalid),
    .m_axi_awready    (m_axi_awready),
    .m_axi_wdata      (m_axi_wdata),
    .m_axi_wstrb      (m_axi_wstrb),
    .m_axi_wlast      (m_axi_wlast),
    .m_axi_wvalid     (m_axi_wvalid),
    .m_axi_wready     (m_axi_wready),
    .m_axi_bresp      (m_axi_bresp),
    .m_axi_bvalid     (m_axi_bvalid),
    .m_axi_bready     (m_axi_bready)
  );

  // Simple AXI memory model
  logic [127:0] mem [0:MEM_DEPTH-1];
  integer ridx;

  initial begin
    for (ridx = 0; ridx < MEM_DEPTH; ridx++) begin
      mem[ridx] = '0;
    end
    $readmemh("img_32x32_rgb.mem", mem, 0, 1023);
    $readmemh("weights_conv3x3_ch16.mem", mem, 1024, 2047);
  end

  typedef enum logic [1:0] {READ_IDLE, READ_BURST} read_state_t;
  read_state_t read_state;
  int unsigned read_count;
  int unsigned read_addr;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      read_state <= READ_IDLE;
      m_axi_arready <= 1'b0;
      m_axi_rvalid  <= 1'b0;
      m_axi_rlast   <= 1'b0;
      m_axi_rdata   <= '0;
      read_count    <= 0;
      read_addr     <= 0;
    end else begin
      m_axi_arready <= 1'b1;
      m_axi_rlast   <= 1'b0;
      if (m_axi_arvalid && m_axi_arready) begin
        read_state <= READ_BURST;
        read_addr  <= m_axi_araddr[11:4];
        read_count <= m_axi_arlen + 1;
      end
      if (read_state == READ_BURST) begin
        if (m_axi_rready || !m_axi_rvalid) begin
          m_axi_rvalid <= 1'b1;
          m_axi_rdata  <= mem[read_addr];
          read_addr    <= read_addr + 1;
          read_count   <= read_count - 1;
          if (read_count == 1) begin
            m_axi_rlast <= 1'b1;
            read_state  <= READ_IDLE;
          end
        end
      end else begin
        m_axi_rvalid <= 1'b0;
      end
    end
  end

  typedef enum logic [1:0] {WRITE_IDLE, WRITE_BURST} write_state_t;
  write_state_t write_state;
  int unsigned write_addr;

  always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
      write_state  <= WRITE_IDLE;
      m_axi_awready<= 1'b0;
      m_axi_wready <= 1'b0;
      m_axi_bvalid <= 1'b0;
      m_axi_bresp  <= 2'b00;
      write_addr   <= 0;
    end else begin
      m_axi_awready <= 1'b1;
      m_axi_bvalid  <= 1'b0;
      case (write_state)
        WRITE_IDLE: begin
          if (m_axi_awvalid && m_axi_awready) begin
            write_state <= WRITE_BURST;
            write_addr  <= m_axi_awaddr[11:4];
            m_axi_wready<= 1'b1;
          end
        end
        WRITE_BURST: begin
          if (m_axi_wvalid && m_axi_wready) begin
            mem[write_addr] <= m_axi_wdata;
            write_addr      <= write_addr + 1;
            if (m_axi_wlast) begin
              write_state  <= WRITE_IDLE;
              m_axi_wready <= 1'b0;
              m_axi_bvalid <= 1'b1;
            end
          end
        end
      endcase
    end
  end

  // Stimulus
  initial begin
    pad_cop_req_vld  = 0;
    pad_cop_req_cop  = 5'd0;
    pad_cop_req_hint = 8'd0;
    pad_cop_req_id   = 12'h001;
    pad_cop_req_insn = 32'b0101011_00101_00000_000_00000_0000000;
    pad_cop_req_data = '0;

    @(posedge rst_b);
    repeat (5) @(posedge clk);

    pad_cop_req_vld = 1'b1;
    @(posedge clk);
    pad_cop_req_vld = 1'b0;

    wait (cop_pad_resp_vld);
    $display("Response ID %0d data %0h", cop_pad_resp_id, cop_pad_resp_data);
    #100ns;
    $finish;
  end

endmodule
