#!/usr/bin/env python3
"""Tiny RV32I assembler.  Usage: python3 asm.py prog.s prog.hex
Supports all RV32I base instructions (except fence/ecall/ebreak) plus the
pseudo-instructions: nop, li, mv, j, jr, ret, beqz, bnez, not, neg.
Output: one 32-bit hex word per line (for $readmemh) and a listing."""
import sys, re

ABI = "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6".split()
REG = {f"x{i}": i for i in range(32)}
REG.update({n: i for i, n in enumerate(ABI)}); REG["fp"] = 8

R_OPS = {"add":(0,0),"sub":(0x20,0),"sll":(0,1),"slt":(0,2),"sltu":(0,3),
         "xor":(0,4),"srl":(0,5),"sra":(0x20,5),"or":(0,6),"and":(0,7)}
I_OPS = {"addi":0,"slti":2,"sltiu":3,"xori":4,"ori":6,"andi":7}
SH_OPS = {"slli":(0,1),"srli":(0,5),"srai":(0x20,5)}
LOADS = {"lb":0,"lh":1,"lw":2,"lbu":4,"lhu":5}
STORES = {"sb":0,"sh":1,"sw":2}
BRANCH = {"beq":0,"bne":1,"blt":4,"bge":5,"bltu":6,"bgeu":7}

def reg(s):
    s = s.strip()
    if s not in REG: raise ValueError(f"bad register '{s}'")
    return REG[s]

def num(s):
    return int(s.strip(), 0)

def enc_r(f7, rs2, rs1, f3, rd, op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm, rs1, f3, rd, op):     return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xfff
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1f)<<7)|op
def enc_b(imm, rs2, rs1, f3, op):
    imm &= 0x1fff
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|op
def enc_u(imm20, rd, op):            return ((imm20&0xfffff)<<12)|(rd<<7)|op
def enc_j(imm, rd, op):
    imm &= 0x1fffff
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|op

def split_args(s):
    return [a.strip() for a in s.split(",")] if s.strip() else []

def expand(mn, args):
    """Expand pseudo-instructions into real ones (as (mnemonic, args) tuples)."""
    if mn == "nop":  return [("addi", ["x0","x0","0"])]
    if mn == "mv":   return [("addi", [args[0], args[1], "0"])]
    if mn == "not":  return [("xori", [args[0], args[1], "-1"])]
    if mn == "neg":  return [("sub",  [args[0], "x0", args[1]])]
    if mn == "j":    return [("jal",  ["x0", args[0]])]
    if mn == "jr":   return [("jalr", ["x0", args[0], "0"])]
    if mn == "ret":  return [("jalr", ["x0", "ra", "0"])]
    if mn == "beqz": return [("beq",  [args[0], "x0", args[1]])]
    if mn == "bnez": return [("bne",  [args[0], "x0", args[1]])]
    if mn == "li":
        v = num(args[1])
        if -2048 <= v <= 2047:
            return [("addi", [args[0], "x0", str(v)])]
        v &= 0xffffffff
        lo = v & 0xfff
        if lo >= 0x800: lo -= 0x1000
        hi = ((v - lo) >> 12) & 0xfffff
        return [("lui", [args[0], str(hi)]), ("addi", [args[0], args[0], str(lo)])]
    return [(mn, args)]

def assemble(lines):
    # pass 1: strip comments, collect labels, expand pseudos
    items, labels, pc = [], {}, 0
    for raw in lines:
        line = raw.split("#")[0].strip()
        while ":" in line:
            lab, line = line.split(":", 1)
            labels[lab.strip()] = pc
            line = line.strip()
        if not line: continue
        parts = line.split(None, 1)
        mn, args = parts[0].lower(), split_args(parts[1] if len(parts) > 1 else "")
        for m, a in expand(mn, args):
            items.append((pc, m, a, raw.strip()))
            pc += 4
    # pass 2: encode
    words = []
    for pc, mn, a, src in items:
        def target(t):  # label or number -> pc-relative offset
            return (labels[t] - pc) if t in labels else num(t)
        try:
            if mn in R_OPS:
                f7, f3 = R_OPS[mn]; w = enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]), 0x33)
            elif mn in I_OPS:
                w = enc_i(num(a[2]), reg(a[1]), I_OPS[mn], reg(a[0]), 0x13)
            elif mn in SH_OPS:
                f7, f3 = SH_OPS[mn]; w = enc_i((f7<<5)|(num(a[2])&0x1f), reg(a[1]), f3, reg(a[0]), 0x13)
            elif mn in LOADS:
                m = re.match(r"(-?\w+)\((\w+)\)", a[1]); w = enc_i(num(m[1]), reg(m[2]), LOADS[mn], reg(a[0]), 0x03)
            elif mn in STORES:
                m = re.match(r"(-?\w+)\((\w+)\)", a[1]); w = enc_s(num(m[1]), reg(a[0]), reg(m[2]), STORES[mn], 0x23)
            elif mn in BRANCH:
                w = enc_b(target(a[2]), reg(a[1]), reg(a[0]), BRANCH[mn], 0x63)
            elif mn == "jal":
                w = enc_j(target(a[1]), reg(a[0]), 0x6f)
            elif mn == "jalr":
                w = enc_i(num(a[2]), reg(a[1]), 0, reg(a[0]), 0x67)
            elif mn == "lui":
                w = enc_u(num(a[1]), reg(a[0]), 0x37)
            elif mn == "auipc":
                w = enc_u(num(a[1]), reg(a[0]), 0x17)
            else:
                raise ValueError(f"unknown instruction '{mn}'")
        except Exception as e:
            sys.exit(f"error at pc=0x{pc:x} ({src}): {e}")
        words.append((pc, w, src))
    return words, labels

if __name__ == "__main__":
    if len(sys.argv) != 3: sys.exit(__doc__)
    words, labels = assemble(open(sys.argv[1]).read().splitlines())
    with open(sys.argv[2], "w") as f:
        for pc, w, src in words: f.write(f"{w:08x}\n")
    for pc, w, src in words: print(f"{pc:04x}: {w:08x}   {src}")
