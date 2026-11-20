#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Drive a serial console on stdio non-interactively (a tiny 'expect').

  qemu-drive.py [--timeout SECS] [--log FILE] STEP... -- command [args...]

Each STEP is 'REGEX' or 'REGEX=>TEXT': wait until REGEX appears in the output
that arrived since the previous step, then send TEXT plus a newline.  When all
steps are done (or the timeout expires) the command is terminated.  Exit status
0 = every step matched, 1 = timeout / command died early.
"""
import os, re, select, subprocess, sys, time

def main():
    a = sys.argv[1:]
    timeout, log = 300.0, None
    while a and a[0] in ("--timeout", "--log"):
        if a[0] == "--timeout": timeout = float(a[1])
        else: log = a[1]
        a = a[2:]
    cut = a.index("--")
    steps, cmd = a[:cut], a[cut + 1:]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, bufsize=0)
    logf = open(log, "wb") if log else None
    deadline = time.time() + timeout
    buf, ok = b"", True
    def pump(t):
        nonlocal buf
        r, _, _ = select.select([p.stdout], [], [], t)
        if not r: return True
        d = os.read(p.stdout.fileno(), 65536)
        if not d: return False
        buf += d
        if logf: logf.write(d); logf.flush()
        sys.stdout.buffer.write(d); sys.stdout.buffer.flush()
        return True
    for s in steps:
        pat, _, send = s.partition("=>")
        rx = re.compile(pat.encode())
        while True:
            m = rx.search(buf)
            if m: break
            left = deadline - time.time()
            if left <= 0 or not pump(min(left, 1.0)):
                ok = False; break
        if not ok:
            sys.stderr.write("\n[qemu-drive] FAILED waiting for %r\n" % pat); break
        buf = buf[m.end():]
        if "=>" in s:
            p.stdin.write(send.encode() + b"\n"); p.stdin.flush()
    end = time.time() + 1.0
    while ok and time.time() < end and pump(0.2): pass
    p.terminate()
    try: p.wait(5)
    except subprocess.TimeoutExpired: p.kill()
    sys.stderr.write("\n[qemu-drive] %s\n" % ("all steps matched" if ok else "FAILED"))
    return 0 if ok else 1

sys.exit(main())
