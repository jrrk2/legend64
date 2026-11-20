#!/usr/bin/env python3
"""Generate a random self-terminating RV32IM program as a $readmemh image.

usage: gen_random.py <seed> <out.hex> [n_instructions]

Layout matches sw/common: reset entry at 0x80, scratch data at 0x10000, exit device at 0x2000_0000.
Reserved registers: x31 = scratch base, x30 = loop counter, x29 = jalr temporary.
The program contains straight-line arithmetic, loads/stores of every width, forward branches and
jumps, jal/jalr call-return pairs, and counted backward loops, so it always terminates.
"""
import random, sys

seed = int(sys.argv[1]); out = sys.argv[2]
N = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
rnd = random.Random(seed)
DATA = 0x10000
FREE = list(range(1, 29))  # registers the random code may write

def r_type(f7, rs2, rs1, f3, rd, op): return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def i_type(imm, rs1, f3, rd, op): return ((imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op
def s_type(imm, rs2, rs1, f3): return (((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1f) << 7) | 0x23
def b_type(imm, rs2, rs1, f3):
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3f) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | \
           (((imm >> 1) & 0xf) << 8) | (((imm >> 11) & 1) << 7) | 0x63
def u_type(imm20, rd, op): return ((imm20 & 0xfffff) << 12) | (rd << 7) | op
def j_type(imm, rd):
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3ff) << 21) | (((imm >> 11) & 1) << 20) | \
           (((imm >> 12) & 0xff) << 12) | (rd << 7) | 0x6f

def anyreg(): return rnd.choice([0] + list(range(1, 32))) if rnd.random() < 0.9 else 0
def dst(): return rnd.choice(FREE + [0])
def interesting(): return rnd.choice([0, 1, -1, 0x7ff, -0x800, 2, 31, 32, rnd.randint(-0x800, 0x7ff)])

def simple():
    """One instruction with no control flow."""
    k = rnd.random()
    if k < 0.30:
        f3 = rnd.randrange(8); f7 = 0x20 if (f3 in (0, 5) and rnd.random() < 0.5) else 0
        return r_type(f7, anyreg(), anyreg(), f3, dst(), 0x33)
    if k < 0.52:
        f3 = rnd.randrange(8)
        if f3 == 1: return i_type(rnd.randrange(32), anyreg(), 1, dst(), 0x13)
        if f3 == 5: return i_type(rnd.randrange(32) | (0x400 if rnd.random() < 0.5 else 0), anyreg(), 5, dst(), 0x13)
        return i_type(interesting(), anyreg(), f3, dst(), 0x13)
    if k < 0.58: return u_type(rnd.getrandbits(20), dst(), 0x37)
    if k < 0.62: return u_type(rnd.getrandbits(20), dst(), 0x17)
    if k < 0.72: return r_type(1, anyreg(), anyreg(), rnd.randrange(4), dst(), 0x33)
    if k < 0.76: return r_type(1, anyreg(), anyreg(), 4 + rnd.randrange(4), dst(), 0x33)
    if k < 0.89:
        f3 = rnd.choice([0, 1, 2, 4, 5]); size = 1 << (f3 & 3)
        return i_type(rnd.randrange(-0x400, 0x400) & ~(size - 1), 31, f3, dst(), 0x03)
    f3 = rnd.choice([0, 1, 2]); size = 1 << f3
    return s_type(rnd.randrange(-0x400, 0x400) & ~(size - 1), anyreg(), 31, f3)

def block(n, depth):
    """A list of n-ish instruction words with only internal control flow."""
    code = []
    while len(code) < n:
        k = rnd.random()
        left = n - len(code)
        if k < 0.70 or left < 8:
            code.append(simple())
        elif k < 0.82:  # forward conditional branch over a few instructions
            skip = rnd.randint(0, min(6, left - 2))
            body = [simple() for _ in range(skip)]
            code.append(b_type(4 * (skip + 1), anyreg(), anyreg(), rnd.choice([0, 1, 4, 5, 6, 7])))
            code += body
        elif k < 0.87:  # forward jal, optionally linking
            skip = rnd.randint(0, min(4, left - 2))
            code.append(j_type(4 * (skip + 1), rnd.choice([0, 1, 5, dst()])))
            code += [simple() for _ in range(skip)]
        elif k < 0.92:  # forward jalr through x29
            skip = rnd.randint(0, min(4, left - 3))
            code.append(u_type(0, 29, 0x17))
            code.append(i_type(4 * (skip + 2), 29, 0, rnd.choice([0, 1, 5, dst()]), 0x67))
            code += [simple() for _ in range(skip)]
        elif k < 0.96 and left > 12:  # call a tiny function placed inline, return through ra
            fn = [simple() for _ in range(rnd.randint(1, 4))]
            fn = [w for w in fn if ((w >> 7) & 31) != 1 or (w & 0x7f) == 0x23]  # keep ra intact
            code.append(j_type(8, 1))                       # jal ra, fn
            code.append(j_type(4 * (len(fn) + 2), 0))       # after return: skip the function
            code += fn
            code.append(i_type(0, 1, 0, 0, 0x67))           # ret
        elif depth < 2 and left > 12:  # counted backward loop
            body = block(rnd.randint(2, min(12, left - 4)), depth + 1 + 2)
            code.append(i_type(rnd.randint(1, 6), 0, 0, 30, 0x13))
            code += body
            code.append(i_type(-1, 30, 0, 30, 0x13))
            code.append(b_type(-4 * (len(body) + 1), 0, 30, 1))
        else:
            code.append(simple())
    return code

prog = []
prog.append(u_type(DATA >> 12, 31, 0x37))               # x31 = scratch base + 0x800
prog.append(i_type(0x400, 31, 0, 31, 0x13))
prog.append(i_type(0x400, 31, 0, 31, 0x13))
for r in range(1, 31):
    v = rnd.getrandbits(32) if rnd.random() < 0.8 else rnd.choice([0, 1, 0xffffffff, 0x80000000, 0x7fffffff])
    lo = v & 0xfff; hi = ((v + 0x800) >> 12) & 0xfffff
    prog.append(u_type(hi, r, 0x37)); prog.append(i_type(lo, r, 0, r, 0x13))
prog += block(N, 0)
prog.append(u_type(0x20000, 5, 0x37))                   # exit(0)
prog.append(s_type(0, 0, 5, 2))
prog.append(j_type(0, 0))

image = [j_type(0, 0)] * 32 + prog
assert len(image) * 4 < DATA
image += [0] * (DATA // 4 - len(image))
image += [rnd.getrandbits(32) for _ in range(0x1000 // 4)]
with open(out, "w") as f:
    for w in image: f.write("%08x\n" % (w & 0xffffffff))
