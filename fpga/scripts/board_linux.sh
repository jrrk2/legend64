#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Boot Linux on the shared VC707: JTAG-load the bitstream, send OpenSBI, the kernel, the device
# tree and the initramfs through the monitor's UDP loader, then drive the shell over serial.
# Must run under the board lock:
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_linux.sh <bitstream>
# JTAG load only; the BPI flash is never written.
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
bit=${1:?bitstream}
L=$root/linux/out
(python3 "$here/serial.py" capture 150 --until "> " 2>&1) &
cap=$!
sleep 0.5
$HOME/synthgui/build-deps/prefix/bin/openFPGALoader --cable digilent --freq 15000000 "$bit" 2>&1 | tr "\r" "\n" | grep -E "isc_done" | tail -1
wait $cap
echo; echo "--- network load"
ping -c 2 -W 1 192.168.1.51 > /dev/null
(sleep 1; python3 "$here/netload.py" $L/fw_jump.bin@80000000 \
    $L/Image@80200000 $L/legend64-vc707-initramfs.dtb@86000000 $L/initramfs.cpio.gz@88000000 \
    --jump 80000000 --arg 86000000 1>&2) &
python3 "$here/serial.py" chat 90 "~ # " "cat /proc/cpuinfo; uname -a^" "~ # " "ifconfig eth0 192.168.1.51 up; sleep 3; ping -c 3 192.168.1.176^" "~ # " "cat /proc/interrupts; ifconfig eth0^" "~ # " ""
wait
echo; echo "--- ping from the host"
ping -c 4 -W 1 192.168.1.51 | tail -3
ping -c 3 -W 1 -s 1400 192.168.1.51 | tail -2
