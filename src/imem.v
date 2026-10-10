// Instruction memory (read-only, asynchronous read). Loaded from a hex file.
module imem #(
    parameter FILE  = "program.hex",
    parameter WORDS = 256
)(
    input  [31:0] addr,
    output [31:0] instr
);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    reg [8*128-1:0] fname;
    initial begin
        for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000013; // NOP (addi x0,x0,0)
        if ($value$plusargs("prog=%s", fname)) $readmemh(fname, mem);   // simulation override
        else                                   $readmemh(FILE, mem);
    end
    assign instr = mem[addr[9:2]];   // 256 words = 1 KB
endmodule
