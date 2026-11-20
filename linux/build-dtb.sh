#!/bin/bash
# Compile the board device trees into out/.  No root needed.
#   out/legend64-vc707.dtb            NFS root (the default bootargs in the .dts)
#   out/legend64-vc707-initramfs.dtb  boots out/initramfs.cpio.gz preloaded at INITRD_ADDR
# Overrides (environment):
#   TIMEBASE_HZ=50000000 ./build-dtb.sh      CPU/mtime clock, default 25000000
#   BOOTARGS_NFS="..." / BOOTARGS_INITRAMFS="..."   replace a command line
#   INITRD_ADDR=0x88000000                   where the boot monitor puts the initramfs
# The initramfs variant records the exact initramfs size, so rerun this after
# build-initramfs.sh.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
T=/home/jonathan/riscv/tools/root
DTC="env LD_LIBRARY_PATH=$T/usr/lib/x86_64-linux-gnu $T/usr/bin/dtc"
CPP="cpp -nostdinc -undef -x assembler-with-cpp -P"
TIMEBASE_HZ=${TIMEBASE_HZ:-25000000}
INITRD_ADDR=${INITRD_ADDR:-0x88000000}
BOOTARGS_INITRAMFS=${BOOTARGS_INITRAMFS:-console=ttyS0,115200 earlycon rdinit=/init}
dts=$here/dts/legend64-vc707.dts
mkdir -p "$here/out"

nfs_args=(-DTIMEBASE_HZ="$TIMEBASE_HZ")
[ -n "${BOOTARGS_NFS:-}" ] && nfs_args+=(-DBOOTARGS="\"$BOOTARGS_NFS\"")
$CPP "${nfs_args[@]}" "$dts" | $DTC -I dts -O dtb -o "$here/out/legend64-vc707.dtb" -

rd=$here/out/initramfs.cpio.gz
if [ -f "$rd" ]; then
    size=$(stat -c %s "$rd")
    end=$(printf '0x%x' $((INITRD_ADDR + size)))
    $CPP -DTIMEBASE_HZ="$TIMEBASE_HZ" -DBOOTARGS="\"$BOOTARGS_INITRAMFS\"" \
         -DINITRD_START="$INITRD_ADDR" -DINITRD_END="$end" "$dts" \
        | $DTC -I dts -O dtb -o "$here/out/legend64-vc707-initramfs.dtb" -
    echo "initramfs variant: initrd $INITRD_ADDR..$end ($size bytes)"
else
    echo "out/initramfs.cpio.gz missing: initramfs DTB variant not built" >&2
fi
cp "$here"/out/legend64-vc707*.dtb "$here/dts/"
ls -l "$here"/out/*.dtb
