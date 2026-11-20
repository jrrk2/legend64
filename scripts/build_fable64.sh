#!/bin/bash
# Build the fable64 simulator: build/sim/fable64
set -e
cd "$(dirname "$0")/.."
mkdir -p build/sim
W="-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-INITIALDLY -Wno-VARHIDDEN -Wno-IMPORTSTAR -Wno-UNSIGNED -Wno-CMPCONST"
verilator --binary -O3 --x-assign 0 --x-initial 0 $W --top-module tb -Mdir build/sim/fable64_obj -o ../fable64 tb/tb_fable64.sv rtl/fable64.sv rtl/fable64_rvc.sv rtl/fable64_fpu.sv > build/sim/fable64.log 2>&1 || { grep -A6 "%Error" build/sim/fable64.log | head -60; exit 1; }
