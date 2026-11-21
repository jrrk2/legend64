# SPDX-License-Identifier: Apache-2.0
# vivado_endpoints.tcl <dcp> <timing.xdc> <clock net> <outdir>: every endpoint of one clock in a
# json2dcp checkpoint, setup at Vivado's slow and fast corners and hold at the fast corner, as
# TSV for timing_fit.py.
set dcp [lindex $argv 0]; set xdc [lindex $argv 1]; set cn [lindex $argv 2]; set o [lindex $argv 3]
open_checkpoint $dcp
read_xdc -unmanaged $xdc
set clk [get_clocks -of [get_nets $cn]]
proc dump {file paths} {
  set f [open $file w]
  puts $f "endpoint\tstartpoint\tslack\tdatapath\tlogic\tnet\tlevels\tskew\trequirement"
  foreach p $paths {
    puts $f "[get_property ENDPOINT_PIN $p]\t[get_property STARTPOINT_PIN $p]\t[get_property SLACK $p]\t[get_property DATAPATH_DELAY $p]\t[get_property DATAPATH_LOGIC_DELAY $p]\t[get_property DATAPATH_NET_DELAY $p]\t[get_property LOGIC_LEVELS $p]\t[get_property SKEW $p]\t[get_property REQUIREMENT $p]"
  }
  close $f
}
foreach {name slow fast} {slow min_max none fast none min_max} {
  config_timing_corners -corner Slow -delay_type $slow
  config_timing_corners -corner Fast -delay_type $fast
  dump $o/setup_$name.tsv [get_timing_paths -from $clk -to $clk -setup -max_paths 100000 -nworst 1 -unique_pins]
}
config_timing_corners -corner Slow -delay_type min_max
config_timing_corners -corner Fast -delay_type min_max
dump $o/hold.tsv [get_timing_paths -from $clk -to $clk -hold -max_paths 100000 -nworst 1 -unique_pins]
puts "PERIOD [get_property PERIOD $clk]"
exit
