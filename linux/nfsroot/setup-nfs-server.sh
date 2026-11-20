#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# ============================================================================
#  RUN AS ROOT (sudo ./setup-nfs-server.sh) - not run by the build automation.
# ============================================================================
# Export the Debian tree to the board (192.168.1.51) from this host
# (192.168.1.176) with the in-kernel NFS server.
set -euo pipefail
TARGET=${TARGET:-/srv/nfs/fable64}
BOARD_IP=${BOARD_IP:-192.168.1.51}
LINE="$TARGET $BOARD_IP(rw,sync,no_root_squash,no_subtree_check)"

[ "$(id -u)" = 0 ] || { echo "must be run as root" >&2; exit 1; }
[ -d "$TARGET/etc" ] || { echo "$TARGET: no Debian tree" >&2; exit 1; }
[ ! -e "$TARGET/debootstrap" ] || echo "WARNING: $TARGET/debootstrap exists - the second stage has not been run yet" >&2

apt-get install -y nfs-kernel-server
# no_root_squash: the board's root must be root on its own root file system.
# NFSv3 over TCP is what the kernel command line asks for (nfsroot=...,vers=3,tcp).
grep -qxF "$LINE" /etc/exports || echo "$LINE" >> /etc/exports
systemctl enable --now nfs-kernel-server
exportfs -ra
exportfs -v | grep -A1 -F "$TARGET" || true
echo
echo "If a firewall is active, allow $BOARD_IP to reach TCP/UDP 111 and 2049 and the mountd port"
echo "(rpcinfo -p | grep mountd).  Check from another machine:  showmount -e 192.168.1.176"
