#!/usr/bin/env python3
"""Talk to the fable64 boot monitor on the VC707 UART (/dev/ttyUSB0, 115200 8N1).

usage: serial.py capture <seconds> [keys]         print what arrives; optional keys are sent after 1 s
       serial.py run <image.bin> <seconds>        load the image to 0x8000_0000, start it, print its output
       serial.py chat <seconds> <expect> <send> [<expect> <send> ...]
                                                  wait for each text in turn and answer it (^ = Enter);
                                                  <seconds> is the limit for each wait
In both modes capture stops early once the text given by --until appears.
"""
import os, sys, time, termios, select

def open_port():
    fd = os.open('/dev/ttyUSB0', os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = 0; a[1] = 0; a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; a[3] = 0
    a[4] = a[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd

def read_for(fd, seconds, out, until=None):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                d = os.read(fd, 4096)
            except BlockingIOError:
                continue
            out.extend(d)
            sys.stdout.write(d.decode('latin1').replace('\r', '')); sys.stdout.flush()
            if until and until.encode() in out:
                return True
    return False

def write_all(fd, data):
    # the monitor's UART has a one-byte receive buffer: pace the bytes at the line rate
    for i in range(0, len(data), 64):
        chunk = data[i:i + 64]
        while chunk:
            try:
                n = os.write(fd, chunk); chunk = chunk[n:]
            except BlockingIOError:
                time.sleep(0.001)
        termios.tcdrain(fd)

args = sys.argv[1:]
until = None
if '--until' in args:
    i = args.index('--until'); until = args[i + 1]; del args[i:i + 2]
fd = open_port()
out = bytearray()
if args[0] == 'capture':
    if len(args) > 2:
        read_for(fd, 1.0, out)
        for ch in args[2]:
            os.write(fd, ch.encode()); read_for(fd, 0.5, out)
    read_for(fd, float(args[1]), out, until)
elif args[0] == 'run':
    img = open(args[1], 'rb').read()
    write_all(fd, b'L' + len(img).to_bytes(4, 'little') + img + bytes([sum(img) & 0xff]))
    if not read_for(fd, 10, out, 'sum OK'):
        sys.exit('load failed')
    os.write(fd, b'g')
    read_for(fd, float(args[2]), out, until)
elif args[0] == 'chat':
    limit = float(args[1])
    for expect, send in zip(args[2::2], args[3::2] + ['']):
        del out[:]
        if not read_for(fd, limit, out, expect):
            sys.exit(f'\n[serial.py: timed out waiting for {expect!r}]')
        time.sleep(0.3)
        for ch in send.replace('^', '\r'):
            os.write(fd, ch.encode()); time.sleep(0.02)
    read_for(fd, 2.0, out)
