# Self-checking test program for the RV32I pipeline (see tb/tb_cpu.v)
    addi x1, x0, 5          # x1 = 5
    addi x2, x0, 10         # x2 = 10
    add  x3, x1, x2         # 15   (forwarding from EX/MEM and MEM/WB)
    sub  x4, x2, x1         # 5
    and  x5, x3, x4         # 5
    or   x6, x3, x4         # 15
    xor  x7, x3, x4         # 10
    slli x8, x1, 3          # 40
    sw   x8, 0(x0)          # mem[0] = 40
    lw   x9, 0(x0)          # x9 = 40
    addi x10, x9, 2         # 42   (load-use hazard -> 1 stall)
    addi x11, x0, 0         # sum = 0
    addi x12, x0, 1         # i = 1
    addi x13, x0, 11
loop:
    add  x11, x11, x12      # sum += i
    addi x12, x12, 1
    bne  x12, x13, loop     # loop 10 times -> sum = 55
    jal  x1, func           # call, x1 = return address
    addi x15, x0, 99        # runs after return
    j    after
func:
    addi x14, x0, 77
    jalr x0, x1, 0          # return
after:
    lui  x16, 0x12345
    addi x16, x16, 0x678    # x16 = 0x12345678
    sb   x16, 4(x0)         # mem[1] byte0 = 0x78
    addi x17, x0, -1
    sb   x17, 5(x0)         # mem[1] byte1 = 0xFF
    lb   x18, 5(x0)         # -1 (sign-extended)
    lbu  x19, 5(x0)         # 255
    sh   x16, 8(x0)
    lh   x20, 8(x0)         # 0x5678
    addi x21, x0, -16
    srai x21, x21, 2        # -4
    slt  x22, x21, x2       # 1  (signed:   -4 < 10)
    sltu x23, x21, x2       # 0  (unsigned: 0xFFFFFFFC > 10)
    auipc x24, 0            # = address of this instruction
    addi x25, x0, 1
    beq  x25, x0, bad       # not taken
    beq  x25, x25, good     # taken -> next two instructions must be flushed
    addi x26, x0, 111       # must NOT execute
bad:
    addi x26, x0, 222       # must NOT execute
    addi x28, x0, 1         # must NOT execute
good:
    addi x27, x0, 1
    addi x29, x0, 123
    sw   x29, 12(x0)        # store data forwarded from EX/MEM
    lw   x30, 12(x0)        # 123
    lw   x31, 12(x0)
    sw   x31, 16(x0)        # load-use on store data -> stall, mem[4] = 123
    # ---- signed vs unsigned branch checks: x13 must end up = 15 ----
    addi x25, x0, -1
    addi x13, x0, 0
    blt  x25, x2, c1        # -1 < 10 signed        -> taken
    j    c1end
c1: addi x13, x13, 1
c1end:
    bltu x25, x2, c2end     # 0xFFFFFFFF < 10 false -> not taken
    addi x13, x13, 2
c2end:
    bge  x2, x25, c3        # 10 >= -1 signed       -> taken
    j    c3end
c3: addi x13, x13, 4
c3end:
    bgeu x25, x2, c4        # 0xFFFFFFFF >= 10      -> taken
    j    c4end
c4: addi x13, x13, 8
c4end:
done:
    j    done
