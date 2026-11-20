#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Run one image on PicoRV32 and pico_legend and compare every register write and memory write, in order.
# usage: lockstep_pico.sh <hex> [plusargs for the new core only, e.g. +nola]   -> prints "OK <n events>" or the first difference
cd "$(dirname "$0")/.."
h=$1; shift
t=$(mktemp -d)
./build/sim/pico_ref +hex=$h +quiet +trace=$t/ref.tr +max_cycles=20000000 | grep '@@' > $t/ref.out
./build/sim/pico_dut +hex=$h +quiet +trace=$t/dut.tr +max_cycles=20000000 "$@" | grep '@@' > $t/dut.out
ok=1
for k in R M; do
  grep "^$k" $t/ref.tr > $t/ref.$k; grep "^$k" $t/dut.tr > $t/dut.$k
  if ! cmp -s $t/ref.$k $t/dut.$k; then ok=0; echo "DIFF($k) $h:"; diff $t/ref.$k $t/dut.$k | head -6; fi
done
r=$(sed 's/cycles=.*//' $t/ref.out); d=$(sed 's/cycles=.*//' $t/dut.out)
[ "$r" = "$d" ] || { ok=0; echo "END DIFF $h: ref[$r] dut[$d]"; }
[ $ok = 1 ] && echo "OK $(basename $h) events=$(wc -l < $t/ref.tr) ref[$(cat $t/ref.out)] dut[$(cat $t/dut.out)]"
rm -rf $t
[ $ok = 1 ]
