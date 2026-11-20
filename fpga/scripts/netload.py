#!/usr/bin/env python3
"""Send images to the fable64 boot monitor over UDP and start them.

usage: netload.py [--ip 192.168.1.51] <file>@<hex address> ... [--jump <hex address> [--arg <hex value>]]

Example (OpenSBI + Linux + device tree + initramfs, then enter the firmware with a1 = device tree):
  netload.py fw_jump.bin@80000000 Image@80200000 board.dtb@86000000 initramfs.cpio.gz@88000000 \\
             --jump 80000000 --arg 86000000

Protocol (port 6464, little-endian 24-byte header 'FBL1', command, sequence, address, length):
stop-and-wait, every packet acknowledged, resent after a timeout. See fpga/sw/monitor.c.
"""
import socket, struct, sys, time

args = sys.argv[1:]
ip, jump, arg, files = "192.168.1.51", None, 0, []
while args:
    a = args.pop(0)
    if a == "--ip": ip = args.pop(0)
    elif a == "--jump": jump = int(args.pop(0), 16)
    elif a == "--arg": arg = int(args.pop(0), 16)
    else:
        name, addr = a.rsplit("@", 1)
        files.append((name, int(addr, 16)))

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(0.25)
seq = 0

def call(cmd, addr, payload=b"", length=None, tries=40):
    global seq
    seq += 1
    pkt = struct.pack("<4sB3xIQI", b"FBL1", cmd, seq, addr, len(payload) if length is None else length) + payload
    for _ in range(tries):
        s.sendto(pkt, (ip, 6464))
        try:
            while True:
                r, _ = s.recvfrom(256)
                if len(r) >= 24 and r[:4] == b"FBL1" and r[4] == (cmd | 0x80) and struct.unpack_from("<I", r, 8)[0] == seq:
                    return
        except socket.timeout:
            pass
    sys.exit(f"no answer from {ip} (command {cmd}, address {addr:#x})")

call(3, 0)
print(f"monitor at {ip} answers")
CHUNK = 1408
for name, addr in files:
    data = open(name, "rb").read()
    t0 = time.time()
    for off in range(0, len(data), CHUNK):
        call(1, addr + off, data[off:off + CHUNK])
    dt = time.time() - t0
    print(f"{name}: {len(data)} bytes to {addr:#x} in {dt:.1f} s ({len(data) / dt / 1024:.0f} KiB/s)")
if jump is not None:
    call(2, jump, struct.pack("<Q", arg), length=8)
    print(f"jump to {jump:#x} with a1 = {arg:#x} acknowledged")
