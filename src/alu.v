// ALU for RV32I
module alu (
    input      [31:0] a, b,
    input      [3:0]  ctrl,
    output reg [31:0] y
);
    localparam ADD=4'd0, SUB=4'd1, SLL=4'd2, SLT=4'd3, SLTU=4'd4,
               XOR_=4'd5, SRL=4'd6, SRA=4'd7, OR_=4'd8, AND_=4'd9;
    always @* begin
        case (ctrl)
            ADD:  y = a + b;
            SUB:  y = a - b;
            SLL:  y = a << b[4:0];
            SLT:  y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            SLTU: y = (a < b) ? 32'd1 : 32'd0;
            XOR_: y = a ^ b;
            SRL:  y = a >> b[4:0];
            SRA:  y = $signed(a) >>> b[4:0];
            OR_:  y = a | b;
            AND_: y = a & b;
            default: y = 32'd0;
        endcase
    end
endmodule
