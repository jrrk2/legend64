#!/bin/bash
# Keep the shared VC707 for <minutes> (default 30) without reloading it, logging a ping to the
# running system every 10 s: for when someone is working on its console.
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_hold.sh [minutes]
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
end=$((SECONDS + ${1:-30} * 60))
while [ $SECONDS -lt $end ]; do
  echo "$(date +%T) $(ping -c 1 -W 1 192.168.1.51 | grep -E 'time=|100% packet loss' | sed 's/.*\(time=.*\)/\1/; s/.*100% packet loss.*/LOST/')"
  sleep 10
done
