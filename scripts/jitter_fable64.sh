#!/bin/bash
# For every ISA test, check the retirement trace is identical with and without bus jitter.
# The run ends a few cycles after the tohost write, so one trace may be a few lines longer;
# the shorter must be an exact prefix of the longer.
cd "$(dirname "$0")/.."
mkdir -p build/isatr
one() { h=$1; t=$(basename $h .hex); a="+hex=$h +tohost=$(cat ${h%.hex}.tohost) +quiet +max_cycles=2000000"
  ./build/sim/fable64 $a +trace=build/isatr/$t.a >/dev/null; ./build/sim/fable64 $a +jitter +trace=build/isatr/$t.b >/dev/null
  n=$(( $(wc -l < build/isatr/$t.a) < $(wc -l < build/isatr/$t.b) ? $(wc -l < build/isatr/$t.a) : $(wc -l < build/isatr/$t.b) ))
  d=$(( $(wc -l < build/isatr/$t.a) - $(wc -l < build/isatr/$t.b) )); d=${d#-}
  if [ $d -le 6 ] && cmp -s <(head -n $n build/isatr/$t.a) <(head -n $n build/isatr/$t.b); then echo SAME; else echo "DIFF $t"; fi
  rm -f build/isatr/$t.a build/isatr/$t.b; }
export -f one
ls build/sw/rv64/isa/*.hex | xargs -P 20 -I{} bash -c 'one {}' | sort | uniq -c
