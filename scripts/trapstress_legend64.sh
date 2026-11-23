#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Trap entry under interrupts and page faults (sw/rv64/trapstress.S), with the data memory slower
# than the instruction memory by 0..4 cycles and with random bus timing.
# usage: trapstress_legend64.sh [seeds=8]
cd "$(dirname "$0")/.."
make -s -C sw/rv64 stress || exit 1
h=build/sw/rv64/trapstress.hex
a="+hex=$h +tohost=$(cat ${h%.hex}.tohost) +quiet +max_cycles=30000000"
run() { r=$(./build/sim/legend64 $a "$@" | grep '@@'); case "$r" in *"exit code=0 "*) echo PASS;; *) echo "FAIL $*: $r";; esac; }
{ for d in 0 1 2 3 4; do run +dlat=$d & done
  for s in $(seq 1 ${1:-8}); do run +jitter +verilator+seed+$s & done
  wait; } | sort | uniq -c
