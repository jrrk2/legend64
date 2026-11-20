#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build OpenSBI (third_party/opensbi, the "generic" platform) -> out/fw_jump.bin.
# fw_jump expects the kernel at 0x80200000 and takes the device tree address in a1.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-12}
# cross toolchain unpacked (dpkg -x) from Ubuntu gcc-riscv64-linux-gnu under tools/root
export PATH=$here/tools/root/usr/bin:$PATH
export LD_LIBRARY_PATH=$here/tools/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
mkdir -p "$here/out"
make -C "$here/../third_party/opensbi" O="$here/opensbi-build" PLATFORM=generic CROSS_COMPILE=riscv64-linux-gnu- \
     FW_PAYLOAD=n FW_DYNAMIC=n -j"$JOBS"
cp "$here/opensbi-build/platform/generic/firmware/fw_jump.bin" "$here/out/fw_jump.bin"
ls -l "$here/out/fw_jump.bin"
