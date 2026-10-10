# RV32I 5-Stage Pipelined CPU (Verilog)

A 32-bit RISC-V (RV32I) processor with a classic 5-stage pipeline
(IF, ID, EX, MEM, WB), written in Verilog and verified in simulation with
Icarus Verilog. Includes its own assembler, a self-checking testbench and
a CPI benchmark setup.

## Features
- All RV32I integer instructions (loads/stores of byte, half and word; branches; jumps; LUI/AUIPC)
- **Data forwarding** from EX/MEM and MEM/WB, plus register-file write-first bypass
- **Load-use hazard detection** with a 1-cycle stall
- **Control hazards**: branches/jumps resolved in EX, 2-cycle flush when taken
- Self-checking testbench covering forwarding, stalls, flushes, sign/zero extension and signed/unsigned compares
- Small Python assembler (`tools/asm.py`) so programs can be written in assembly
- Retired-instruction counter for CPI measurement
- Basys 3 FPGA wrapper (`fpga/`), not yet tested on hardware

Not implemented: CSRs, ECALL/EBREAK/FENCE (treated as NOP), exceptions, caches.

## Pipeline overview
```
 IF        ID          EX            MEM        WB
+----+   +-------+   +--------+   +--------+  +-----+
| PC |-->| decode|-->|  ALU   |-->|  data  |->| reg |
|imem|   | regfile|  | branch |   |  mem   |  | file|
+----+   +-------+   +--------+   +--------+  +-----+
              ^   forwarding (EX/MEM, MEM/WB) --+
              +-- hazard unit: stall on load-use, flush on taken branch
```

## Repository layout
```
src/    alu.v  regfile.v  imem.v  dmem.v  riscv_pipeline.v
tb/     tb_cpu.v (self-checking test)   tb_bench.v (CPI measurement)
sw/     test.s  fib.s  bubble.s         (assembly programs)
tools/  asm.py                          (RV32I assembler)
fpga/   fpga_top.v  basys3.xdc  blink.s  blink.hex
```

## How to run (needs Python 3 and Icarus Verilog)

**1. Functional test**
```
python tools/asm.py sw/test.s sw/program.hex
iverilog -g2012 -o sim.out src/alu.v src/regfile.v src/imem.v src/dmem.v src/riscv_pipeline.v tb/tb_cpu.v
vvp sim.out
```
Expected last line: `PASS: all checks passed (400 cycles run)`

View waveforms: open `cpu.vcd` in GTKWave or Surfer.

**2. Performance benchmarks**
```
python tools/asm.py sw/fib.s sw/fib.hex
iverilog -g2012 -o bench.out src/alu.v src/regfile.v src/imem.v src/dmem.v src/riscv_pipeline.v tb/tb_bench.v
vvp bench.out +prog=sw/fib.hex
```
Use `sw/bubble.s` / `sw/bubble.hex` the same way.

## Results (baseline, no branch prediction)

| Benchmark | Cycles | Instructions | CPI | Result check |
|---|---|---|---|---|
| fib(20) | 145 | 103 | 1.40 | a0 = 6765 |
| bubble sort (8 elements) | 363 | 255 | 1.42 | memory sorted correctly |

CPI = cycles / instructions retired. Most of the overhead comes from the
2-cycle penalty on taken branches (fib has 19 taken branches = 38 lost
cycles) and from load-use stalls.

## Verification
The testbench checks register and memory contents after running `sw/test.s`.
To confirm the tests are meaningful, deliberate bugs were injected (stall
disabled, forwarding broken, flush removed, signed compare made unsigned)
and each one made the testbench fail.

## Future work
- [ ] Branch predictor (static, then 2-bit counters) and re-measure CPI
- [ ] M extension (MUL/DIV)
- [ ] Direct-mapped cache
- [ ] Run official riscv-arch-test compliance suite
- [ ] RTL-to-GDS with OpenLane (SkyWater 130nm)
- [ ] FPGA hardware demo on Basys 3
