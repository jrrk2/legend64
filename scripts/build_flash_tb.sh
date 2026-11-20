#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build and run the unit test of the flash bus bridge (fpga/tb/tb_flash.sv) at 50 and 12.5 MHz.
set -e
cd "$(dirname "$0")/.."
V=verilator; [ -x tools/verilator/bin/verilator ] && V=tools/verilator/bin/verilator
mkdir -p build/sim
for hz in 50000000 12500000; do
  name=flash_tb_$hz
  $V --binary -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -DCLK_HZ=$hz --top-module tb \
    -Mdir build/sim/${name}_obj -o ../$name fpga/tb/tb_flash.sv fpga/rtl/legend_flash.sv > build/sim/$name.log 2>&1 \
    || { grep -A6 "%Error" build/sim/$name.log | head -40; exit 1; }
  build/sim/$name | grep -E 'ERROR|Hz:|PASS|FAIL' | head -20
done
