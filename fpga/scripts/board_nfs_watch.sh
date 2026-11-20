#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Boot Linux on the shared VC707 with its root on NFS, leaving the serial port alone so the console
# can be watched in a terminal program (picocom -b 115200 /dev/ttyUSB0). JTAG-loads the bitstream,
# waits for the monitor to answer ping, sends OpenSBI, the kernel and the NFS-root device tree, then
# holds the board for <minutes> (default 20), logging a ping to the board every 10 s.
# Must run under the board lock:
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_nfs_watch.sh <bitstream> [minutes]
# JTAG load only; the BPI flash is never written.
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
bit=${1:?bitstream}; minutes=${2:-20}
L=$root/linux/out
$HOME/synthgui/build-deps/prefix/bin/openFPGALoader --cable digilent --freq 15000000 "$bit" 2>&1 | tr "\r" "\n" | grep -E "isc_done" | tail -1
for i in $(seq 150); do ping -c 1 -W 1 192.168.1.51 > /dev/null && break; sleep 1; done
echo "monitor answered ping after ~$i s"
sleep 2
python3 "$here/netload.py" $L/fw_jump.bin@80000000 \
    $L/Image@80200000 $L/legend64-vc707.dtb@86000000 --jump 80000000 --arg 86000000 2>&1 | tail -3
end=$((SECONDS + minutes * 60))
while [ $SECONDS -lt $end ]; do
  echo "$(date +%T) $(ping -c 1 -W 1 192.168.1.51 | grep -E 'time=|100% packet loss' | sed 's/.*\(time=.*\)/\1/; s/.*100% packet loss.*/LOST/')"
  sleep 10
done
