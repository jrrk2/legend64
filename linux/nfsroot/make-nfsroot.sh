#!/bin/bash
# ============================================================================
#  RUN AS ROOT (sudo ./make-nfsroot.sh) - not run by the build automation.
# ============================================================================
# Stage 1 of the Debian riscv64 NFS root: debootstrap --foreign on this x86
# host.  riscv64 is a release architecture of Debian 13 "trixie" (current
# stable), so the normal mirror and the normal debian-archive-keyring are used
# (no debian-ports).
#
# Afterwards:
#   2. sudo ./second-stage-qemu.sh         (finishes the install under QEMU, ~10 min)
#   3. sudo ./setup-nfs-server.sh          (exports the tree to the board)
#   4. boot the board with out/fable64-vc707.dtb
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
TARGET=${TARGET:-/srv/nfs/fable64}
SUITE=${SUITE:-trixie}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
INCLUDE=${INCLUDE:-systemd-timesyncd,iputils-ping,netbase,ca-certificates}

[ "$(id -u)" = 0 ] || { echo "must be run as root" >&2; exit 1; }
if [ -e "$TARGET/etc" ] || [ -e "$TARGET/debootstrap" ]; then
    echo "$TARGET already contains a tree - remove it first if you really want to start over" >&2; exit 1
fi

# debootstrap + keyring: use the system ones if installed, else install them,
# else fall back to the copies unpacked under linux/tools/root.
if ! command -v debootstrap >/dev/null; then
    apt-get install -y debootstrap debian-archive-keyring || true
fi
if command -v debootstrap >/dev/null && [ -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
    DEBOOTSTRAP=(debootstrap); KEYRING=/usr/share/keyrings/debian-archive-keyring.gpg
else
    T=$here/../tools/root
    DEBOOTSTRAP=(env DEBOOTSTRAP_DIR="$T/usr/share/debootstrap" "$T/usr/sbin/debootstrap")
    KEYRING=$T/usr/share/keyrings/debian-archive-keyring.gpg
fi

mkdir -p "$TARGET"
"${DEBOOTSTRAP[@]}" --foreign --arch=riscv64 --keyring="$KEYRING" \
    --include="$INCLUDE" "$SUITE" "$TARGET" "$MIRROR"
install -m 755 "$here/target/fable64-second-stage.sh" "$TARGET/fable64-second-stage.sh"

echo
echo "Stage 1 done in $TARGET.  Next:  sudo $here/second-stage-qemu.sh"
