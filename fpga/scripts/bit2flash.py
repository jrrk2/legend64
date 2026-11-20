#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Convert a Xilinx .bit file to the image the VC707's BPI flash holds, and back.

usage: bit2flash.py <design.bit> <flash.img>        for netload.py --flash, the monitor's U
                                                    command, or flashcp to the bitstream partition
       bit2flash.py --back <flash.img> <config.bin> the configuration data again (as in a .bin)

The image is the flash as software sees it through the SoC's window at 0x6000_0000 (and as the
kernel's /dev/mtd0 presents it): 16-bit words, low byte first. The FPGA reads a word as two
configuration bytes, the high byte first, each with its bits in the opposite order to the
flash's data lines; this is what Vivado's write_cfgmem -interface BPIx16 produces.
"""
import sys

REV = bytes(int('{:08b}'.format(i)[::-1], 2) for i in range(256))

def swap(data):
    data = data.translate(REV)
    out = bytearray(len(data))
    out[0::2] = data[1::2]
    out[1::2] = data[0::2]
    return bytes(out)

def config_data(bit):
    """The configuration data of a .bit file: what follows its header fields a, b, c, d, e."""
    if bit[:2] != b'\x00\x09':
        sys.exit('not a .bit file')
    p = 2 + 9 + 2          # the 9-byte field and the length of the next
    while True:
        key = bit[p:p + 1]
        if key == b'e':
            n = int.from_bytes(bit[p + 1:p + 5], 'big')
            return bit[p + 5:p + 5 + n]
        if key not in (b'a', b'b', b'c', b'd'):
            sys.exit('unexpected field in the .bit header')
        p += 3 + int.from_bytes(bit[p + 1:p + 3], 'big')

if __name__ == '__main__':
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == '--back':
        d = open(a[1], 'rb').read()
        open(a[2], 'wb').write(swap(d + b'\xff' * (len(d) % 2)))
    elif len(a) == 2:
        d = config_data(open(a[0], 'rb').read())
        d += b'\xff' * (-len(d) % 8)
        open(a[1], 'wb').write(swap(d))
        print('%s: %d bytes' % (a[1], len(d)))
    else:
        sys.exit(__doc__)
