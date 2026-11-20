#!/bin/bash
# Network benchmark of the Debian NFS-root system on the shared VC707: JTAG-load the bitstream,
# send OpenSBI, the kernel and the NFS-root device tree, wait for the system's SSH server, and
# over SSH (as the invoking user, by key) run iperf3 each way against this host, check 8 MB of
# data each way with SHA-256, time a cold read of a large file over NFS and one password hash at
# Debian's default cost, and print the interface's counters. The serial console is left alone.
# Must run under the board lock:
#   ~/synthgui-work/mapper-bisect/board-run.sh rv64g "<purpose>" -- fpga/scripts/board_nfs_bench.sh <bitstream> [dtb]
# With no bitstream ("-") the running system is measured as it is.
# JTAG load only; the BPI flash is never written.
set -u
[ -n "${BOARD_LOCK_HELD:-}" ] || { echo "run this through board-run.sh" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
bit=${1:?bitstream, or - to measure the running system}
L=$root/linux/out
dtb=${2:-$L/fable64-vc707.dtb}
B=192.168.1.51; H=192.168.1.176
big=/var/lib/apt/lists/deb.debian.org_debian_dists_trixie_main_binary-riscv64_Packages
cold=/var/lib/apt/lists/deb.debian.org_debian_dists_trixie_main_i18n_Translation-en
tree=/srv/nfs/fable64
trap 'kill $(jobs -p) 2>/dev/null' EXIT
ctl=$(mktemp -u /tmp/fable-ssh-XXXXXX)
S="ssh -o BatchMode=yes -o ConnectTimeout=90 -o StrictHostKeyChecking=accept-new -o ControlMaster=auto -o ControlPath=$ctl -o ControlPersist=120 $B"

if [ "$bit" != - ]; then
  $HOME/synthgui/build-deps/prefix/bin/openFPGALoader --cable digilent --freq 15000000 "$bit" 2>&1 | tr "\r" "\n" | grep -E "isc_done" | tail -1
  for i in $(seq 150); do ping -c 1 -W 1 $B > /dev/null && break; sleep 1; done
  echo "monitor answered ping after ~$i s"
  sleep 2
  python3 "$here/netload.py" $root/tools/qemu/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin@80000000 \
      $L/Image@80200000 $dtb@86000000 --jump 80000000 --arg 86000000 2>&1 | tail -1
  t0=$SECONDS
  for i in $(seq 120); do sleep 5; timeout 3 bash -c "echo > /dev/tcp/$B/22" 2>/dev/null && break; done
  echo "SSH port open $((SECONDS - t0)) s after the kernel was started"
  sleep 20
fi

(iperf3 -s -1 -p 5201 > /dev/null 2>&1) &
(iperf3 -s -1 -p 5202 > /dev/null 2>&1) &
(nc -l 5003 | sha256sum | cut -d' ' -f1 > $ctl.tx) &
(head -c 8000000 $tree$big | nc -N -l 5004) &
want=$(head -c 8000000 $tree$big | sha256sum | cut -d' ' -f1)
sleep 1
timeout 600 $S "uname -v; grep ' / ' /proc/mounts | cut -d' ' -f4 | cut -c1-60; uptime
echo '== iperf3, board sends';    iperf3 -c $H -p 5201 -t 10 | tail -4 | head -2
echo '== iperf3, board receives'; iperf3 -c $H -p 5202 -t 10 -R | tail -4 | head -2
echo '== 8 MB to the host';       head -c 8000000 $big > /dev/tcp/$H/5003
echo '== 8 MB from the host';     sha256sum < /dev/tcp/$H/5004
echo '== cold NFS read';          dd if=$cold of=/dev/null bs=64k 2>&1 | tail -1
echo '== one yescrypt password hash'; ( time -p perl -e 'crypt(q(test), q(\$y\$j9T\$abcdefghijklmnop\$))' ) 2>&1 | tr '\n' ' '; echo
ip -s -s link show end0 | sed -n 3,10p
grep -E '^Tcp:' /proc/net/snmp | tail -1"
sleep 1
echo "8 MB to the host arrived as $(cat $ctl.tx 2>/dev/null)"
echo "expected both ways         $want"
rm -f $ctl.tx
