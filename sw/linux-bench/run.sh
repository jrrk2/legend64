#!/bin/sh
# CoreMark, Dhrystone 2.1 and Whetstone, one after another, with what the machine is
cd "$(dirname "$0")"
uname -n -r -m; grep -m1 isa /proc/cpuinfo; uptime
echo "== CoreMark";  ./coremark | grep -E 'CoreMark Size|Total time|Iterations/Sec|Iterations  |Correct|ERROR|CoreMark 1.0'
echo "== Dhrystone 2.1"; echo ${DHRY_RUNS:-3000000} | ./dhrystone | grep -E 'Microseconds|Dhrystones per Second|too small'
echo "== Whetstone (double precision)"; ./whetstone ${WHET_LOOPS:-30000} | grep -E 'Loops|MIPS'
