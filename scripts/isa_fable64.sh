#!/bin/bash
# Run ISA tests on fable64. usage: isa_fable64.sh [-v] [extra plusargs, e.g. +jitter]
#   default: the machine-level "p" environment images; -v: the virtual-memory "v" environment images
cd "$(dirname "$0")/.."
pat='build/sw/rv64/isa/*.hex'; skip='-v-'
if [ "${1:-}" = "-v" ]; then pat='build/sw/rv64/isa/*-v-*.hex'; skip='@none@'; shift; fi
run() { r=$(./build/sim/fable64 +hex=$1 +tohost=$(cat ${1%.hex}.tohost) +quiet +max_cycles=5000000 "${@:2}" | grep '@@'); case "$r" in *"exit code=0 "*) echo PASS;; *) echo "FAIL $(basename $1 .hex): $r";; esac; }
export -f run
ls $pat | grep -v -- "$skip" | xargs -P 12 -I{} bash -c "run {} $*" | sort | uniq -c
