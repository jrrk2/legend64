# SPDX-License-Identifier: Apache-2.0
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

# The configuration flash (U3, linear BPI, 16 bits wide). bpi_addr[n] is flash pin A<n+1>, net
# FLASH_A<n>. The two address lines above these (FLASH_A24/A25) are driven by switch SW11 and are
# left alone; FLASH_WAIT and the flash clock are not used (asynchronous cycles only).
set_property -dict {PACKAGE_PIN AJ28 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[0]}]
set_property -dict {PACKAGE_PIN AH28 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[1]}]
set_property -dict {PACKAGE_PIN AG31 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[2]}]
set_property -dict {PACKAGE_PIN AF30 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[3]}]
set_property -dict {PACKAGE_PIN AK29 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[4]}]
set_property -dict {PACKAGE_PIN AK28 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[5]}]
set_property -dict {PACKAGE_PIN AG29 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[6]}]
set_property -dict {PACKAGE_PIN AK30 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[7]}]
set_property -dict {PACKAGE_PIN AJ30 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[8]}]
set_property -dict {PACKAGE_PIN AH30 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[9]}]
set_property -dict {PACKAGE_PIN AH29 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[10]}]
set_property -dict {PACKAGE_PIN AL30 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[11]}]
set_property -dict {PACKAGE_PIN AL29 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[12]}]
set_property -dict {PACKAGE_PIN AN33 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[13]}]
set_property -dict {PACKAGE_PIN AM33 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[14]}]
set_property -dict {PACKAGE_PIN AM32 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[15]}]
set_property -dict {PACKAGE_PIN AV41 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[16]}]
set_property -dict {PACKAGE_PIN AU41 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[17]}]
set_property -dict {PACKAGE_PIN BA42 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[18]}]
set_property -dict {PACKAGE_PIN AU42 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[19]}]
set_property -dict {PACKAGE_PIN AT41 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[20]}]
set_property -dict {PACKAGE_PIN BA40 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[21]}]
set_property -dict {PACKAGE_PIN BA39 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[22]}]
set_property -dict {PACKAGE_PIN BB39 IOSTANDARD LVCMOS18} [get_ports {bpi_addr[23]}]
set_property -dict {PACKAGE_PIN AM36 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[0]}]
set_property -dict {PACKAGE_PIN AN36 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[1]}]
set_property -dict {PACKAGE_PIN AJ36 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[2]}]
set_property -dict {PACKAGE_PIN AJ37 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[3]}]
set_property -dict {PACKAGE_PIN AK37 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[4]}]
set_property -dict {PACKAGE_PIN AL37 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[5]}]
set_property -dict {PACKAGE_PIN AN35 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[6]}]
set_property -dict {PACKAGE_PIN AP35 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[7]}]
set_property -dict {PACKAGE_PIN AM37 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[8]}]
set_property -dict {PACKAGE_PIN AG33 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[9]}]
set_property -dict {PACKAGE_PIN AH33 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[10]}]
set_property -dict {PACKAGE_PIN AK35 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[11]}]
set_property -dict {PACKAGE_PIN AL35 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[12]}]
set_property -dict {PACKAGE_PIN AJ31 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[13]}]
set_property -dict {PACKAGE_PIN AH34 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[14]}]
set_property -dict {PACKAGE_PIN AJ35 IOSTANDARD LVCMOS18} [get_ports {bpi_dq[15]}]
set_property -dict {PACKAGE_PIN BB41 IOSTANDARD LVCMOS18} [get_ports bpi_we_n]
set_property -dict {PACKAGE_PIN BA41 IOSTANDARD LVCMOS18} [get_ports bpi_oe_n]
set_property -dict {PACKAGE_PIN AL36 IOSTANDARD LVCMOS18} [get_ports bpi_ce_n]
set_property -dict {PACKAGE_PIN AY37 IOSTANDARD LVCMOS18} [get_ports bpi_adv_n]

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

set_false_path -to [get_ports {LED[*] UART_TX eth_rst_n bpi_addr[*] bpi_dq[*] bpi_ce_n bpi_oe_n bpi_we_n bpi_adv_n}]
set_false_path -from [get_ports {GPIO_DIP_SW[*] GPIO_SW[*] UART_RX sys_rst bpi_dq[*]}]

# Register retiming for our own logic only. Applied to the whole design it also moves registers
# inside the memory interface's calibration logic.
set_property BLOCK_SYNTH.RETIMING 1 [get_cells u_soc]
