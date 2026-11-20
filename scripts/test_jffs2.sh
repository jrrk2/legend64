#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Host test of the monitor's JFFS2 reader (fpga/sw/jffs2.c) against images made by mkfs.jffs2:
# with its default compressors (zlib and rtime), with zlib only, and uncompressed.
# mkfs.jffs2 is taken from tools/mtd (mtd-utils unpacked with dpkg -x) or the PATH.
set -e
cd "$(dirname "$0")/.."
M=mkfs.jffs2; [ -x tools/mtd/usr/sbin/mkfs.jffs2 ] && M=tools/mtd/usr/sbin/mkfs.jffs2
T=build/jffs2test; rm -rf $T; mkdir -p $T/root/sub
gcc -O2 -Wall -fsanitize=address,undefined -o $T/jffs2_test fpga/sw/test/jffs2_test.c fpga/sw/jffs2.c
python3 - $T/root <<'PY'
import os, random, sys
d = sys.argv[1]; random.seed(1)
open(d + '/empty', 'wb').close()
open(d + '/small.conf', 'w').write('mac=02:00:00:fa:b1:e5\nip=192.168.1.51\n')
open(d + '/random.bin', 'wb').write(random.randbytes(300001))
open(d + '/zeros.bin', 'wb').write(bytes(70000))
open(d + '/runs.bin', 'wb').write(b''.join(bytes([random.randrange(4)]) * random.randrange(1, 40) for _ in range(20000)))
open(d + '/text.txt', 'w').write(''.join('line %d of some text that compresses well\n' % i for i in range(30000)))
open(d + '/sub/small.conf', 'w').write('a file of the same name that is not in the root directory\n')
PY
[ -f linux/out/Image ] && cp linux/out/Image $T/root/Image
files="empty small.conf random.bin zeros.bin runs.bin text.txt $([ -f $T/root/Image ] && echo Image) !absent !sub"
for opt in "" "-x rtime -x lzo" "-m none"; do
  $M -l -e 0x40000 -r $T/root -o $T/fs.img $opt
  echo "mkfs.jffs2 $opt: $(stat -c %s $T/fs.img) bytes"
  $T/jffs2_test $T/fs.img $T/root $files | grep -v ": ok$"
done
