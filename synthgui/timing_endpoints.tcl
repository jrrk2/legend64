# SPDX-License-Identifier: Apache-2.0
# OpenSTA: every endpoint of the core clock in a routed build, for timing_correlate.py. Run in
# the directory synthgui's sta step leaves (<work>/sta), with clocks.tcl holding the create_clock
# lines of its sta.tcl:  grep ^create_clock sta.tcl > clocks.tcl; sta -no_splash -exit timing_endpoints.tcl
read_liberty nextpnr_xc7.lib
read_verilog routed.v
link_design top
source clocks.tcl
set_propagated_clock [all_clocks]
read_sdf routed.sdf
set f [open endpoints_pnr.tsv w]
puts $f "endpoint\tstart\tstart_arr\tarrival\ttarget_clk\trequired\tslack\tnlut\tncarry\tnmux\tnpins"
set pes [find_timing_paths -path_delay max -group_path_count 60000 -unique_paths_to_endpoint -path_group u_sys]
foreach pe $pes {
  set p [$pe path]
  set sp [$p start_path]
  set nl 0; set nc 0; set nm 0
  set pins [$p pins]
  foreach pin $pins {
    if {![$pin is_driver]} continue
    set c [get_property [get_property [$pin instance] cell] name]
    if {[string match *LUT* $c]} {incr nl} elseif {[string match *CARRY* $c]} {incr nc} elseif {[string match *MUXF* $c] || [string match *F7* $c] || [string match *F8* $c]} {incr nm}
  }
  puts $f "[get_full_name [$pe pin]]\t[get_full_name [$sp pin]]\t[$sp arrival]\t[$pe data_arrival_time]\t[$pe target_clk_delay]\t[$pe data_required_time]\t[$pe slack]\t$nl\t$nc\t$nm\t[llength $pins]"
}
close $f
puts "paths [llength $pes]"
exit
