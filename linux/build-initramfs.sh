#!/bin/bash
# Build out/initramfs.cpio.gz from Debian's unmodified riscv64 busybox-static.
# No root needed (the only device node, /dev/console, comes from devtmpfs,
# which /init mounts itself).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
DEB=busybox-static_1.37.0-6+b9_riscv64.deb          # Debian 13 "trixie", main
SHA=4add476d2b185c5b487c285b38d790f0881a7e4a8e2ddde835f917e770eb8633   # from the signed trixie Packages index
URL=https://deb.debian.org/debian/pool/main/b/busybox/$DEB
dl=$here/dl/debian; work=$here/initramfs/work; root=$here/initramfs/root

mkdir -p "$dl" "$here/out"
[ -f "$dl/$DEB" ] || curl -fL -o "$dl/$DEB" "$URL"
echo "$SHA  $dl/$DEB" | sha256sum -c -

rm -rf "$work" "$root"
mkdir -p "$work/busybox-static" "$root"/{bin,sbin,dev,proc,sys,tmp,run,mnt,root,etc,usr/bin,usr/sbin}
dpkg -x "$dl/$DEB" "$work/busybox-static"          # untrusted archive: own directory
install -m 755 "$work/busybox-static/usr/bin/busybox" "$root/bin/busybox"
ln -s busybox "$root/bin/sh"
install -m 755 "$here/initramfs/init" "$root/init"
echo "legend64" > "$root/etc/hostname"
printf 'root::0:0:root:/root:/bin/sh\n' > "$root/etc/passwd"
printf 'root:x:0:\n' > "$root/etc/group"

# deterministic archive, everything owned by root
( cd "$root" && find . -print0 | LC_ALL=C sort -z \
    | cpio --null -o -H newc -R 0:0 --reproducible 2>/dev/null ) | gzip -9n > "$here/out/initramfs.cpio.gz"
ls -l "$here/out/initramfs.cpio.gz"
file "$root/bin/busybox" | sed 's/^/busybox: /'
