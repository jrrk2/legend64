#!/usr/bin/env python3
"""Compare a legend64 run with QEMU, instruction by instruction.

usage: lockstep_qemu.py <test.elf> [--keep]

Runs the ELF on QEMU's `spike` machine (one instruction per translation block, logging the PC
and integer registers before every instruction) and on the legend64 simulator (logging every
retired instruction, its register write, and every trap). Then walks the two streams together:
the PCs must match step for step, and after each instruction the registers must agree.

QEMU logs an instruction that traps as an executed step with no register change; legend64 logs
it as a trap. QEMU logs nothing at all for an instruction-fetch page fault or an interrupt. Values that legitimately differ between the two machines are not compared:
reads of the cycle, time and instruction counters.
"""
import atexit, os, re, shutil, subprocess, sys, tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
elf = sys.argv[1]
base = elf[:-4]
CPU = "rv64,sv48=off,sv57=off,pmp=off,sstc=off,v=off,zba=off,zbb=off,zbc=off,zbs=off,zicbom=off,zicboz=off,zicbop=off,zawrs=off,zfa=off,zihintntl=off,zihintpause=off,svadu=off,svade=on,h=off,zkr=off,zcb=off,smrnmi=off"
# QEMU's register log runs to hundreds of megabytes: keep it on the project disk, never in /tmp,
# and remove it however the comparison ends
os.makedirs(os.path.join(root, "build/lockstep"), exist_ok=True)
tmp = tempfile.mkdtemp(prefix="run", dir=os.path.join(root, "build/lockstep"))
if "--keep" not in sys.argv:
    atexit.register(shutil.rmtree, tmp, ignore_errors=True)
qlog, dlog = os.path.join(tmp, "qemu.log"), os.path.join(tmp, "dut.tr")

r = subprocess.run([os.path.join(root, "tools/qemu-rv64"), "-M", "spike", "-cpu", CPU, "-m", "256M", "-bios", "none",
                    "-nographic", "-kernel", elf, "-accel", "tcg,one-insn-per-tb=on", "-d", "exec,cpu,nochain", "-D", qlog],
                   stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
if r.returncode not in (0, 1) or not os.path.getsize(qlog):
    sys.exit("qemu failed: " + r.stdout.decode()[:300])
tohost = open(base + ".tohost").read().strip()
subprocess.run([os.path.join(root, "build/sim/legend64"), "+hex=" + base + ".hex", "+tohost=" + tohost, "+quiet",
                "+max_cycles=5000000", "+trace=" + dlog], stdout=subprocess.DEVNULL, timeout=300)

# QEMU: a Trace line for each instruction, followed by the register dump from before it runs
qsteps = []
reg_re = re.compile(r"x(\d+)/\w+\s+([0-9a-f]{16})")
trace_re = re.compile(r"^Trace \d+: \S+ \[[0-9a-f]+/([0-9a-f]+)/")
for line in open(qlog, errors="replace"):
    if line.startswith(" x") and qsteps:
        for m in reg_re.finditer(line):
            qsteps[-1][1][int(m.group(1))] = int(m.group(2), 16)
    else:
        m = trace_re.match(line)
        if m:
            qsteps.append((int(m.group(1), 16), [0] * 32))
entry = 0x80000000
start = next(i for i, s in enumerate(qsteps) if s[0] == entry)   # skip QEMU's reset stub
qsteps = qsteps[start:]

dut = []
for line in open(dlog):
    f = line.split()
    if len(f) < 2 or (f[0] == "T" and len(f) < 4):
        break   # the last line may be cut short when the simulation stops
    if f[0] == "T":
        dut.append(("trap", int(f[1], 16), int(f[2], 16), int(f[3], 16)))
    else:
        w = (int(f[2][1:]), int(f[3], 16)) if len(f) > 2 and f[2][0] == "x" else None
        dut.append(("ret", int(f[0], 16), int(f[1], 16), w))

def is_counter_read(insn):
    return insn & 0x7f == 0x73 and (insn >> 12) & 3 != 0 and (insn >> 20) in (0xb00, 0xb02, 0xc00, 0xc01, 0xc02)

# CSRs QEMU implements and legend64 does not; software probes them and catches the trap
QEMU_ONLY_CSRS = {0x744, 0x741, 0x742, 0x740, 0x3a0, 0x3b0, 0x747, 0x30c, 0x10c, 0x14d, 0x5a8}

def probes_qemu_only_csr(insn):
    return insn & 0x7f == 0x73 and (insn >> 12) & 3 != 0 and (insn >> 20) in QEMU_ONLY_CSRS

shadow = list(qsteps[0][1])
skipped = 0
di = checked = traps = 0
for qi in range(len(qsteps) - 1):
    pc, _ = qsteps[qi]
    nregs = qsteps[qi + 1][1]
    if di >= len(dut):
        break   # the simulator stops a few instructions after the tohost write
    # QEMU sometimes logs an instruction, leaves the block without running it (an exit request),
    # and logs it again: the same PC twice with identical registers. Count only the second.
    if qsteps[qi + 1][0] == pc and nregs == qsteps[qi][1] and not (dut[di][0] == "ret" and di + 1 < len(dut) and dut[di + 1][1] == pc and dut[di][3] is None):
        skipped += 1
        continue
    ev = dut[di]
    # QEMU logs nothing for an instruction it could not fetch, nor for an interrupt
    while ev[0] == "trap" and ev[1] != pc and (ev[2] == 12 or ev[2] >> 63):
        traps += 1
        di += 1
        if di >= len(dut):
            break
        ev = dut[di]
    if di >= len(dut):
        break
    if ev[1] != pc:
        print(f"MISMATCH {os.path.basename(base)} step {qi}: qemu pc {pc:x}, legend64 {ev[0]} at {ev[1]:x}")
        sys.exit(1)
    di += 1
    if ev[0] == "trap":
        traps += 1
        if ev[2] == 2 and probes_qemu_only_csr(ev[3]):
            pass
        elif qsteps[qi + 1][0] == pc + 2 or qsteps[qi + 1][0] == pc + 4:
            # QEMU went straight on where legend64 trapped
            print(f"MISMATCH {os.path.basename(base)} step {qi}: legend64 trapped at {pc:x} (cause {ev[2]:x}), qemu did not")
            sys.exit(1)
    else:
        if ev[3]:
            shadow[ev[3][0]] = ev[3][1]
        if is_counter_read(ev[2]) and ev[3]:
            shadow[ev[3][0]] = nregs[ev[3][0]]
    for i in range(1, 32):
        if shadow[i] != nregs[i]:
            print(f"MISMATCH {os.path.basename(base)} step {qi} pc {pc:x} insn {ev[2] if ev[0]=='ret' else 0:08x}: x{i} qemu {nregs[i]:x} legend64 {shadow[i]:x}")
            sys.exit(1)
    checked += 1
print(f"OK {os.path.basename(base)} steps={checked} traps={traps} qemu_repeats={skipped}")
if "--keep" in sys.argv:
    print("logs in", tmp)
