# Benchmark 2: bubble sort of 8 words stored at address 0
    li   t0, 64
    sw   t0, 0(x0)
    li   t0, 25
    sw   t0, 4(x0)
    li   t0, 12
    sw   t0, 8(x0)
    li   t0, 22
    sw   t0, 12(x0)
    li   t0, 11
    sw   t0, 16(x0)
    li   t0, 90
    sw   t0, 20(x0)
    li   t0, 3
    sw   t0, 24(x0)
    li   t0, 47
    sw   t0, 28(x0)
    li   s0, 8              # n
outer:
    addi s1, s0, -1         # compares in this pass
    li   t0, 0              # i
inner:
    slli t1, t0, 2
    lw   t2, 0(t1)
    lw   t3, 4(t1)
    bge  t3, t2, noswap
    sw   t3, 0(t1)
    sw   t2, 4(t1)
noswap:
    addi t0, t0, 1
    bne  t0, s1, inner
    addi s0, s0, -1
    li   t4, 1
    bne  s0, t4, outer
    lw   a0, 0(x0)          # a0 = smallest = 3
    sw   x0, 1020(x0)       # halt marker
