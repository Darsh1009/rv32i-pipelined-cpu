// 32 x 32-bit register file, x0 hardwired to 0.
// Write-first bypass: if WB writes a register in the same cycle ID reads it,
// the new value is returned (solves the 3-instruction-apart hazard).
module regfile (
    input         clk,
    input         we,
    input  [4:0]  ra1, ra2, wa,
    input  [31:0] wd,
    output [31:0] rd1, rd2,
    output [31:0] dbg_x10        // register a0, for LEDs / debug
);
    reg [31:0] r [0:31];
    integer i;
    initial for (i = 0; i < 32; i = i + 1) r[i] = 32'd0;

    always @(posedge clk)
        if (we && wa != 5'd0) r[wa] <= wd;

    assign rd1 = (ra1 == 5'd0) ? 32'd0 : (we && wa == ra1) ? wd : r[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : (we && wa == ra2) ? wd : r[ra2];
    assign dbg_x10 = r[10];
endmodule
