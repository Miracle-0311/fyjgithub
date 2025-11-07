// COP agent for CNN accelerator. Handles instruction decode, buffering and
// instantiates the cnn_accel_top.
module cop_agent_cnn
#(
    parameter ID_WIDTH = 12,
    parameter FIFO_DEPTH = 16
)(
    input                     clk,
    input                     rst_b,
    // COP request channel
    output                    cop_pad_req_rdy,
    input                     pad_cop_req_vld,
    input      [4:0]          pad_cop_req_cop,
    input      [7:0]          pad_cop_req_hint,
    input      [ID_WIDTH-1:0] pad_cop_req_id,
    input      [31:0]         pad_cop_req_insn,
    input      [255:0]        pad_cop_req_data,
    input                     pad_cop_resp_rdy,
    // COP response channel
    output reg [63:0]         cop_pad_resp_data,
    output reg                cop_pad_resp_vld,
    output reg [ID_WIDTH-1:0] cop_pad_resp_id
);

    assign cop_pad_req_rdy = 1'b1;

    localparam OP_LOADW = 4'h1;
    localparam OP_LOADI = 4'h2;
    localparam OP_START = 4'h3;
    localparam OP_READO = 4'h4;
    localparam OP_STAT  = 4'h5;

    // Request pipeline (two stages)
    reg                     req_vld_ff1;
    reg                     req_vld_ff2;
    reg [ID_WIDTH-1:0]      req_id_ff1;
    reg [ID_WIDTH-1:0]      req_id_ff2;
    reg [31:0]              req_insn_ff1;
    reg [31:0]              req_insn_ff2;
    reg [255:0]             req_data_ff1;
    reg [255:0]             req_data_ff2;

    wire pop_fifo;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            req_vld_ff1 <= 1'b0;
            req_vld_ff2 <= 1'b0;
            req_id_ff1 <= {ID_WIDTH{1'b0}};
            req_id_ff2 <= {ID_WIDTH{1'b0}};
            req_insn_ff1 <= 32'h0;
            req_insn_ff2 <= 32'h0;
            req_data_ff1 <= 256'h0;
            req_data_ff2 <= 256'h0;
        end else begin
            req_vld_ff1 <= pad_cop_req_vld;
            req_id_ff1 <= pad_cop_req_id;
            req_insn_ff1 <= pad_cop_req_insn;
            req_data_ff1 <= pad_cop_req_data;
            req_vld_ff2 <= req_vld_ff1;
            req_id_ff2 <= req_id_ff1;
            req_insn_ff2 <= req_insn_ff1;
            req_data_ff2 <= req_data_ff1;
        end
    end

    wire decode_valid = req_vld_ff2;
    wire [3:0] opcode = req_insn_ff2[31:28];

    // FIFO for load commands
    reg [255:0] fifo_data   [0:FIFO_DEPTH-1];
    reg [11:0]  fifo_addr   [0:FIFO_DEPTH-1];
    reg         fifo_is_ifm [0:FIFO_DEPTH-1];
    reg [4:0]   fifo_wr_ptr;
    reg [4:0]   fifo_rd_ptr;
    reg [4:0]   fifo_count;

    wire fifo_full  = (fifo_count == FIFO_DEPTH);
    wire fifo_empty = (fifo_count == 0);

    wire push_fifo = decode_valid && ((opcode == OP_LOADW) || (opcode == OP_LOADI)) && !fifo_full;
    wire fifo_type = (opcode == OP_LOADI);

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            fifo_wr_ptr <= 5'h0;
            fifo_rd_ptr <= 5'h0;
            fifo_count  <= 5'h0;
        end else begin
            if (push_fifo) begin
                fifo_data[fifo_wr_ptr[3:0]] <= req_data_ff2;
                fifo_addr[fifo_wr_ptr[3:0]] <= req_insn_ff2[27:16];
                fifo_is_ifm[fifo_wr_ptr[3:0]] <= fifo_type;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
                fifo_count <= fifo_count + 1'b1;
            end
            if (pop_fifo) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
                fifo_count <= fifo_count - 1'b1;
            end
        end
    end

    wire fifo_head_type = fifo_is_ifm[fifo_rd_ptr[3:0]];

    // Start command registers
    reg        start_pulse;
    reg [7:0]  start_width_reg;
    reg [7:0]  start_height_reg;
    reg [3:0]  start_in_ch_reg;
    reg [3:0]  start_out_ch_reg;
    reg [3:0]  start_stride_reg;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            start_pulse <= 1'b0;
            start_width_reg <= 8'h0;
            start_height_reg <= 8'h0;
            start_in_ch_reg <= 4'h0;
            start_out_ch_reg <= 4'h0;
            start_stride_reg <= 4'h1;
        end else begin
            start_pulse <= 1'b0;
            if (decode_valid && (opcode == OP_START)) begin
                start_pulse <= 1'b1;
                start_width_reg <= req_insn_ff2[27:20];
                start_height_reg <= req_insn_ff2[19:12];
                start_in_ch_reg <= req_insn_ff2[11:8];
                start_out_ch_reg <= req_insn_ff2[7:4];
                start_stride_reg <= req_insn_ff2[3:0];
            end
        end
    end

    // Status response handling
    reg stat_valid_reg;
    reg [ID_WIDTH-1:0] stat_resp_id;
    wire stat_fire = stat_valid_reg && pad_cop_resp_rdy;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            stat_valid_reg <= 1'b0;
            stat_resp_id <= {ID_WIDTH{1'b0}};
        end else begin
            if (!stat_valid_reg && decode_valid && (opcode == OP_STAT)) begin
                stat_valid_reg <= 1'b1;
                stat_resp_id <= req_id_ff2;
            end else if (stat_fire) begin
                stat_valid_reg <= 1'b0;
            end
        end
    end

    // Read response handling
    reg read_pending;
    reg [ID_WIDTH-1:0] read_resp_id_reg;
    reg [11:0]         read_addr_reg;
    reg                read_req_pulse;
    reg                read_valid_reg;
    reg [63:0]         read_data_reg;
    wire read_fire = read_valid_reg && pad_cop_resp_rdy && !stat_valid_reg;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            read_pending <= 1'b0;
            read_resp_id_reg <= {ID_WIDTH{1'b0}};
            read_addr_reg <= 12'h0;
            read_req_pulse <= 1'b0;
            read_valid_reg <= 1'b0;
            read_data_reg <= 64'h0;
        end else begin
            read_req_pulse <= 1'b0;
            if (!read_pending && decode_valid && (opcode == OP_READO)) begin
                read_pending <= 1'b1;
                read_resp_id_reg <= req_id_ff2;
                read_addr_reg <= req_insn_ff2[27:16];
                read_req_pulse <= 1'b1;
            end else if (read_resp_vld_int) begin
                read_pending <= 1'b0;
                read_valid_reg <= 1'b1;
                read_data_reg <= read_resp_data_int[63:0];
            end else if (read_fire) begin
                read_valid_reg <= 1'b0;
            end
        end
    end

    // Response multiplexer
    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            cop_pad_resp_vld <= 1'b0;
            cop_pad_resp_id <= {ID_WIDTH{1'b0}};
            cop_pad_resp_data <= 64'h0;
        end else begin
            cop_pad_resp_vld <= 1'b0;
            if (stat_valid_reg) begin
                cop_pad_resp_vld <= 1'b1;
                cop_pad_resp_id <= stat_resp_id;
                cop_pad_resp_data <= { {20{1'b0}}, accel_last_addr_int, 30'b0, accel_busy_int, accel_done_int };
            end else if (read_valid_reg) begin
                cop_pad_resp_vld <= 1'b1;
                cop_pad_resp_id <= read_resp_id_reg;
                cop_pad_resp_data <= read_data_reg;
            end
        end
    end

    // Connections toward accelerator
    wire loadw_rdy_int;
    wire loadi_rdy_int;
    wire accel_busy_int;
    wire accel_done_int;
    wire [11:0] accel_last_addr_int;
    wire read_resp_vld_int;
    wire [255:0] read_resp_data_int;

    wire loadw_vld_int = (!fifo_empty) && (fifo_head_type == 1'b0);
    wire loadi_vld_int = (!fifo_empty) && (fifo_head_type == 1'b1);
    wire [11:0] loadw_addr_int = fifo_addr[fifo_rd_ptr[3:0]];
    wire [11:0] loadi_addr_int = fifo_addr[fifo_rd_ptr[3:0]];
    wire [255:0] loadw_data_int = fifo_data[fifo_rd_ptr[3:0]];
    wire [255:0] loadi_data_int = fifo_data[fifo_rd_ptr[3:0]];

    assign pop_fifo = (!fifo_empty) && (((fifo_head_type == 1'b0) && loadw_rdy_int) || ((fifo_head_type == 1'b1) && loadi_rdy_int));

    wire read_req_vld_int = read_req_pulse;
    wire [11:0] read_req_addr_int = read_addr_reg;

    cnn_accel_top
    #(
        .DATAW(8),
        .IFM_CH(8),
        .OFM_CH(8),
        .K(3),
        .SRAM_AW(12)
    ) u_cnn_accel_top (
        .clk(clk),
        .rst_b(rst_b),
        .loadw_vld(loadw_vld_int),
        .loadw_addr(loadw_addr_int),
        .loadw_data(loadw_data_int),
        .loadw_rdy(loadw_rdy_int),
        .loadi_vld(loadi_vld_int),
        .loadi_addr(loadi_addr_int),
        .loadi_data(loadi_data_int),
        .loadi_rdy(loadi_rdy_int),
        .start_vld(start_pulse),
        .start_width(start_width_reg),
        .start_height(start_height_reg),
        .start_in_ch(start_in_ch_reg),
        .start_out_ch(start_out_ch_reg),
        .start_stride(start_stride_reg),
        .busy(accel_busy_int),
        .done(accel_done_int),
        .last_ofmap_addr(accel_last_addr_int),
        .read_req_vld(read_req_vld_int),
        .read_req_addr(read_req_addr_int),
        .read_resp_vld(read_resp_vld_int),
        .read_resp_data(read_resp_data_int)
    );
endmodule
