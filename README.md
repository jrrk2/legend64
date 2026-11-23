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
| `fpga/` | the SoC (`rtl/`), constraints, Vivado build script, boot monitor (`sw/`), testbenches, board scripts, the LiteDRAM configuration and generated core, and a corrected copy of the MAC's transmit side (`third_party/`) |
| `synthgui/` | the same design as a project for synthgui's open flow (its Verilator-based mapper, nextpnr, prjxray), and patches for that mapper |
| `linux/` | kernel configuration and build script, the Ethernet driver, device tree, initramfs and Debian NFS-root scripts; see `linux/README.md` |
| `third_party/` | dependencies as submodules, below |
| `ref/` | `riscv-tests` (the ISA tests) and `picorv32` (comparison core for the benchmarks), as submodules |

## Measured against Rocket and CVA6

Three systems on the same VC707 (xc7vx485t-2), each built with Vivado 2020.1, each booting the
same Debian NFS root and running the same binaries (GCC 15.2 `-O2 -march=rv64gc`), one core
each:

* **legend64**, this repository at 100 MHz (build `0000200e`), with one 1 MiB direct-mapped
  cache shared by instructions, data and the Ethernet MAC.
* **Rocket**, `rocket64b1` from vivado-risc-v at 100 MHz, 16 KiB caches.
* **CVA6**, at 50 MHz, the frequency its FPGA build is given.

Speed, on the board under Linux:

| | legend64, 100 MHz | Rocket, 100 MHz | CVA6, 50 MHz |
|---|---|---|---|
| CoreMark, iterations/s | **237.0** | 220.6 | 76.7 |
| CoreMark per MHz | 2.37 | 2.21 | 1.53 |
| Dhrystone 2.1, per second | 237,154 | **313,808** | 83,426 |
| Whetstone, double precision, MIPS | 120.0 | **214.3** | 130.4 |
| iperf3 TCP, board sends, Mbit/s | **135** | 50.5 | 14.1 |
| iperf3 TCP, board receives, Mbit/s | **114** | 22.5 | 17.9 |
| Cold read of 35 MB over NFS, MB/s | **8.6** | 2.2 | 1.4 |

Area, the whole system on chip after place and route:

| | legend64 | Rocket | CVA6 |
|---|---|---|---|
| LUTs | **23,801** | 58,308 | 78,813 |
| Flip-flops | **14,519** | 37,623 | 52,002 |
| Block RAM tiles | 314.5 | **15** | 78.5 |
| DSP48 | 25 | 15 | 27 |
| of which the DDR3 controller, LUTs | 4,571 (LiteDRAM) | 13,930 (MIG and AXI) | 15,141 (MIG) |
| of which the core and its bus, LUTs | 18,632 (SoC, flattened) | 37,204 | 47,277 |

How to read these:

* legend64 is the smallest in logic by more than a factor of two and the largest in block RAM.
  Nearly all of its 314 block RAMs are the 1 MiB cache, against 16 KiB caches in this Rocket;
  the cache size is a build parameter (64 KiB by default), and the figures above are for 1 MiB.
* Rocket is faster on Dhrystone and much faster in floating point; legend64's FPU takes
  several cycles per operation. legend64 is ahead on CoreMark and well ahead wherever the
  network and memory system count.
* The network and NFS rows measure each system's own Ethernet MAC, driver and memory
  controller as much as its core.
* The legend64 and Rocket figures were taken with the board otherwise idle. The CVA6 run was
  taken with a load average between 1 and 2.5, and its figures may be a few percent low.
* Timing: legend64 meets 100 MHz with +0.001 ns of setup slack, Rocket with +0.177 ns.

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
