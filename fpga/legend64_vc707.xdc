# legend64 on the VC707. The DDR3 pins and the 200 MHz system clock (sys_clk_p/n) are constrained
# by the memory interface's own XDC. This file is Tcl (read with read_xdc -unmanaged).
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
# Do not hold the start-up sequence for the DCI impedance match: on this board it never
# reports a match and the FPGA would stay unconfigured (DONE low, fan off).
set_property BITSTREAM.STARTUP.MATCH_CYCLE NoWait [current_design]

set_property -dict {PACKAGE_PIN AV40 IOSTANDARD LVCMOS18} [get_ports sys_rst]
set_property -dict {PACKAGE_PIN AM39 IOSTANDARD LVCMOS18} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN AN39 IOSTANDARD LVCMOS18} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN AR37 IOSTANDARD LVCMOS18} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN AT37 IOSTANDARD LVCMOS18} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN AR35 IOSTANDARD LVCMOS18} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN AP41 IOSTANDARD LVCMOS18} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN AP42 IOSTANDARD LVCMOS18} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN AU39 IOSTANDARD LVCMOS18} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN AU36 IOSTANDARD LVCMOS18} [get_ports UART_TX]
set_property -dict {PACKAGE_PIN AU33 IOSTANDARD LVCMOS18} [get_ports UART_RX]
set_property -dict {PACKAGE_PIN AV30 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[0]}]
set_property -dict {PACKAGE_PIN AY33 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[1]}]
set_property -dict {PACKAGE_PIN BA31 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[2]}]
set_property -dict {PACKAGE_PIN BA32 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[3]}]
set_property -dict {PACKAGE_PIN AW30 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[4]}]
set_property -dict {PACKAGE_PIN AY30 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[5]}]
set_property -dict {PACKAGE_PIN BA30 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[6]}]
set_property -dict {PACKAGE_PIN BB31 IOSTANDARD LVCMOS18} [get_ports {GPIO_DIP_SW[7]}]
set_property -dict {PACKAGE_PIN AV39 IOSTANDARD LVCMOS18} [get_ports {GPIO_SW[0]}]
set_property -dict {PACKAGE_PIN AW40 IOSTANDARD LVCMOS18} [get_ports {GPIO_SW[1]}]
set_property -dict {PACKAGE_PIN AP40 IOSTANDARD LVCMOS18} [get_ports {GPIO_SW[2]}]
set_property -dict {PACKAGE_PIN AU38 IOSTANDARD LVCMOS18} [get_ports {GPIO_SW[3]}]
set_property -dict {PACKAGE_PIN AR40 IOSTANDARD LVCMOS18} [get_ports {GPIO_SW[4]}]

# SGMII to the Marvell PHY, 125 MHz reference
set_property PACKAGE_PIN AH8 [get_ports sgmii_refclk_p]
set_property PACKAGE_PIN AH7 [get_ports sgmii_refclk_n]
set_property PACKAGE_PIN AN2 [get_ports sgmii_txp]
set_property PACKAGE_PIN AN1 [get_ports sgmii_txn]
set_property PACKAGE_PIN AM8 [get_ports sgmii_rxp]
set_property PACKAGE_PIN AM7 [get_ports sgmii_rxn]
set_property -dict {PACKAGE_PIN AJ33 IOSTANDARD LVCMOS18} [get_ports eth_rst_n]

create_clock -period 8.000 -name sgmii_refclk [get_ports sgmii_refclk_p]
# the transceiver's 62.5 MHz output clocks; the PHY's MMCMs derive the 125 MHz GMII clocks
create_clock -period 16.000 -name eth_txout [get_pins u_eth/i_phy/GTXE2_CHANNEL/TXOUTCLK]
create_clock -period 16.000 -name eth_rxout [get_pins u_eth/i_phy/GTXE2_CHANNEL/RXOUTCLK]

# Every crossing between these domains goes through a synchroniser or a held-steady handshake:
#   memory interface clocks | core clock | MAC clock | PCS transmit | PCS receive
set sys_clks [get_clocks -of_objects [get_pins {u_mmcm/CLKOUT0 u_mmcm/CLKFBOUT}]]
set mac_clks [get_clocks -of_objects [get_pins u_mmcm/CLKOUT1]]
set mig_clks {}
foreach c [get_clocks -include_generated_clocks sys_clk_p] {
    if {[lsearch -exact [concat $sys_clks $mac_clks] $c] < 0} {lappend mig_clks $c}
}
set_clock_groups -asynchronous \
    -group $mig_clks -group $sys_clks -group $mac_clks \
    -group [get_clocks -include_generated_clocks eth_txout] \
    -group [get_clocks -include_generated_clocks eth_rxout] \
    -group [get_clocks sgmii_refclk]

set_false_path -to [get_ports {LED[*] UART_TX eth_rst_n}]
set_false_path -from [get_ports {GPIO_DIP_SW[*] GPIO_SW[*] UART_RX sys_rst}]

# Register retiming for our own logic only. Applied to the whole design it also moves registers
# inside the memory interface's calibration logic.
set_property BLOCK_SYNTH.RETIMING 1 [get_cells u_soc]
