#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build CoreMark, Dhrystone 2.1 and Whetstone as static RV64GC Linux programs, for running the
# same binaries on legend64 and on any other RV64GC Linux system it is compared with.
#   sw/linux-bench/build.sh [out dir]      default build/bench
# CoreMark's sources are sw/coremark's with the Linux port here. Dhrystone and Whetstone are
# fetched (and their checksums checked) from the places named below; they are not in this
# repository. No file is compiled with the others' sources in view: the benchmarks' rules.
#
# The C library is Debian's, not the cross compiler's own. Ubuntu builds its riscv64 libraries
# for the RVA23 profile, and a program linked with them stops with an illegal instruction on an
# RV64GC core at the first vector instruction (in memset). Debian's are RV64GC; the three packages
# below are fetched from its archive with the checksums of the signed trixie index and unpacked
# under the output directory, and the programs are linked against them by hand.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd)
out=${1:-$root/build/bench}; mkdir -p "$out/src"
T=$root/linux/tools/root
export PATH=$T/usr/bin:$PATH LD_LIBRARY_PATH=$T/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
CC=riscv64-linux-gnu-gcc

fetch() {  # url file sha256 ("-" to print what it is)
  [ -f "$out/src/$2" ] || curl -fsSL -o "$out/src/$2" "$1"
  if [ "$3" = - ]; then sha256sum "$out/src/$2"; else echo "$3  $out/src/$2" | sha256sum -c - > /dev/null; fi
}

# ---- Debian trixie's RV64GC C library, kernel headers and compiler support library
deb=$out/debian; mkdir -p "$deb/root"
while read -r f sha; do
  b=$(basename "$f")
  fetch "https://deb.debian.org/debian/$f" "$b" "$sha"
  [ -f "$deb/.$b" ] || { dpkg -x "$out/src/$b" "$deb/root"; touch "$deb/.$b"; }   # untrusted archive: its own directory
done <<'PKGS'
pool/main/g/glibc/libc6-dev_2.41-12+deb13u4_riscv64.deb 46ac97192a508a016f454624bcf4ae8ca9ca4589eb41c33b69c2eb24b446084c
pool/main/l/linux/linux-libc-dev_6.12.94-1_all.deb 6183985d8fa4b97d277e8b55b10ad247bd98bc23aa8b531c1f79f05bfbf50997
pool/main/g/gcc-14/libgcc-14-dev_14.2.0-19_riscv64.deb d7811e6b1984251d786b2ca938ae7f21fdf9d0d8364f0bd85b1d87bf17e82db5
PKGS
L=$deb/root/usr/lib/riscv64-linux-gnu; G=$deb/root/usr/lib/gcc/riscv64-linux-gnu/14
# compile: the compiler's own headers, then Debian's; link: a static program, every piece Debian's
ARCH="-march=rv64gc -mabi=lp64d -nostdinc -isystem $($CC -print-file-name=include) -isystem $deb/root/usr/include/riscv64-linux-gnu -isystem $deb/root/usr/include"
link() {  # output, objects...
  o=$1; shift
  $CC -march=rv64gc -mabi=lp64d -static -nostdlib -o "$o" "$L/crt1.o" "$L/crti.o" "$G/crtbeginT.o" "$@" \
      -L"$L" -L"$G" -Wl,--start-group -lm -lc -lgcc -lgcc_eh -Wl,--end-group "$G/crtend.o" "$L/crtn.o"
}

# ---- CoreMark: -O2, the flags reported in its own output
CMF="-O2 -march=rv64gc -mabi=lp64d"
# (the sources are copied beside the Linux port: compiled where they are, their #include
# "core_portme.h" would find the bare-metal port that lives next to them)
rm -rf "$out/src/coremark"; mkdir -p "$out/src/coremark"
cp "$root"/sw/coremark/core_{list_join,main,matrix,state,util}.c "$root/sw/coremark/coremark.h" \
   "$here"/coremark/core_portme.[ch] "$out/src/coremark/"
for c in "$out"/src/coremark/*.c; do $CC -O2 $ARCH -DITERATIONS=0 -DFLAGS_STR="\"$CMF\"" -c "$c" -o "${c%.c}.o"; done
link "$out/coremark" "$out"/src/coremark/*.o

# ---- Dhrystone 2.1 (Reinhold Weicker; C version by Rick Richardson), as kept by Keith Thompson
D=https://raw.githubusercontent.com/Keith-S-Thompson/dhrystone/master/v2.1
fetch $D/dhry.h   dhry.h   "${DHRY_H_SHA:-73be10649f198698cf40a48659d079123e45ef2542d275e6885427e4eb10d503}"
fetch $D/dhry_1.c dhry_1.c "${DHRY_1_SHA:-958069f6ff8fe099ac6121d5f590fa8207bc32a744f138be721bc7358d143cbb}"
fetch $D/dhry_2.c dhry_2.c "${DHRY_2_SHA:-7954383013caead70e8283375b249ecbaa1aaf092b526acbcac3f187a015c108}"
# K&R C; the two files compiled separately, as the benchmark requires, and times() for the clock
DF="-O2 $ARCH -std=gnu89 -w -DTIMES -DHZ=100"
# its own `extern int times ();` contradicts today's <sys/times.h>: that line alone is dropped
sed '/^extern  *int  *times *();/d' "$out/src/dhry_1.c" > "$out/src/dhry_1_linux.c"
$CC $DF -I"$out/src" -c "$out/src/dhry_1_linux.c" -o "$out/src/dhry_1.o"
$CC $DF -c "$out/src/dhry_2.c" -o "$out/src/dhry_2.o"
link "$out/dhrystone" "$out/src/dhry_1.o" "$out/src/dhry_2.o"

# ---- Whetstone, double precision (netlib's C version)
fetch https://www.netlib.org/benchmark/whetstone.c whetstone.c "${WHET_SHA:-333e4ceca042c146f63eec605573d16ae8b07166cbc44a17bec1ea97c6f1efbf}"
$CC -O2 $ARCH -std=gnu89 -w -c "$out/src/whetstone.c" -o "$out/src/whetstone.o"
link "$out/whetstone" "$out/src/whetstone.o"

ls -l "$out"/coremark "$out"/dhrystone "$out"/whetstone
