#!/bin/bash
# Build the two PicoRV32-interface simulators: build/sim/pico_ref (PicoRV32) and build/sim/pico_dut (pico_legend).
set -e
cd "$(dirname "$0")/.."
W="-Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNUSED -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD -Wno-GENUNNAMED -Wno-CASEOVERLAP"
verilator --binary -O3 --x-assign 0 --x-initial 0 $W -DREF --top-module tb -Mdir build/sim/pico_ref_obj -o ../pico_ref tb/tb_pico.sv ref/picorv32/picorv32.v > build/sim/pico_ref.log 2>&1 || { tail -30 build/sim/pico_ref.log; exit 1; }
verilator --binary -O3 --x-assign 0 --x-initial 0 $W --top-module tb -Mdir build/sim/pico_dut_obj -o ../pico_dut tb/tb_pico.sv rtl/pico_legend.v > build/sim/pico_dut.log 2>&1 || { tail -30 build/sim/pico_dut.log; exit 1; }
