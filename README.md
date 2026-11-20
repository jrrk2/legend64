# legend64

An RV64GC processor core with supervisor mode and Sv39 virtual memory, a system-on-chip around
it for the Xilinx VC707 board (DDR3, gigabit Ethernet, UART), and the software to boot Debian on
it from an NFS root.

    git clone --recurse-submodules <this repository>
    # or, in an existing clone:
    git submodule update --init --recursive

| Directory | |
|---|---|
| `rtl/` | the core: `legend64.sv`, its FPU and compressed-instruction decoder |
| `tb/`, `scripts/`, `sw/` | core testbenches, ISA-test and QEMU-lockstep scripts, benchmarks |
| `fpga/` | the SoC (`rtl/`), constraints, Vivado build script, boot monitor (`sw/`), testbenches, board scripts, the LiteDRAM configuration and generated core |
| `linux/` | kernel configuration and build script, the Ethernet driver, device tree, initramfs and Debian NFS-root scripts; see `linux/README.md` |
| `third_party/` | dependencies as submodules, below |
| `ref/` | `riscv-tests` (the ISA tests) and `picorv32` (comparison core for the benchmarks), as submodules |

## Dependencies

Submodules, each pinned to the commit the design was built and tested with:

| Submodule | Used for |
|---|---|
| `third_party/synthgui` | the Ethernet MAC (`eth_mac_1g`, from verilog-ethernet) and the generated LiteEth SGMII PHY, in `projects/vc707_ethmin-src`; read by `fpga/scripts/build.tcl` |
| `third_party/litex`, `litedram`, `migen` | the DDR3 controller generator (`fpga/litedram/gen.sh`) and `liblitedram`, the memory initialisation code compiled into the boot monitor |
| `third_party/opensbi` | the machine-mode firmware; `linux/build-opensbi.sh` builds `linux/out/fw_jump.bin` |
| `ref/riscv-tests` | `scripts/isa_legend64.sh` |
| `ref/picorv32` | the PicoRV32 comparison in `scripts/*pico*` |

Not submodules:

* The Linux kernel: `linux/build-kernel.sh` downloads the release tarball of the version it
  names and checks its SHA-256.
* Tools, installed or built separately and expected under `tools/` or on the path: Vivado
  2020.1, Verilator (5.032 as packaged faults on some of the testbenches; a current release
  built into `tools/verilator` is used if present), RISC-V GCC (bare-metal and Linux), QEMU,
  the Python packages LiteX needs, and a static BusyBox for the initramfs.

## Licence

Apache-2.0; the kernel driver is GPL-2.0. See `LICENSE` and `NOTICE`.
