#!/usr/bin/env python3
"""Convert a flat little-endian binary into one hex word per line for $readmemh.

usage: bin2hex.py <in.bin> <out.hex> [bytes_per_word=4]
"""
import sys
n = int(sys.argv[3]) if len(sys.argv) > 3 else 4
d = open(sys.argv[1], "rb").read()
d += b"\0" * (-len(d) % n)
with open(sys.argv[2], "w") as f:
    for i in range(0, len(d), n):
        f.write("%0*x\n" % (2 * n, int.from_bytes(d[i:i + n], "little")))
