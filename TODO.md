# legend64 task list

Roughly in priority order within each section. Measurements are from the VC707 at 50 MHz.

## In progress

- **A kernel oops seen once on the board:** the trap handler entered a second time while still on
  user registers (`handle_exception+0x8c`, in `systemd-sysctl`). Looks like a rare fault in the
  core's trap or interrupt entry. Not reproduced, not investigated.
- **Reserve boot and settings in flash:** a JFFS2 filesystem in the flash's `reserve` partition
  (12 MiB) holding a settings file (MAC address, IP address, TFTP server, boot order) and a
  reserve kernel with a small root for when the network is away. The read-only JFFS2 reader is
  written and tested on the host (`scripts/test_jffs2.sh`); the monitor does not use it yet and
  the partition is blank.
- **Timing margin:** the build with the flash bridge closes at +0.056 ns.

## Done recently

- synthgui's open flow: the silent bitstream was the mapper dropping a part-select write at an
  offset that is not a multiple of its width (the fetch buffer's
  `win_data[16*buf_cnt +: 32] = arr_word`), found by running RTL and netlist side by side
  (`synthgui/netlist_compare.py`); fixed in `synthgui/patches/0005`, initial contents in `0006`.
  The open-flow bitstream now brings the monitor up on the board at 12.5 MHz.
- Boot with no host script: the monitor fetches firmware, kernel and device tree by TFTP
  (tftpd-hpa on the host, `/srv/tftp/legend64/`); the flash holds such a build, so power-on goes
  to a Debian login by itself.
- A reset branch on every register except the memories; no cost in timing or area.
- The configuration flash from the SoC: `legend_flash.sv` maps the selected 32 MiB image at
  `0x6000_0000`; the monitor identifies, erases, programs and verifies it; Linux sees it as two
  MTD partitions (`bitstream`, `reserve`); `reboot` reloads the FPGA from flash through ICAPE2.
  All of it runs on the board: the flash was rewritten twice through the SoC
  (`netload.py --flash ... --reconfigure`), and `reboot` under Linux brings the board back.
- TCP transmit loss with segmentation: the MAC's transmit side counted its inter-frame gap only
  once after reset (see `fpga/third_party/verilog-ethernet/`). Sending is now 68 Mbit/s with no
  retransmits.
- Rocket comparison on the same NFS root: see the measurements in the commit that added this.

## Memory system

- Second-level TLB consulted on a miss, and ASIDs so that a context switch does not flush the
  TLBs. (32-entry first-level TLBs meet timing at +0.003 ns; decide whether to keep them.)
- Split or set-associative caches; today one direct-mapped cache serves instructions, data and
  the Ethernet DMA. Design it with multi-core coherence in mind.
- Cheaper misses: skip the read when a whole line is about to be overwritten (receive DMA,
  sequential fills), next-line prefetch.
- Timing margin: the 1 MiB cache build closes at +0.11 ns.

## Ethernet

- Receive FIFO still overflows now and then under iperf3 (drain into memory is slower than the
  wire when lines miss).
- Jumbo frames (hardware limit is 1518 bytes; needs host and switch MTU changes too).
- Consider moving to verilog-ethernet's current MAC; the copy in use is a 2019 fork of it.
- Second stage of offloading: the full flow engine from vc707_romlinux_toe, kernel-driven.
- Hardware receive coalescing, if measurements justify it once transmit is fixed.

## Core

- A real `wfi` (today it is a no-op, so the idle loop spins).
- Faster divider (66 cycles, fixed).
- Higher clock: the pipeline's long paths limit it to 50 MHz.
- SMP: needs per-core caches with coherence, atomics that hold a line exclusively, per-hart
  interrupt plumbing, and a multi-core stress test.
- Performance counters, debug module.

## Low priority

- **PMP (physical memory protection).** Not implemented: the firmware cannot fence its memory
  off from the kernel, and the `rv64mi-pmpaddr` ISA test fails. Process and kernel/user
  protection through Sv39 is complete and unaffected. The comparisons would sit on the address
  path that limits the clock, so do it after the memory-system work.
- Misaligned loads and stores trap (`ma_data` tests fail); firmware emulation or hardware support.
- UART transmit FIFO (the device tree says `ns16550`, not `ns16550a`, because there is none).
- Why the Xilinx memory interface never calibrates in this design (LiteDRAM is used instead).

## Housekeeping

- Move the NFS export to `/srv/nfs/legend64` and set the hostname inside the tree (needs root on
  the host), then update `nfsroot=` in `linux/dts/legend64-vc707.dts`.
- Writing the flash from Linux needs `mtd-utils` in the NFS tree and root on the board.
- The open flow leaves the flash pins and ICAPE2 out (`make_project.py` has not been taught them).
- Serial password login times out; probably the 6.7 s yescrypt hash plus slow start-up, unconfirmed.
- Decide whether `third_party/synthgui` stays a submodule or its five source files are copied in.
- Rename the working directory `~/riscv` when nothing is running in it.
