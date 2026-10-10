`timescale 1ns/1ps
// Self-checking testbench. Run from the project root so program.hex is found.
module tb_cpu;
    reg clk = 0, rst = 1;
    wire [31:0] pc, a0;
    integer errors = 0, cycles = 0;

    riscv_pipeline #(.IMEM_FILE("sw/program.hex")) dut (
        .clk(clk), .rst(rst), .dbg_pc(pc), .dbg_a0(a0), .dbg_retire()
    );

    always #5 clk = ~clk;                       // 100 MHz
    always @(posedge clk) if (!rst) cycles <= cycles + 1;

    task check_reg(input integer n, input [31:0] expected);
        begin
            if (dut.rf.r[n] !== expected) begin
                $display("FAIL  x%0d = 0x%08h, expected 0x%08h", n, dut.rf.r[n], expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_mem(input integer widx, input [31:0] expected);
        begin
            if (dut.u_dmem.mem[widx] !== expected) begin
                $display("FAIL  mem[%0d] = 0x%08h, expected 0x%08h", widx, dut.u_dmem.mem[widx], expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, tb_cpu);
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (400) @(posedge clk);            // plenty for the test program

        check_reg(1,  32'h00000048);  // return address from jal
        check_reg(2,  10);   check_reg(3, 15);  check_reg(4, 5);
        check_reg(5,  5);    check_reg(6, 15);  check_reg(7, 10);
        check_reg(8,  40);   check_reg(9, 40);  check_reg(10, 42);
        check_reg(11, 55);   check_reg(12, 11); check_reg(14, 77);
        check_reg(13, 15);  check_reg(15, 99);   check_reg(16, 32'h12345678);
        check_reg(18, 32'hFFFFFFFF); check_reg(19, 255);
        check_reg(20, 32'h00005678); check_reg(21, 32'hFFFFFFFC);
        check_reg(22, 1);    check_reg(23, 0);  check_reg(24, 32'h0000008C);
        check_reg(26, 0);    check_reg(27, 1);  check_reg(28, 0);   // flush check
        check_reg(29, 123);  check_reg(30, 123); check_reg(31, 123);
        check_mem(0, 40);    check_mem(1, 32'h0000FF78);
        check_mem(2, 32'h00005678); check_mem(3, 123); check_mem(4, 123);

        if (errors == 0) $display("PASS: all checks passed (%0d cycles run)", cycles);
        else             $display("FAILED: %0d errors", errors);
        $finish;
    end
endmodule
