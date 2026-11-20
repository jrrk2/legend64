#!/bin/bash
# Build the fable64 kernel: mainline linux-6.18.64, unmodified source,
# config kernel/fable64_defconfig.  No root needed.
#
#   ./build-kernel.sh                  build  -> out/Image
#   ./build-kernel.sh regen-defconfig  regenerate kernel/fable64_defconfig from
#                                      kernel/fable64.fragment (allnoconfig + fragment)
#   ./build-kernel.sh menuconfig       edit the config, then save it back as defconfig
#
# Optional out-of-tree Ethernet driver ("fable,eth"):
#   if kernel/patches/fable-eth.patch exists it is applied (-p1) to the source
#   tree before building and CONFIG_FABLE_ETH=y is added to the config; extra
#   config lines the driver needs can go in kernel/patches/fable-eth.config.
#   If the patch is later changed or removed, the old one is reverted first.
#   kernel/make-fable-eth-patch.sh creates such a patch from a single fable_eth.c.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
KVER=6.18.64
KSHA=020d45510c539972e6f14c5c71566878d3b7ef56fb082b3e09134f2ebaade562   # from kernel.org sha256sums.asc
URL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
JOBS=${JOBS:-12}                      # shared machine: never more than 12

tarball=$here/dl/linux-$KVER.tar.xz
src=$here/kernel/src/linux-$KVER
build=$here/kernel/build
patch_in=$here/kernel/patches/fable-eth.patch
patch_cfg=$here/kernel/patches/fable-eth.config
patch_applied=$here/kernel/src/.fable-eth.applied.patch

# cross toolchain unpacked (dpkg -x) from Ubuntu gcc-riscv64-linux-gnu under tools/root
export PATH=$here/tools/root/usr/bin:$PATH
export LD_LIBRARY_PATH=$here/tools/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

if [ ! -d "$src" ]; then
    mkdir -p "$here/dl" "$here/kernel/src"
    [ -f "$tarball" ] || curl -fL -o "$tarball" "$URL"
    echo "$KSHA  $tarball" | sha256sum -c -
    tar -C "$here/kernel/src" -xf "$tarball"
    rm -f "$patch_applied"
fi

# ---- optional fable,eth driver patch ----------------------------------------
if [ -f "$patch_applied" ] && { [ ! -f "$patch_in" ] || ! cmp -s "$patch_in" "$patch_applied"; }; then
    echo "== reverting previously applied fable-eth patch"
    patch -d "$src" -p1 -R -E --no-backup-if-mismatch < "$patch_applied"
    rm -f "$patch_applied"
fi
if [ -f "$patch_in" ] && [ ! -f "$patch_applied" ]; then
    echo "== applying $patch_in"
    patch -d "$src" -p1 --dry-run < "$patch_in" > /dev/null
    patch -d "$src" -p1 --no-backup-if-mismatch < "$patch_in"
    cp "$patch_in" "$patch_applied"
fi

mk() { make -C "$src" O="$build" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- "$@"; }
mkdir -p "$build" "$here/out"

case "${1:-build}" in
regen-defconfig)
    mk KCONFIG_ALLCONFIG="$here/kernel/fable64.fragment" allnoconfig
    mk savedefconfig
    cp "$build/defconfig" "$here/kernel/fable64_defconfig"
    echo "wrote kernel/fable64_defconfig"
    exit 0 ;;
menuconfig)
    cp "$here/kernel/fable64_defconfig" "$build/.config"
    mk olddefconfig; mk menuconfig; mk savedefconfig
    cp "$build/defconfig" "$here/kernel/fable64_defconfig"
    echo "wrote kernel/fable64_defconfig (kernel/fable64.fragment is NOT updated)"
    exit 0 ;;
build) ;;
*)  echo "usage: $0 [build|regen-defconfig|menuconfig]" >&2; exit 2 ;;
esac

cp "$here/kernel/fable64_defconfig" "$build/.config"
if [ -f "$patch_applied" ]; then
    echo "CONFIG_FABLE_ETH=y" >> "$build/.config"
    [ -f "$patch_cfg" ] && cat "$patch_cfg" >> "$build/.config"
fi
mk olddefconfig
if [ -f "$patch_applied" ] && ! grep -q '^CONFIG_FABLE_ETH=y' "$build/.config"; then
    echo "ERROR: patch applied but CONFIG_FABLE_ETH=y did not survive olddefconfig" >&2
    echo "       (Kconfig symbol missing or its dependencies are not met)" >&2
    exit 1
fi
mk -j"$JOBS" Image
cp "$build/arch/riscv/boot/Image" "$here/out/Image"
cp "$build/.config" "$here/out/kernel.config"
cp "$build/System.map" "$here/out/System.map"
echo
echo "kernel:  $(strings "$here/out/Image" | grep -m1 '^Linux version')"
ls -l "$here/out/Image"
# memory footprint when loaded at 0x80200000 (must stay below the DTB that
# OpenSBI fw_jump relocates to 0x82200000)
end=$(awk '$3=="_end"{print $1}' "$build/System.map"); start=$(awk '$3=="_start"{print $1}' "$build/System.map")
printf 'footprint (_start.._end): %d bytes -> physical 0x80200000..0x%x\n' \
    $((0x$end - 0x$start)) $((0x80200000 + 0x$end - 0x$start))
