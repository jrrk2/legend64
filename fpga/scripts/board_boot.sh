#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Load a bitstream on the shared VC707 and exercise it: boot log, status, ping.
# Must run under the board lock:
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_boot.sh <bitstream>
# JTAG load only; the BPI flash is never written.
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
bit=${1:?bitstream}
log=${bit%.bit}.uart.log
(python3 "$here/serial.py" capture ${2:-60} --until "> " > "$log" 2>&1) &
cap=$!
sleep 0.5
$HOME/synthgui/build-deps/prefix/bin/openFPGALoader --cable digilent --freq 15000000 "$bit" 2>&1 | tr "\r" "\n" | grep -E "isc_done|^Done |DCI match|EOS |CRC Error|^Done$" | tail -6
wait $cap
cat "$log"
echo "--- ping 192.168.1.51"
ping -c 5 -W 1 192.168.1.51 | tail -3
ping -c 3 -W 1 -s 1400 192.168.1.51 | tail -2
echo "--- status"
python3 "$here/serial.py" capture 2 i
