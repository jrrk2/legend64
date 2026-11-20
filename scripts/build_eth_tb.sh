#!/bin/bash
# Build and run the unit test of the Ethernet MAC front end (fpga/tb/tb_eth.sv):
#   build_eth_tb.sh              the normal build, three runs
#   build_eth_tb.sh small        with a small receive FIFO, so that it overflows
set -e
cd "$(dirname "$0")/.."
V=verilator; [ -x tools/verilator/bin/verilator ] && V=tools/verilator/bin/verilator
mkdir -p build/sim
if [ "${1:-}" = small ]; then name=eth_tb_small; def=-DRX_FIFO_AW=8; else name=eth_tb; def=; fi
$V --binary -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC $def --top-module tb \
  -Mdir build/sim/${name}_obj -o ../$name fpga/tb/tb_eth.sv fpga/rtl/legend_eth.sv > build/sim/$name.log 2>&1 \
  || { grep -A6 "%Error" build/sim/$name.log | head -40; exit 1; }
if [ "${1:-}" = small ]; then
  build/sim/$name +frames=1500 +slowmem +verilator+seed+1 | grep -E 'ERROR|receive:|over 1518|PASS|FAIL'
  build/sim/$name +frames=1500 +slowmem +slowrx +verilator+seed+2 | grep -E 'ERROR|receive:|over 1518|PASS|FAIL'
else
  build/sim/$name +frames=3000 +verilator+seed+1 | grep -E 'ERROR|transmit:|receive:|PASS|FAIL'
  build/sim/$name +frames=3000 +verilator+seed+2 | grep -E 'ERROR|PASS|FAIL'
  build/sim/$name +frames=1500 +slowrx +verilator+seed+3 | grep -E 'ERROR|receive:|PASS|FAIL'
fi
