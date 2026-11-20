#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Make the synthgui project for legend64 on the VC707: legend64_vc707.json and its constraints
file legend64_vc707_open.xdc, both written beside this script.

    make_project.py [--synthgui DIR] [--clk-mhz N] [--cache-log2 N] [--tlb N]

synthgui (github.com/jrrk2/synthgui) is an open FPGA flow: a Verilator-based mapper, nextpnr,
prjxray. Its projects are JSON files; this one takes its tool paths, pipeline steps and place and
route options from an existing VC707 project there (vc707_romlinux, which has the same DDR3
PHY and SGMII PHY) and points at this repository's sources, by paths relative to the project file. Vivado sets the top level's
parameters with -generic; here they go to the mapper as -G options, in the "params" field.

The constraints are in the form the open flow reads: one property per line, clocks on ports and
named nets. The DDR3 pins and their I/O standards, and the placement of the transceiver and its
clock buffers, are taken from that same project's XDC with the port and cell names changed, so
they are the ones already proven in this flow.
"""
import argparse, json, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
legend = os.path.dirname(here)
ap = argparse.ArgumentParser()
ap.add_argument('--synthgui', default=os.path.join(legend, 'third_party', 'synthgui'))
ap.add_argument('--clk-mhz', type=float, default=25.0, help='core clock; 1000/clk must suit the MMCM')
ap.add_argument('--cache-log2', type=int, default=10)
ap.add_argument('--tlb', type=int, default=8)
ap.add_argument('--timing-passes', type=int, default=2, help='timing-driven mapping passes after the first; -1 leaves the mapper\'s timing analysis off')
ap.add_argument('--timing-margin', type=float, help='ns the mapper aims to beat each constraint by (its default: a fifth of the period)')
ap.add_argument('--max-fanout', type=int, default=32)
ap.add_argument('--mapper-flags', default='', help='more options for the mapper, e.g. --map-only-abc-script "..."')
ap.add_argument('--out', default='legend64_vc707', help='name of the project file and of its work directory, for experiments')
ap.add_argument('--verilator', help="the mapper binary, if not synthgui's own (see patches/)")
ap.add_argument('--verilator-root', help='and its VERILATOR_ROOT')
args = ap.parse_args()

ref_json = os.path.join(args.synthgui, 'projects', 'vc707_romlinux.json')
ref_xdc = os.path.join(args.synthgui, 'projects', 'vc707_romlinux-src', 'xilinx_vc707.xdc')
ref = json.load(open(ref_json))

# ---------------------------------------------------------------- project file
eth = '{root}/projects/vc707_ethmin-src'
sources = [
    '../rtl/legend64.sv', '../rtl/legend64_rvc.sv', '../rtl/legend64_fpu.sv',
    '../fpga/rtl/legend_uart16550.sv', '../fpga/rtl/legend_plic.sv', '../fpga/rtl/legend_eth.sv',
    '../fpga/rtl/legend_ram.sv', '../fpga/rtl/legend_cache.sv', '../fpga/rtl/litedram_line_adapter.sv',
    '../fpga/rtl/legend64_soc.sv', '../fpga/rtl/legend_sgmii.sv', '../fpga/rtl/legend64_vc707.sv',
    '../fpga/rtl/legend_flash.sv',                  # legend_reconfig.sv (ICAPE2) is left out: RECONFIG=0 below

    '../build/synthgui/litedram_core_open.v',       # written below
    eth + '/liteeth_sgmii_phy.v', eth + '/eth_mac_1g.sv', eth + '/axis_gmii_rx.sv', '../fpga/third_party/verilog-ethernet/axis_gmii_tx.sv',   # corrected copy: see build.tcl
   
    eth + '/rgmii_lfsr.sv',
]
clk_hz = int(round(args.clk_mhz * 1e6))
proj = dict(ref)
proj.update({
    'name': 'legend64 RV64GC on the VC707 (LiteDRAM, SGMII)',
    'top': 'legend64_vc707',
    'work': '../build/synthgui/' + args.out,
    'xdc': 'legend64_vc707_open.xdc',
    'srcdir': '../fpga/rtl',
    'sources': sources,
    'incdirs': ['../fpga/rtl'],
    'defines': ['SYNTHESIS'],
    'params': "-GLITEDRAM=1 -GSYS_DIV=%.3f -GCLK_HZ=%d -GBUILD_ID=24064 -GRECONFIG=0 -GCACHE_LINES_LOG2=%d -GTLB_ENTRIES=%d "
              # the boot monitor image (fpga/sw/Makefile), relative to the work directory, where the steps run
              "-GBOOT_HEX='\"../../fpga/boot.hex\"'"
              % (1000.0 / args.clk_mhz, clk_hz, args.cache_log2, args.tlb)
              + ('' if args.timing_passes < 0 else
                 # timing-driven mapping against the clocks in legend64_vc707_synth.sdc (written below)
                 ' --map-only-sdc ../../../synthgui/legend64_vc707_synth.sdc --map-only-pins ../../../synthgui/legend64_vc707_open.xdc --map-only-timing-report legend64_vc707_timing.rpt'
                 ' --map-only-timing-iterations %d --map-only-max-fanout %d' % (args.timing_passes, args.max_fanout)
                 + ('' if args.timing_margin is None else ' --map-only-timing-margin %g' % args.timing_margin))
              + (' ' + args.mapper_flags if args.mapper_flags else ''),
    'blackboxes': sorted(set(ref['blackboxes']) | {'MMCME2_BASE', 'PLLE2_ADV'}),
})
proj.pop('bpi_bridge_dir', None)
# The mapper's timing analysis is given its own constraint file through `params` above, not the
# XDC through synthgui's option: nextpnr wants the generated clocks defined on nets, the mapper
# on the pins that make them, and neither reads the other's form.
proj['options'] = {k: v for k, v in ref.get('options', {}).items() if k != 'synth.timing'}
steps = []
for s in ref['steps']:
    s = dict(s)
    if s['id'] == 'synth':
        assert '{defines}' in s['command']
        s['command'] = s['command'].replace('{defines}', '{defines} {params}')
    if s['id'] == 'program_flash':
        continue                      # this design is only ever loaded over JTAG
    steps.append(s)
proj['steps'] = steps
if args.verilator:
    proj['verilator'] = os.path.abspath(args.verilator)
if args.verilator_root:
    proj['verilator_root'] = os.path.abspath(args.verilator_root)
json.dump(proj, open(os.path.join(here, args.out + '.json'), 'w'), indent=2)

# ---------------------------------------------------------------- the DDR3 core for this flow
# nextpnr configures a PLLE2_ADV only with COMPENSATION "INTERNAL"; the generated core leaves the
# parameter at its default (ZHOLD), which Vivado resolves by itself for a PLL fed back internally,
# as this one is. The copy used here states it.
core = open(os.path.join(legend, 'fpga', 'litedram', 'build', 'gateware', 'litedram_core.v')).read()
assert core.count('PLLE2_ADV #(') == 1
core = core.replace('PLLE2_ADV #(', 'PLLE2_ADV #(\n\t.COMPENSATION      ("INTERNAL"),', 1)
os.makedirs(os.path.join(legend, 'build', 'synthgui'), exist_ok=True)
open(os.path.join(legend, 'build', 'synthgui', 'litedram_core_open.v'), 'w').write(core)

# ---------------------------------------------------------------- constraints
port_map = {
    'cpu_reset': 'sys_rst', 'clk200_p': 'sys_clk_p', 'clk200_n': 'sys_clk_n',
    'serial_rx': 'UART_RX', 'serial_tx': 'UART_TX', 'eth_rst_n': 'eth_rst_n',
    'eth_rx_p': 'sgmii_rxp', 'eth_rx_n': 'sgmii_rxn', 'eth_tx_p': 'sgmii_txp', 'eth_tx_n': 'sgmii_txn',
    'sgmii_clock_p': 'sgmii_refclk_p', 'sgmii_clock_n': 'sgmii_refclk_n',
    'ddram64_ras_n': 'ddr3_ras_n', 'ddram64_cas_n': 'ddr3_cas_n', 'ddram64_we_n': 'ddr3_we_n',
    # the top level declares these five as one-bit vectors; the mapper's netlist has them as
    # scalars, so that is how they must be named here (with [0] they matched nothing, and the
    # clock, clock enable, chip select and termination pins of the DDR3 went unconstrained)
    'ddram64_reset_n': 'ddr3_reset_n', 'ddram64_clk_p': 'ddr3_ck_p', 'ddram64_clk_n': 'ddr3_ck_n',
    'ddram64_cke': 'ddr3_cke', 'ddram64_cs_n': 'ddr3_cs_n', 'ddram64_odt': 'ddr3_odt',
}
bus_map = {'ddram64_a': ('ddr3_addr', 14), 'ddram64_ba': ('ddr3_ba', 3), 'ddram64_dm': ('ddr3_dm', 8),
           'ddram64_dq': ('ddr3_dq', 64), 'ddram64_dqs_p': ('ddr3_dqs_p', 8), 'ddram64_dqs_n': ('ddr3_dqs_n', 8)}
for i in range(8):
    port_map['user_led%d' % i] = 'LED[%d]' % i

out = ['# Constraints for legend64 on the VC707 in synthgui\'s open flow (nextpnr).',
       '# Generated by make_project.py from the XDC of synthgui\'s vc707_romlinux project; do not edit.',
       '']
dropped = set()
for line in open(ref_xdc):
    line = line.rstrip('\n')
    m = re.search(r'\[get_ports \{?([A-Za-z0-9_]+)(\[(\d+)\])?\}?\]', line)
    if line.startswith('set_property') and m:
        name, idx = m.group(1), m.group(3)
        if idx is not None and name in bus_map:
            new, width = bus_map[name]
            if int(idx) >= width:
                continue
            port = '%s[%s]' % (new, idx)
        elif idx is None and name in port_map:
            port = port_map[name]
        else:
            dropped.add(name)
            continue
        out.append(line[:m.start()] + '[get_ports {%s}]' % port)
    elif line.startswith('set_property') and 'get_cells liteeth_sgmii_phy.' in line:
        out.append(line.replace('get_cells liteeth_sgmii_phy.', 'get_cells u_eth.i_phy.'))
    elif line.startswith('set_property') and '[current_design]' in line:
        out.append(line)

# the switches and the flash, which that project does not use: from this repository's Vivado constraints
out.append('')
for line in open(os.path.join(legend, 'fpga', 'legend64_vc707.xdc')):
    m = re.match(r'set_property -dict \{PACKAGE_PIN (\S+) IOSTANDARD (\S+)\} \[get_ports \{?((GPIO_DIP_SW|GPIO_SW|bpi_addr|bpi_dq)\[\d+\]|bpi_[a-z]+_n)\}?\]', line)
    if m:
        out.append('set_property LOC %s [get_ports {%s}]' % (m.group(1), m.group(3)))
        out.append('set_property IOSTANDARD %s [get_ports {%s}]' % (m.group(2), m.group(3)))

out += ['',
        'create_clock -name sys_clk_p -period 5.0 [get_ports sys_clk_p]',
        'create_clock -name sgmii_refclk_p -period 8.0 [get_ports sgmii_refclk_p]',
        'create_clock -name eth_tx_clk -period 8.0 [get_nets eth_tx_clk]',
        'create_clock -name eth_rx_clk -period 8.0 [get_nets eth_rx_clk]',
        'create_clock -name clk_sys -period %.3f [get_nets clk_sys]' % (1000.0 / args.clk_mhz),
        # the transceiver's two 62.5 MHz output clocks, which feed the PHY's MMCMs
        'create_clock -name eth_txout -period 16.0 [get_nets u_eth.i_phy.k7_1000basex_s7mmcm0_clkin_signal]',
        'create_clock -name eth_rxout -period 16.0 [get_nets u_eth.i_phy.k7_1000basex_rxoutclk_rebuffer]',
        'set_clock_groups -group [get_clocks -of [get_nets eth_tx_clk]] -group [get_clocks -of [get_nets eth_rx_clk]] -asynchronous',
        'set_clock_groups -group [get_clocks -of [get_nets eth_tx_clk]] -group [get_clocks -of [get_nets clk_sys]] -asynchronous',
        'set_clock_groups -group [get_clocks -of [get_nets eth_rx_clk]] -group [get_clocks -of [get_nets clk_sys]] -asynchronous',
        'set_clock_groups -group [get_clocks -of [get_nets clk_sys]] -group [get_clocks -of [get_nets mem_clk]] -asynchronous',
        '']
open(os.path.join(here, 'legend64_vc707_open.xdc'), 'w').write('\n'.join(out))

# ---------------------------------------------------------------- the mapper's timing constraints
# Every clock is named where it is made, which also makes each a domain of its own: the mapper
# relates only the clocks it derives itself from an MMCM or PLL (the memory interface's, and the
# 125 MHz Ethernet clocks from the transceiver's two outputs), and paths between the domains
# named here all go through synchronisers or held-steady handshakes, as in the Vivado constraints.
sdc = ['# Timing constraints for the mapper (verilator --map-only-sdc) for legend64 on the VC707.',
       '# Generated by make_project.py; do not edit.',
       'create_clock -name sys_clk_p -period 5.000 [get_ports sys_clk_p]',
       'create_clock -name sgmii_refclk -period 8.000 [get_ports sgmii_refclk_p]',
       'create_clock -name clk_sys -period %.3f [get_pins u_mmcm/CLKOUT0]' % (1000.0 / args.clk_mhz),
       'create_clock -name clk_mac -period 8.000 [get_pins u_mmcm/CLKOUT1]',
       'create_clock -name eth_txout -period 16.000 [get_pins u_eth_i_phy_GTXE2_CHANNEL/TXOUTCLK]',
       'create_clock -name eth_rxout -period 16.000 [get_pins u_eth_i_phy_GTXE2_CHANNEL/RXOUTCLK]',
       '']
open(os.path.join(here, 'legend64_vc707_synth.sdc'), 'w').write('\n'.join(sdc))
print('wrote legend64_vc707.json and legend64_vc707_open.xdc (%d constraint lines); ports of the reference left out: %s'
      % (len(out), ', '.join(sorted(dropped))))
