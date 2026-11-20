#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build a simulator of the SoC: build_soc_sim.sh <testbench.sv> <output name>
set -e
cd "$(dirname "$0")/.."
# a Verilator built from source under tools/ if there is one (5.032 as packaged faults on some builds)
V=verilator; [ -x tools/verilator/bin/verilator ] && V=tools/verilator/bin/verilator
W="-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-INITIALDLY -Wno-VARHIDDEN -Wno-IMPORTSTAR -Wno-UNSIGNED -Wno-CMPCONST -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-STMTDLY -Wno-INFINITELOOP -Wno-SELRANGE"
$V --binary -O3 --x-assign 0 --x-initial 0 $W --top-module tb -Mdir build/sim/$2_obj -o ../$2 $1 \
  fpga/rtl/legend64_soc.sv fpga/rtl/legend_cache.sv fpga/rtl/legend_ram.sv fpga/rtl/legend_uart16550.sv fpga/rtl/legend_plic.sv \
  fpga/rtl/legend_eth.sv fpga/rtl/legend_flash.sv rtl/legend64.sv rtl/legend64_rvc.sv rtl/legend64_fpu.sv > build/sim/$2.log 2>&1 || { grep -A6 "%Error" build/sim/$2.log | head -40; exit 1; }
