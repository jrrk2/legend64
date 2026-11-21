# SPDX-License-Identifier: Apache-2.0
# Place and route a netlist from synthgui's mapper with Vivado, to tell a fault in the mapping
# from one in the open place-and-route and bitstream tools: the same netlist, the same pins.
#   vivado -mode batch -source vivado_netlist.tcl -tclargs <netlist.edf> <open-flow xdc> <out dir> <core clock period ns> [explore|plain]
# The core clock's period is the netlist's own (its MMCM); `explore` runs the stages with the
# directives of the Vivado build of the RTL (fpga/scripts/build.tcl), to see how fast the
# mapper's netlist can go when Vivado tries as hard as it does there; `plain` places and routes
# and does nothing else, which measures the netlist itself.
lassign $argv edf xdc out period effort
file mkdir $out
set_part xc7vx485tffg1761-2
read_edif $edf
link_design -top legend64_vc707 -part xc7vx485tffg1761-2

# Pins, I/O standards and configuration properties come from the open flow's XDC; its clock and
# placement lines are for nextpnr (names with dots, clocks on nets) and are replaced below.
set fi [open $xdc r]; set fo [open $out/pins.xdc w]
while {[gets $fi line] >= 0} {
    if {[string match "set_property *get_ports*" $line] || [string match "set_property *current_design*" $line]} {
        puts $fo $line
    }
}
close $fi; close $fo
read_xdc $out/pins.xdc
# the DDR3 banks' reference voltage and DCI, which Vivado checks and the open flow does not model
set_property INTERNAL_VREF 0.75 [get_iobanks 37]
set_property INTERNAL_VREF 0.75 [get_iobanks 38]
set_property INTERNAL_VREF 0.75 [get_iobanks 39]
set_property DCI_CASCADE {37 38} [get_iobanks 39]

create_clock -name sys_clk_p -period 5.0 [get_ports sys_clk_p]
create_clock -name sgmii_refclk_p -period 8.0 [get_ports sgmii_refclk_p]
set gtx [get_cells -hierarchical -filter {REF_NAME == GTXE2_CHANNEL}]
create_clock -name eth_txout -period 16.0 [get_pins -of_objects $gtx -filter {REF_PIN_NAME == TXOUTCLK}]
create_clock -name eth_rxout -period 16.0 [get_pins -of_objects $gtx -filter {REF_PIN_NAME == RXOUTCLK}]
# the core's clock domain (the outputs of u_mmcm) is asynchronous to the memory controller's
set mmcm [get_cells -hierarchical -filter {NAME =~ *u_mmcm && REF_NAME =~ MMCME2*}]
set core_clks [get_clocks -of_objects [get_pins -of_objects $mmcm -filter {REF_PIN_NAME =~ CLKOUT* || REF_PIN_NAME == CLKFBOUT}]]
set mem_clks {}
foreach c [get_clocks -include_generated_clocks sys_clk_p] {
    if {[lsearch -exact $core_clks $c] < 0} {lappend mem_clks $c}
}
set_clock_groups -asynchronous -group $mem_clks -group $core_clks \
    -group [get_clocks -include_generated_clocks eth_txout] \
    -group [get_clocks -include_generated_clocks eth_rxout] -group [get_clocks sgmii_refclk_p]
set_false_path -to [get_ports {LED[*] UART_TX eth_rst_n}]
set_false_path -from [get_ports {GPIO_DIP_SW[*] GPIO_SW[*] UART_RX sys_rst}]
puts "core clocks: $core_clks"

if {$effort eq "explore"} {
    opt_design -directive Explore
    place_design -directive ExtraTimingOpt
    phys_opt_design -directive AggressiveExplore
    route_design -directive Explore
    phys_opt_design -directive AggressiveExplore
} elseif {$effort eq "plain"} {
    # place and route alone: the netlist as the mapper wrote it, with no logic optimisation,
    # replication or retiming by Vivado
    place_design
    route_design
} else {
    opt_design
    place_design
    phys_opt_design
    route_design
}
write_checkpoint -force $out/route.dcp
report_timing_summary -file $out/timing.rpt -max_paths 5
foreach c $core_clks {
    set p [get_timing_paths -quiet -setup -group $c -max_paths 1]
    if {$p ne {}} { puts "RESULT clock $c period [get_property PERIOD $c] slack [get_property SLACK $p] levels [get_property LOGIC_LEVELS $p] from [get_property STARTPOINT_PIN $p] to [get_property ENDPOINT_PIN $p]" }
}
report_utilization -file $out/util.rpt
report_drc -file $out/drc.rpt
puts "RESULT WNS=[get_property SLACK [get_timing_paths -max_paths 1 -setup]] WHS=[get_property SLACK [get_timing_paths -max_paths 1 -hold]]"
write_bitstream -force $out/legend64_vc707.bit
puts "RESULT bitstream written"
