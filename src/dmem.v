// Data memory with byte / halfword / word access (LB,LH,LW,LBU,LHU,SB,SH,SW).
module dmem (
    input         clk,
    input         mem_write,
    input  [2:0]  funct3,
    input  [31:0] addr,
    input  [31:0] wdata,
    output reg [31:0] rdata
);
    reg [31:0] mem [0:255];          // 1 KB
    integer i;
    initial for (i = 0; i < 256; i = i + 1) mem[i] = 32'd0;

    wire [7:0] widx = addr[9:2];
    wire [1:0] off  = addr[1:0];
    wire [31:0] word = mem[widx];

    // ---- store ----
    reg [31:0] w;
    always @(posedge clk) begin
        if (mem_write) begin
            w = mem[widx];
            case (funct3[1:0])
                2'b00: case (off)                          // SB
                    2'd0: w[7:0]   = wdata[7:0];
                    2'd1: w[15:8]  = wdata[7:0];
                    2'd2: w[23:16] = wdata[7:0];
                    2'd3: w[31:24] = wdata[7:0];
                endcase
                2'b01: if (off[1]) w[31:16] = wdata[15:0]; // SH
                       else        w[15:0]  = wdata[15:0];
                default: w = wdata;                        // SW
            endcase
            mem[widx] <= w;
        end
    end

    // ---- load (sign/zero extension) ----
    reg [7:0]  b;
    reg [15:0] h;
    always @* begin
        case (off)
            2'd0: b = word[7:0];
            2'd1: b = word[15:8];
            2'd2: b = word[23:16];
            default: b = word[31:24];
        endcase
        h = off[1] ? word[31:16] : word[15:0];
        case (funct3)
            3'b000:  rdata = {{24{b[7]}},  b};   // LB
            3'b001:  rdata = {{16{h[15]}}, h};   // LH
            3'b010:  rdata = word;               // LW
            3'b100:  rdata = {24'd0, b};         // LBU
            3'b101:  rdata = {16'd0, h};         // LHU
            default: rdata = word;
        endcase
    end
endmodule
