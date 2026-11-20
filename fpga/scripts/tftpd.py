#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""A small read-only TFTP server (RFC 1350 with the blksize option of RFC 2348) for booting the
board without installing one:   tftpd.py <directory> [port]

The standard port, 69, needs root (or `setcap cap_net_bind_service+ep` on the interpreter); any
other port matches a monitor built with -DTFTP_PORT=<port>. tftpd-hpa or any other server does
the same job: the monitor asks for legend64/fw_jump.bin, legend64/Image and
legend64/legend64-vc707.dtb.
"""
import os, socket, struct, sys, threading

def serve(root, data, peer):
    parts = data[2:].split(b'\0')
    name, mode = parts[0].decode(errors='replace'), parts[1].lower()
    opts = dict(zip((p.lower() for p in parts[2::2]), parts[3::2]))
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(1.0)
    path = os.path.normpath(os.path.join(root, name.lstrip("/")))    # symbolic links inside are followed
    if mode != b'octet' or not path.startswith(root + os.sep) or not os.path.isfile(path):
        s.sendto(struct.pack('>HH', 5, 1) + b'File not found\0', peer)
        print('%s: %s refused' % (peer[0], name), flush=True)
        return
    blob = open(path, 'rb').read()
    blk = 512
    if b'blksize' in opts:
        blk = max(8, min(int(opts[b'blksize']), 1428))
        pkt = struct.pack('>H', 6) + b'blksize\0' + str(blk).encode() + b'\0'
        want = 0
    else:
        pkt, want = None, None
    n = 0                                   # the block being sent; 0 is the option acknowledgement
    while True:
        if pkt is None:
            n += 1
            chunk = blob[(n - 1) * blk:n * blk]
            pkt, want = struct.pack('>HH', 3, n & 0xffff) + chunk, n & 0xffff
        for attempt in range(8):
            s.sendto(pkt, peer)
            try:
                while True:
                    r, frm = s.recvfrom(64)
                    if frm == peer and len(r) >= 4 and struct.unpack('>HH', r[:4]) == (4, want): break
            except socket.timeout:
                continue
            break
        else:
            print('%s: %s gave up at block %d' % (peer[0], name, n), flush=True)
            return
        if n > 0 and len(pkt) - 4 < blk:
            print('%s: %s, %d bytes sent' % (peer[0], name, len(blob)), flush=True)
            return
        pkt = None

def main():
    root = os.path.realpath(sys.argv[1])
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 69
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('', port))
    print('serving %s on UDP port %d' % (root, port), flush=True)
    while True:
        data, peer = s.recvfrom(1024)
        if len(data) > 4 and data[:2] == b'\0\1':
            threading.Thread(target=serve, args=(root, data, peer), daemon=True).start()

if __name__ == '__main__':
    main()
