#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# retime_bit.sh <open-flow work dir> <divide> <out.bit>
# The routed design in the work directory with the core clock's MMCM output divider changed
# (synthgui's scripts/mmcm_retime.py on the routed FASM), as a bitstream: the same placement and
# routing at another clock, 1000 MHz / divide. For finding on the board how fast a route really
# goes. The design still believes its built-in CLK_HZ: the monitor's UART baud rate is off by the
# ratio, and Linux needs a device tree with the real TIMEBASE_HZ and the UART's clock-frequency
# scaled by the same ratio (retime_dtb below).
set -eu
SG=${SYNTHGUI:-$HOME/synthgui}
w=$1; d=$2; out=$3
DB=$SG/deps/prjxray-db/virtex7; P=xc7vx485tffg1761-2
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
python3 $SG/scripts/mmcm_retime.py --fasm $w/legend64_vc707.fasm --out $t/r.fasm --routed $w/legend64_vc707_routed.json \
    --placement $w/legend64_vc707_placement.json --cell u_mmcm --output CLKOUT0 --divide $d
QT_QPA_PLATFORM=offscreen $SG/build/synthgui --tool fasm2frames --part $P --db-root $DB $t/r.fasm $t/r.frames
$SG/build-deps/prjxray/tools/xc7frames2bit --part_file $DB/$P/part.yaml --part_name $P --frm_file $t/r.frames --output_file $out
ls -l $out | cut -c25-
