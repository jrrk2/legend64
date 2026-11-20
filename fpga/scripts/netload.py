#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Send images to the legend64 boot monitor over UDP and start them.

usage: netload.py [--ip 192.168.1.51] <file>@<hex address> ... [--jump <hex address> [--arg <hex value>]]
       netload.py --read <hex address> <hex length> <file>     copy memory (or flash, at 60000000) to a file
       netload.py --flash <image> [--offset <hex>] [--reconfigure] [--force]
                                    write an image made by bit2flash.py to the configuration flash:
                                    it is sent to memory, then the monitor erases, programs and
                                    verifies the blocks that differ; --reconfigure then reloads the FPGA

Example (OpenSBI + Linux + device tree + initramfs, then enter the firmware with a1 = device tree):
  netload.py fw_jump.bin@80000000 Image@80200000 board.dtb@86000000 initramfs.cpio.gz@88000000 \\
             --jump 80000000 --arg 86000000

Protocol (port 6464, little-endian 24-byte header 'FBL1', command, sequence, address, length):
stop-and-wait, every packet acknowledged, resent after a timeout. See fpga/sw/monitor.c.
"""
import socket, struct, sys, time

args = sys.argv[1:]
ip, jump, arg, files = "192.168.1.51", None, 0, []
read, flash, offset, flags = None, None, 0, 0
UPDATE_ADDR = 0x90000000
while args:
    a = args.pop(0)
    if a == "--ip": ip = args.pop(0)
    elif a == "--jump": jump = int(args.pop(0), 16)
    elif a == "--arg": arg = int(args.pop(0), 16)
    elif a == "--read": read = (int(args.pop(0), 16), int(args.pop(0), 16), args.pop(0))
    elif a == "--flash": flash = args.pop(0)
    elif a == "--offset": offset = int(args.pop(0), 16)
    elif a == "--reconfigure": flags |= 1
    elif a == "--force": flags |= 2
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
                r, _ = s.recvfrom(2048)
                if len(r) >= 24 and r[:4] == b"FBL1" and r[4] == (cmd | 0x80) and struct.unpack_from("<I", r, 8)[0] == seq:
                    return r[24:]
        except socket.timeout:
            pass
    sys.exit(f"no answer from {ip} (command {cmd}, address {addr:#x})")

call(3, 0)
print(f"monitor at {ip} answers")
CHUNK = 1408
if flash is not None:
    image = open(flash, "rb").read()
    image += b"\xff" * (-len(image) % 8)
    files.append((flash, UPDATE_ADDR))
for name, addr in files:
    data = image if name is flash else open(name, "rb").read()
    t0 = time.time()
    for off in range(0, len(data), CHUNK):
        call(1, addr + off, data[off:off + CHUNK])
    dt = time.time() - t0
    print(f"{name}: {len(data)} bytes to {addr:#x} in {dt:.1f} s ({len(data) / dt / 1024:.0f} KiB/s)")
if jump is not None:
    call(2, jump, struct.pack("<Q", arg), length=8)
    print(f"jump to {jump:#x} with a1 = {arg:#x} acknowledged")
if read is not None:
    addr, length, name = read
    t0 = time.time()
    with open(name, "wb") as f:
        for off in range(0, length, 1400):
            n = min(1400, length - off)
            d = call(4, addr + off, length=n)
            if len(d) != n: sys.exit(f"short read at {addr + off:#x}")
            f.write(d)
    dt = time.time() - t0
    print(f"{name}: {length} bytes from {addr:#x} in {dt:.1f} s ({length / dt / 1024:.0f} KiB/s)")
if flash is not None:
    # what was sent must be what is in memory before it goes anywhere near the flash
    back = b"".join(call(4, UPDATE_ADDR + off, length=min(1400, len(image) - off)) for off in range(0, len(image), 1400))
    if back != image: sys.exit("the image in the board's memory does not match the file: nothing written")
    call(5, UPDATE_ADDR, struct.pack("<QQ", offset, flags), length=len(image))
    t0 = time.time()
    while True:
        time.sleep(1)
        state, done, total, written = struct.unpack("<4I", call(6, 0)[:16])
        print(f"\rflash: block {done} of {total}, {written} written, {time.time() - t0:.0f} s ", end="", flush=True)
        if state != 1: break
    print()
    if state != 2: sys.exit("flash update FAILED (see the serial console)")
    print("flash matches the image" + ("; the FPGA is reloading from it" if flags & 1 else ""))
