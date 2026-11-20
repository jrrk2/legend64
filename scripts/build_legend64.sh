#!/bin/bash
# Build the legend64 simulator: build/sim/legend64
set -e
cd "$(dirname "$0")/.."
mkdir -p build/sim
W="-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-INITIALDLY -Wno-VARHIDDEN -Wno-IMPORTSTAR -Wno-UNSIGNED -Wno-CMPCONST"
verilator --binary -O3 --x-assign 0 --x-initial 0 $W --top-module tb -Mdir build/sim/legend64_obj -o ../legend64 tb/tb_legend64.sv rtl/legend64.sv rtl/legend64_rvc.sv rtl/legend64_fpu.sv > build/sim/legend64.log 2>&1 || { grep -A6 "%Error" build/sim/legend64.log | head -60; exit 1; }
