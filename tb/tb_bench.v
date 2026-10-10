`timescale 1ns/1ps
// Performance testbench. Usage:  vvp bench.out +prog=sw/fib.hex
// Program must end with:  sw x0, 1020(x0)   (halt marker)
module tb_bench;
    reg clk = 0, rst = 1;
    wire [31:0] pc, a0;
    wire retire;
    integer cycles = 0, retired = 0, i;
    reg done = 0;

    riscv_pipeline dut (.clk(clk), .rst(rst), .dbg_pc(pc), .dbg_a0(a0), .dbg_retire(retire));
    always #5 clk = ~clk;

    always @(posedge clk) if (!rst && !done) begin
        cycles <= cycles + 1;
        if (retire) retired <= retired + 1;
        // store to halt address seen in MEM -> finish next cycle (store retires in WB)
        if (dut.exmem_mem_write && dut.exmem_result == 32'h000003FC) done <= 1;
    end

    initial begin
        repeat (3) @(posedge clk); rst = 0;
        wait (done);
        @(posedge clk); @(posedge clk);
        $display("=========== BENCHMARK RESULT ===========");
        $display("cycles   = %0d", cycles);
        $display("retired  = %0d instructions", retired);
        $display("CPI      = %0d.%02d", (cycles*100/retired)/100, (cycles*100/retired)%100);
        $display("a0 (x10) = %0d", a0);
        $write("mem[0..7] =");
        for (i = 0; i < 8; i = i + 1) $write(" %0d", dut.u_dmem.mem[i]);
        $display("");
        $display("========================================");
        $finish;
    end
    initial begin #2000000; $display("TIMEOUT - no halt marker reached"); $finish; end
endmodule
