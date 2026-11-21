#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build and run the unit test of the interrupt controller (fpga/tb/tb_plic.sv): random register
# traffic and source lines against a behavioural model.
set -e
cd "$(dirname "$0")/.."
V=verilator; [ -x tools/verilator/bin/verilator ] && V=tools/verilator/bin/verilator
mkdir -p build/sim
$V --binary -O2 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-UNOPTFLAT -Wno-TIMESCALEMOD -Wno-DECLFILENAME \
  -Wno-BLKSEQ -Wno-INITIALDLY --top-module tb -Mdir build/sim/plic_obj -o ../plic_tb fpga/tb/tb_plic.sv fpga/rtl/legend_plic.sv \
  > build/sim/plic_tb.log 2>&1 || { grep -A6 "%Error" build/sim/plic_tb.log | head -40; exit 1; }
for seed in 1 2 3; do ./build/sim/plic_tb +seed=$seed | grep "@@"; done
