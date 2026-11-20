#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Where do transmitted frames go? On the Debian NFS-root system (loaded first if a bitstream is
# given, else as it is running), read the Ethernet hardware's frame counters and the driver's,
# send TCP to this host for a few seconds, read them again and print how far each moved:
#   driver: frames handed to the hardware        hardware: put into the transmit FIFO, discarded,
#   taken by the MAC, started on the PHY interface            host: TCP segments received
# Run under the board lock:
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_txcount.sh <bitstream|-> [seconds]
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
bit=${1:?bitstream, or - for the running system}; secs=${2:-10}
L=$root/linux/out; B=192.168.1.51; H=192.168.1.176
S="ssh -o BatchMode=yes -o ConnectTimeout=90 -o StrictHostKeyChecking=accept-new $B"
trap 'kill $(jobs -p) 2>/dev/null' EXIT
if [ "$bit" != - ]; then
  $HOME/synthgui/build-deps/prefix/bin/openFPGALoader --cable digilent --freq 15000000 "$bit" 2>&1 | tr "\r" "\n" | grep -E "isc_done" | tail -1
  for i in $(seq 150); do ping -c 1 -W 1 $B > /dev/null && break; sleep 1; done
  sleep 2
  python3 "$here/netload.py" $L/fw_jump.bin@80000000 $L/Image@80200000 $L/legend64-vc707.dtb@86000000 \
      --jump 80000000 --arg 86000000 2>&1 | tail -1
  t0=$SECONDS
  for i in $(seq 120); do sleep 5; timeout 3 bash -c "echo > /dev/tcp/$B/22" 2>/dev/null && break; done
  echo "SSH port open $((SECONDS - t0)) s after the kernel was started"
  sleep 45        # let start-up finish
fi
(iperf3 -s -1 -p ${PORT:-5201} > /dev/null 2>&1) &
sleep 1
h0=$(nstat -az TcpInSegs 2>/dev/null | awk '/TcpInSegs/ {print $2}')
timeout 300 $S '
IF=$(ls /sys/class/net | grep -v "^lo$" | head -1)
C=$(find /sys/devices -name hw_counters 2>/dev/null | head -1)
[ -n "$C" ] || { echo "no hw_counters file: this kernel or bitstream has no counters"; exit 1; }
uname -v; uptime
cat $C > /tmp/c0; d0=$(cat /sys/class/net/$IF/statistics/tx_packets); r0=$(awk "/^Tcp: [0-9]/ {print \$13}" /proc/net/snmp)
iperf3 -c '$H' -p ${PORT:-5201} -t '$secs' | tail -4 | head -2
cat $C > /tmp/c1; d1=$(cat /sys/class/net/$IF/statistics/tx_packets); r1=$(awk "/^Tcp: [0-9]/ {print \$13}" /proc/net/snmp)
echo "driver: frames handed to the hardware   $((d1 - d0))   (TCP retransmitted segments among them: $((r1 - r0)))"
paste /tmp/c0 /tmp/c1 | awk "{printf \"hardware: %-18s %d\n\", \$1, (\$4 - \$2 + 65536) % 65536}"
'
h1=$(nstat -az TcpInSegs 2>/dev/null | awk '/TcpInSegs/ {print $2}')
echo "host: TCP segments received from all peers   $((h1 - h0))"
