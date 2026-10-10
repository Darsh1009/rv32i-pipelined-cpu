# LED counter demo for Basys 3: a0 (x10) is shown on the 16 LEDs
    li   x10, 0
loop:
    addi x10, x10, 1        # count up
    li   x5, 1000000        # delay (~0.2 s at 25 MHz)
delay:
    addi x5, x5, -1
    bnez x5, delay
    j    loop
