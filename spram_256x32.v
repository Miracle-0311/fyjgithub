// Simple single-port RAM with byte write enable
module spram_256x32
#(
    parameter AW = 12
)(
    input              clk,
    input              rst_b,
    input              en,
    input  [AW-1:0]    addr,
    input  [31:0]      din,
    input  [3:0]       we,
    output reg [31:0]  dout
);

    reg [31:0] mem [0:(1<<AW)-1];
    integer i;

    always @(posedge clk or negedge rst_b) begin
        if (!rst_b) begin
            dout <= 32'h0;
        end else begin
            if (en) begin
                if (we[0]) mem[addr][7:0]   <= din[7:0];
                if (we[1]) mem[addr][15:8]  <= din[15:8];
                if (we[2]) mem[addr][23:16] <= din[23:16];
                if (we[3]) mem[addr][31:24] <= din[31:24];
                dout <= mem[addr];
            end
        end
    end
endmodule
