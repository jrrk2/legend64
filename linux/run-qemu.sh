#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Run the legend64 kernel on QEMU "virt", with the CPU cut down to what the
# real hardware has (as far as QEMU allows).
#
#   ./run-qemu.sh [initramfs] [qemu args...]   QEMU loads kernel+initramfs, QEMU's own DTB
#   ./run-qemu.sh board [qemu args...]         rehearse the BOARD boot flow: files placed at the
#                                              board load addresses, the board's initramfs DTB,
#                                              entry at 0x80000000 with a0=0, a1=DTB
#   ./run-qemu.sh append 'cmdline' [qemu args...]   like initramfs but with your own command line
# Console is the serial port on stdio; quit with Ctrl-A X.
# Environment: CPU=... replaces the CPU model string, MEM=... the RAM size.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
QEMU=$here/../tools/qemu-rv64
OPENSBI=$here/out/fw_jump.bin          # ./build-opensbi.sh

# RV64GC + Sv39 only.  Everything QEMU's "rv64" enables beyond that is off:
CPU=${CPU:-rv64,sv48=off,sv57=off,pmp=off,sstc=off,h=off,v=off,zba=off,zbb=off,zbc=off,zbs=off,zicbom=off,zicbop=off,zicboz=off,zicntr=off,zihpm=off,pmu-mask=0,zihintpause=off,zihintntl=off,zawrs=off,zfa=off,svadu=off,svade=on,svvptc=off,debug=off}
MEM=${MEM:-1G}
common=(-M virt -m "$MEM" -smp 1 -cpu "$CPU" -nographic -no-reboot)

mode=${1:-initramfs}; [ $# -gt 0 ] && shift
case "$mode" in
initramfs)
    exec "$QEMU" "${common[@]}" -bios "$OPENSBI" \
        -kernel "$here/out/Image" -initrd "$here/out/initramfs.cpio.gz" \
        -append "console=ttyS0,115200 earlycon rdinit=/init" "$@" ;;
append)
    args=$1; shift
    exec "$QEMU" "${common[@]}" -bios "$OPENSBI" -kernel "$here/out/Image" -append "$args" "$@" ;;
board)
    # same addresses as the board's boot monitor uses (README "Boot flow")
    exec "$QEMU" "${common[@]}" -bios none \
        -device loader,file="$OPENSBI",addr=0x80000000,force-raw=on \
        -device loader,file="$here/out/Image",addr=0x80200000,force-raw=on \
        -device loader,file="$here/out/legend64-vc707-initramfs.dtb",addr=0x86000000,force-raw=on \
        -device loader,file="$here/out/initramfs.cpio.gz",addr=0x88000000,force-raw=on \
        -device loader,file="$here/out/bootmon-shim.bin",addr=0x8f000000,force-raw=on \
        -device loader,addr=0x8f000000,cpu-num=0 "$@" ;;
*)  echo "usage: $0 [initramfs|board|append 'cmdline'] [qemu args]" >&2; exit 2 ;;
esac
