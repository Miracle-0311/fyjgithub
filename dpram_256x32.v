// Simple dual-port RAM with byte write enables
module dpram_256x32
#(
    parameter AW = 12
)(
    input              clk,
    input              rst_b,
    // Port A
    input              en_a,
    input  [AW-1:0]    addr_a,
    input  [31:0]      din_a,
    input  [3:0]       we_a,
    output reg [31:0]  dout_a,
    // Port B
    input              en_b,
    input  [AW-1:0]    addr_b,
    input  [31:0]      din_b,
    input  [3:0]       we_b,
    output reg [31:0]  dout_b
);

    reg [31:0] mem [0:(1<<AW)-1];
    integer j;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            dout_a <= 32'h0;
            dout_b <= 32'h0;
        end else begin
            if (en_a) begin
                if (we_a[0]) mem[addr_a][7:0]   <= din_a[7:0];
                if (we_a[1]) mem[addr_a][15:8]  <= din_a[15:8];
                if (we_a[2]) mem[addr_a][23:16] <= din_a[23:16];
                if (we_a[3]) mem[addr_a][31:24] <= din_a[31:24];
                dout_a <= mem[addr_a];
            end
            if (en_b) begin
                if (we_b[0]) mem[addr_b][7:0]   <= din_b[7:0];
                if (we_b[1]) mem[addr_b][15:8]  <= din_b[15:8];
                if (we_b[2]) mem[addr_b][23:16] <= din_b[23:16];
                if (we_b[3]) mem[addr_b][31:24] <= din_b[31:24];
                dout_b <= mem[addr_b];
            end
        end
    end
endmodule
