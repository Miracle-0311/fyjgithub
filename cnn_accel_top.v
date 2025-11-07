// Minimal CNN accelerator top integrating convolution, ReLU and pooling.
module cnn_accel_top
#(
    parameter DATAW = 8,
    parameter IFM_CH = 8,
    parameter OFM_CH = 8,
    parameter K = 3,
    parameter SRAM_AW = 12
)(
    input                        clk,
    input                        rst_b,
    // Weight load interface
    input                        loadw_vld,
    input      [SRAM_AW-1:0]     loadw_addr,
    input      [255:0]           loadw_data,
    output                       loadw_rdy,
    // IFM load interface
    input                        loadi_vld,
    input      [SRAM_AW-1:0]     loadi_addr,
    input      [255:0]           loadi_data,
    output                       loadi_rdy,
    // Start command
    input                        start_vld,
    input      [7:0]             start_width,
    input      [7:0]             start_height,
    input      [3:0]             start_in_ch,
    input      [3:0]             start_out_ch,
    input      [3:0]             start_stride,
    output reg                   busy,
    output reg                   done,
    output reg [11:0]            last_ofmap_addr,
    // Read interface
    input                        read_req_vld,
    input      [SRAM_AW-1:0]     read_req_addr,
    output reg                   read_resp_vld,
    output reg [255:0]           read_resp_data
);

    localparam MEM_BYTES = (1<<SRAM_AW)*4;
    localparam WIN_BYTES = IFM_CH*K*K;

    reg [7:0] weight_bytes [0:MEM_BYTES-1];
    reg [7:0] ifmap_bytes  [0:MEM_BYTES-1];
    reg [7:0] ofmap_bytes  [0:MEM_BYTES-1];

    integer i;

    assign loadw_rdy = 1'b1;
    assign loadi_rdy = 1'b1;

    // Load weight blocks
    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            // Scratchpad contents are cleared lazily by software before use.
        end else begin
            if (loadw_vld) begin
                for (i = 0; i < 32; i = i + 1) begin
                    weight_bytes[{loadw_addr,5'b0} + i] <= loadw_data[i*8 +: 8];
                end
            end
            if (loadi_vld) begin
                for (i = 0; i < 32; i = i + 1) begin
                    ifmap_bytes[{loadi_addr,5'b0} + i] <= loadi_data[i*8 +: 8];
                end
            end
        end
    end

    // Command registers
    reg [7:0]  cfg_width;
    reg [7:0]  cfg_height;
    reg [3:0]  cfg_in_ch;
    reg [3:0]  cfg_out_ch;
    reg [3:0]  cfg_stride;
    reg [9:0]  conv_width;
    reg [9:0]  conv_height;
    reg [9:0]  pool_width;
    reg [9:0]  pool_height;
    reg [15:0] total_pool_expected;

    // FSM
    localparam S_IDLE  = 3'd0;
    localparam S_PREP  = 3'd1;
    localparam S_WAIT  = 3'd2;
    localparam S_FLUSH = 3'd3;
    localparam S_DONE  = 3'd4;

    reg [2:0] state;

    // Window packing
    reg [DATAW*IFM_CH*K*K-1:0] win_data_reg;
    reg [DATAW*IFM_CH*K*K-1:0] weight_data_reg;
    reg                        conv_in_vld;

    wire                       conv_out_vld;
    wire [31:0]                conv_out_sum;

    wire                       relu_out_vld;
    wire [DATAW-1:0]           relu_out_data;

    wire                       pool_out_vld;
    wire [DATAW-1:0]           pool_out_data;
    wire [15:0]                pool_cfg_width;

    wire                       lb_win_vld;
    wire [DATAW*IFM_CH*K*K-1:0] lb_win_data;

    reg [9:0]  ox_cnt;
    reg [9:0]  oy_cnt;
    reg [3:0]  oc_cnt;

    reg [15:0] pool_out_count;

    reg [15:0] ofmap_write_ptr;

    conv3x3_sum
    #(
        .DATAW(DATAW),
        .IFM_CH(IFM_CH),
        .K(K)
    ) u_conv3x3_sum (
        .clk(clk),
        .rst_b(rst_b),
        .in_vld(conv_in_vld),
        .in_ch_cfg(cfg_in_ch),
        .win_data(win_data_reg),
        .weight_data(weight_data_reg),
        .out_vld(conv_out_vld),
        .out_sum(conv_out_sum)
    );

    relu
    #(
        .DATAW(DATAW)
    ) u_relu (
        .clk(clk),
        .rst_b(rst_b),
        .in_vld(conv_out_vld),
        .in_data(conv_out_sum),
        .out_vld(relu_out_vld),
        .out_data(relu_out_data)
    );

    maxpool2x2
    #(
        .DATAW(DATAW)
    ) u_maxpool2x2 (
        .clk(clk),
        .rst_b(rst_b),
        .in_vld(relu_out_vld),
        .in_data(relu_out_data),
        .cfg_out_width(pool_cfg_width),
        .out_vld(pool_out_vld),
        .out_data(pool_out_data)
    );

    line_buffer_3row
    #(
        .DATAW(DATAW),
        .IFM_CH(IFM_CH),
        .WIDTH_MAX(64)
    ) u_line_buffer_dummy (
        .clk(clk),
        .rst_b(rst_b),
        .in_vld(1'b0),
        .in_data({DATAW*IFM_CH{1'b0}}),
        .cfg_width(16'h0),
        .cfg_stride(4'h1),
        .win_vld(lb_win_vld),
        .win_data(lb_win_data)
    );

    // FSM operations
    integer ic_idx;
    integer ky_idx;
    integer kx_idx;
    integer pos_idx;
    integer in_y;
    integer in_x;
    integer in_addr;
    integer wt_addr;

    reg [9:0] conv_w_tmp;
    reg [9:0] conv_h_tmp;
    reg [9:0] pool_w_tmp;
    reg [9:0] pool_h_tmp;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            state <= S_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            conv_in_vld <= 1'b0;
            cfg_width <= 8'h0;
            cfg_height <= 8'h0;
            cfg_in_ch <= 4'h0;
            cfg_out_ch <= 4'h0;
            cfg_stride <= 4'h1;
            conv_width <= 10'h0;
            conv_height <= 10'h0;
            pool_width <= 10'h0;
            pool_height <= 10'h0;
            total_pool_expected <= 16'h0;
            ox_cnt <= 10'h0;
            oy_cnt <= 10'h0;
            oc_cnt <= 4'h0;
            pool_out_count <= 16'h0;
            ofmap_write_ptr <= 16'h0;
            last_ofmap_addr <= 12'h0;
            read_resp_vld <= 1'b0;
            read_resp_data <= 256'h0;
            conv_w_tmp <= 10'h0;
            conv_h_tmp <= 10'h0;
            pool_w_tmp <= 10'h0;
            pool_h_tmp <= 10'h0;
        end else begin
            read_resp_vld <= 1'b0;
            conv_in_vld <= 1'b0;
            if (pool_out_vld) begin
                ofmap_bytes[ofmap_write_ptr] <= pool_out_data;
                ofmap_write_ptr <= ofmap_write_ptr + 1'b1;
                pool_out_count <= pool_out_count + 1'b1;
            end
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start_vld) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        cfg_width <= start_width;
                        cfg_height <= start_height;
                        cfg_in_ch <= start_in_ch;
                        cfg_out_ch <= start_out_ch;
                        cfg_stride <= start_stride;
                        if (start_stride == 4'd2) begin
                            conv_w_tmp = ((start_width - K) >> 1) + 1;
                            conv_h_tmp = ((start_height - K) >> 1) + 1;
                        end else begin
                            conv_w_tmp = (start_width - K) + 1;
                            conv_h_tmp = (start_height - K) + 1;
                        end
                        pool_w_tmp = conv_w_tmp >> 1;
                        pool_h_tmp = conv_h_tmp >> 1;
                        conv_width <= conv_w_tmp;
                        conv_height <= conv_h_tmp;
                        pool_width <= pool_w_tmp;
                        pool_height <= pool_h_tmp;
                        total_pool_expected <= pool_w_tmp * pool_h_tmp * start_out_ch;
                        ox_cnt <= 10'h0;
                        oy_cnt <= 10'h0;
                        oc_cnt <= 4'h0;
                        pool_out_count <= 16'h0;
                        ofmap_write_ptr <= 16'h0;
                        state <= S_PREP;
                    end
                end
                S_PREP: begin
                    for (ic_idx = 0; ic_idx < IFM_CH; ic_idx = ic_idx + 1) begin
                        for (ky_idx = 0; ky_idx < K; ky_idx = ky_idx + 1) begin
                            for (kx_idx = 0; kx_idx < K; kx_idx = kx_idx + 1) begin
                                pos_idx = (ic_idx*K*K + ky_idx*K + kx_idx) * DATAW;
                                if ((ic_idx < cfg_in_ch) && (ox_cnt < conv_width) && (oy_cnt < conv_height)) begin
                                    in_y = oy_cnt * cfg_stride + ky_idx;
                                    in_x = ox_cnt * cfg_stride + kx_idx;
                                    in_addr = ((in_y * cfg_width) + in_x) * cfg_in_ch + ic_idx;
                                    win_data_reg[pos_idx +: DATAW] <= ifmap_bytes[in_addr];
                                end else begin
                                    win_data_reg[pos_idx +: DATAW] <= {DATAW{1'b0}};
                                end
                                if ((ic_idx < cfg_in_ch) && (oc_cnt < cfg_out_ch)) begin
                                    wt_addr = (((oc_cnt * cfg_in_ch) + ic_idx) * (K*K)) + (ky_idx*K + kx_idx);
                                    weight_data_reg[pos_idx +: DATAW] <= weight_bytes[wt_addr];
                                end else begin
                                    weight_data_reg[pos_idx +: DATAW] <= {DATAW{1'b0}};
                                end
                            end
                        end
                    end
                    conv_in_vld <= 1'b1;
                    state <= S_WAIT;
                end
                S_WAIT: begin
                    if (ox_cnt == conv_width - 1) begin
                        ox_cnt <= 10'h0;
                        if (oy_cnt == conv_height - 1) begin
                            oy_cnt <= 10'h0;
                            if (oc_cnt == cfg_out_ch - 1) begin
                                oc_cnt <= 4'h0;
                                state <= S_FLUSH;
                            end else begin
                                oc_cnt <= oc_cnt + 1'b1;
                                state <= S_PREP;
                            end
                        end else begin
                            oy_cnt <= oy_cnt + 1'b1;
                            state <= S_PREP;
                        end
                    end else begin
                        ox_cnt <= ox_cnt + 1'b1;
                        state <= S_PREP;
                    end
                end
                S_FLUSH: begin
                    if (pool_out_count == total_pool_expected) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                    last_ofmap_addr <= ofmap_write_ptr[16:5];
                    if (!start_vld) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase

            if (read_req_vld) begin
                read_resp_vld <= 1'b1;
                for (i = 0; i < 32; i = i + 1) begin
                    read_resp_data[i*8 +: 8] <= ofmap_bytes[{read_req_addr,5'b0} + i];
                end
            end
        end
    end

    assign pool_cfg_width = {6'h0, pool_width};
endmodule
