# Benchmark 1: iterative Fibonacci, a0 = fib(20) = 6765
    li   a0, 0
    li   a1, 1
    li   t0, 20
loop:
    add  t1, a0, a1
    mv   a0, a1
    mv   a1, t1
    addi t0, t0, -1
    bnez t0, loop
    sw   x0, 1020(x0)       # halt marker: testbench stops here
