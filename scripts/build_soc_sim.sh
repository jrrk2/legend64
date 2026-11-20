#!/bin/bash
# Build a simulator of the SoC: build_soc_sim.sh <testbench.sv> <output name>
set -e
cd "$(dirname "$0")/.."
# a Verilator built from source under tools/ if there is one (5.032 as packaged faults on some builds)
V=verilator; [ -x tools/verilator/bin/verilator ] && V=tools/verilator/bin/verilator
W="-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-INITIALDLY -Wno-VARHIDDEN -Wno-IMPORTSTAR -Wno-UNSIGNED -Wno-CMPCONST -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-STMTDLY -Wno-INFINITELOOP -Wno-SELRANGE"
$V --binary -O3 --x-assign 0 --x-initial 0 $W --top-module tb -Mdir build/sim/$2_obj -o ../$2 $1 \
  fpga/rtl/fable64_soc.sv fpga/rtl/fable_cache.sv fpga/rtl/fable_ram.sv fpga/rtl/fable_uart16550.sv fpga/rtl/fable_plic.sv \
  fpga/rtl/fable_eth.sv rtl/fable64.sv rtl/fable64_rvc.sv rtl/fable64_fpu.sv > build/sim/$2.log 2>&1 || { grep -A6 "%Error" build/sim/$2.log | head -40; exit 1; }
