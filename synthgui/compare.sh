#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Build and run the RTL-against-netlist comparison written by netlist_compare.py:
#   compare.sh <directory> [verilator -D defines and +plusargs for the run]
# synthgui's cell library has only an empty RAMB36E1, so the behavioural one beside this script
# is used and the library is copied without its own.
set -u
cd "$(dirname "$0")/.."
D=$1; shift
DEFS=$(for a in "$@"; do case $a in -D*) echo "$a";; esac; done)
PLUS=$(for a in "$@"; do case $a in +*) echo "$a";; esac; done)
V=tools/verilator/bin/verilator
W="-Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-MULTIDRIVEN -Wno-UNOPTFLAT"
R="fpga/rtl/legend64_soc.sv fpga/rtl/legend_cache.sv fpga/rtl/legend_ram.sv fpga/rtl/legend_uart16550.sv fpga/rtl/legend_plic.sv fpga/rtl/legend_eth.sv fpga/rtl/legend_flash.sv rtl/legend64.sv rtl/legend64_rvc.sv rtl/legend64_fpu.sv"
XC7=${SYNTHGUI:-$HOME/synthgui}/xc7
python3 -c "
import re, sys
s = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write(re.sub(r'\nmodule RAMB36E1\b.*?\nendmodule', '\n', s, count=1, flags=re.S))" $XC7/cells_sim.v $D/cells_sim_noram.v
S="$D/tb.sv $R $D/soc_map_ren.v synthgui/ramb36e1_beh.v $D/cells_sim_noram.v $XC7/cells_xtra.v"
# names the RTL does not have (the mapper's renamed or duplicated registers) are dropped
for i in $(seq 1 40); do
  $V --lint-only --timing $W $DEFS --top-module tb $S > $D/lint.log 2>&1 && break
  python3 - "$D" <<'PY' || { grep '%Error' $D/lint.log | head -5; exit 1; }
import re, sys
D = sys.argv[1]
bad = set(int(m) for m in re.findall(r'%Error[^:]*: [^:]*tb\.sv:(\d+):', open(D + '/lint.log').read()))
L = open(D + '/tb.sv').read().split('\n')
keep = [l for i, l in enumerate(L, 1) if not (i in bad and 'bad(' in l)]
if len(keep) == len(L): sys.exit(1)
open(D + '/tb.sv', 'w').write('\n'.join(keep))
PY
done
echo "$(grep -c 'bad(' $D/tb.sv) checks after dropping names the RTL lacks"
$V --binary -O1 --x-assign 0 --x-initial 0 -j 8 $W $DEFS --top-module tb -Mdir $D/vobj -o ../cmp $S > $D/build.log 2>&1 || { grep -A3 '%Error' $D/build.log | head; exit 1; }
$D/cmp $PLUS
