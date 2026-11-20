#!/bin/bash
# ============================================================================
#  RUN AS ROOT for the real tree (sudo ./second-stage-qemu.sh).
#  (It also runs unprivileged on a fakeroot-made rehearsal tree with
#   SECURITY_MODEL=mapped-xattr - that is how it was tested.)
# ============================================================================
# Stage 2 of the Debian NFS root, done under QEMU instead of on the 25 MHz
# board: QEMU "virt" with the fable64 kernel and the hardware-limited CPU mounts
# the tree as its root file system over virtio-9p and runs
# /fable64-second-stage.sh as init (debootstrap --second-stage + configuration),
# then powers off.
#
#   second-stage-qemu.sh            run the second stage
#   second-stage-qemu.sh boot       afterwards: boot the finished tree (systemd,
#                                   login on the serial console) to check it
# Environment: TARGET (default /srv/nfs/fable64), SECURITY_MODEL (default
# passthrough = real ownership, needs root), QEMU_EXTRA (extra QEMU arguments).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
TARGET=${TARGET:-/srv/nfs/fable64}
SECURITY_MODEL=${SECURITY_MODEL:-passthrough}
mode=${1:-second-stage}

if [ "$SECURITY_MODEL" = passthrough ] && [ "$(id -u)" != 0 ]; then
    echo "must be run as root (9p passthrough needs real root to create root-owned files)" >&2; exit 1
fi
[ -d "$TARGET/etc" ] || { echo "$TARGET: no Debian tree (run make-nfsroot.sh first)" >&2; exit 1; }

root9p="root=rootfs rootfstype=9p rootflags=trans=virtio,version=9p2000.L,msize=262144 rw"
case "$mode" in
second-stage)
    install -m 755 "$here/target/fable64-second-stage.sh" "$TARGET/fable64-second-stage.sh"
    args="console=ttyS0,115200 earlycon $root9p init=/fable64-second-stage.sh fable.epoch=$(date +%s)" ;;
boot)
    args="console=ttyS0,115200 earlycon $root9p" ;;
*)  echo "usage: $0 [second-stage|boot]" >&2; exit 2 ;;
esac

# shellcheck disable=SC2086
exec "$here/../run-qemu.sh" append "$args" \
    -fsdev local,id=rootfs,path="$TARGET",security_model="$SECURITY_MODEL" \
    -device virtio-9p-device,fsdev=rootfs,mount_tag=rootfs \
    -device virtio-rng-device ${QEMU_EXTRA:-}
