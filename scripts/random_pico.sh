#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Random lockstep campaign: random_pico.sh <first_seed> <count>. Each seed runs with both memory models.
cd "$(dirname "$0")/.."
mkdir -p build/rand
one() { s=$1; h=build/rand/p$s.hex; python3 scripts/gen_random.py $s $h 1500 && scripts/lockstep_pico.sh $h > build/rand/p$s.log 2>&1 && scripts/lockstep_pico.sh $h +nola >> build/rand/p$s.log 2>&1 && rm -f $h && echo PASS || echo "FAIL seed $s"; }
export -f one
seq $1 $(($1+$2-1)) | xargs -P 20 -I{} bash -c 'one {}' | sort | uniq -c
