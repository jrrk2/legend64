# Generate the DDR3 memory interface for the VC707 from the board preset, with two changes:
# the native user interface instead of AXI, and the extra MMCM outputs set to the system
# clock (800 MHz / SYS_DIV) and the 100 MHz MAC clock.
# usage: vivado -mode batch -source gen_mig.tcl -tclargs <out_dir> <sys_div>
set out [lindex $argv 0]
set sys_div [lindex $argv 1]
set preset /opt/Xilinx/Vivado/2020.1/data/boards/board_files/vc707/1.4/mig.prj
file mkdir $out
set f [open $preset r]; set prj [read $f]; close $f
regsub {<ModuleName>[^<]*</ModuleName>} $prj {<ModuleName>ddr3_mig</ModuleName>} prj
regsub {<MMCMClkOut0>[^<]*</MMCMClkOut0>} $prj "<MMCMClkOut0> [format %.3f $sys_div]</MMCMClkOut0>" prj
regsub {<MMCMClkOut1>[^<]*</MMCMClkOut1>} $prj {<MMCMClkOut1>8</MMCMClkOut1>} prj
regsub {<PortInterface>AXI</PortInterface>} $prj {<PortInterface>NATIVE</PortInterface>} prj
regsub {<AXIParameters>.*</AXIParameters>} $prj {} prj
set f [open $out/mig.prj w]; puts -nonewline $f $prj; close $f

create_project -in_memory -part xc7vx485tffg1761-2
set_property board_part xilinx.com:vc707:part0:1.4 [current_project]
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name ddr3_mig -dir $out
set_property CONFIG.XML_INPUT_FILE [file normalize $out/mig.prj] [get_ips ddr3_mig]
generate_target all [get_ips ddr3_mig]
puts "MIG_DONE"
